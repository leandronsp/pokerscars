defmodule Pokerscars.Table.View do
  @moduledoc """
  A player's projection of the table — the one place that decides what a
  socket may see. Hole cards render only for the hero, everyone else's stay
  `:hidden` until a showdown reveals the contenders'. The web layer renders
  this struct verbatim and never touches server state.
  """

  alias Pokerscars.Engine.{BettingRound, Card, Evaluator, Hand, HandRank, Pot, Seat}
  alias Pokerscars.Table.{Ledger, Server}

  defmodule SeatView do
    @moduledoc "One seat as a given player sees it."

    alias Pokerscars.Engine.{Card, HandRank, Seat}

    @enforce_keys [:position]
    defstruct [
      :position,
      :nickname,
      :stack,
      :cards,
      committed: 0,
      state: :idle,
      dealer?: false,
      to_act?: false,
      hero?: false,
      winner?: false,
      main_winner?: false,
      won: nil,
      aggressor?: false,
      mucked?: false,
      away?: false,
      hand_label: nil
    ]

    @type cards :: [Card.t()] | :hidden | nil
    @type t :: %__MODULE__{
            position: Seat.position(),
            nickname: String.t() | nil,
            stack: Seat.chips() | nil,
            cards: cards(),
            committed: Seat.chips(),
            state: Seat.hand_state() | :idle,
            dealer?: boolean(),
            to_act?: boolean(),
            hero?: boolean(),
            winner?: boolean(),
            main_winner?: boolean(),
            won: Seat.chips() | nil,
            aggressor?: boolean(),
            mucked?: boolean(),
            away?: boolean(),
            hand_label: HandRank.category() | nil
          }
  end

  @enforce_keys [:code, :name, :blinds, :seats]
  defstruct [
    :code,
    :name,
    :blinds,
    :seats,
    :phase,
    :turn,
    :result,
    :hero_actions,
    :hero_hand,
    hand_no: 0,
    board: [],
    pot: 0,
    pots: [],
    bet_to_match: 0,
    buy_in: %{min: 0, max: 0},
    clock_ms: 0,
    hero_leaving?: false,
    creator?: false,
    locked?: false,
    events: [],
    chat: [],
    settlement: []
  ]

  @type turn :: %{position: non_neg_integer(), deadline_ms: integer(), total_ms: pos_integer()}

  @typedoc "Payouts and winners keyed by nickname — player ids never reach the screen."
  @type result :: %{
          reason: :uncontested | :showdown,
          payouts: %{String.t() => non_neg_integer()},
          winners: [%{nickname: String.t(), category: HandRank.category() | nil}]
        }
  @type t :: %__MODULE__{
          code: String.t(),
          name: String.t(),
          blinds: {pos_integer(), pos_integer()},
          seats: [SeatView.t()],
          phase: Hand.phase() | nil,
          turn: turn() | nil,
          result: result() | nil,
          hero_hand: HandRank.category() | nil,
          hero_actions: [
            BettingRound.action()
            | {:call, non_neg_integer()}
            | {:raise_to, non_neg_integer(), non_neg_integer()}
          ],
          hand_no: non_neg_integer(),
          board: [Card.t()],
          pot: non_neg_integer(),
          pots: [non_neg_integer()],
          buy_in: %{min: non_neg_integer(), max: non_neg_integer()},
          clock_ms: non_neg_integer(),
          hero_leaving?: boolean(),
          creator?: boolean(),
          locked?: boolean(),
          events: [map()],
          chat: [map()],
          settlement: [Ledger.balance()]
        }

  @max_seats 9

  @doc "Projects the server state for `player_id` (a spectator when not seated)."
  @spec project(Server.t(), String.t()) :: t()
  def project(state, player_id) do
    hero_position = hero_position(state, player_id)

    %__MODULE__{
      code: state.code,
      name: state.name,
      blinds: state.blinds,
      hand_no: state.hand_no,
      phase: state.hand && state.hand.phase,
      board: revealed_board(state),
      pot: pot(state.hand),
      pots: pot_breakdown(state.hand),
      seats:
        Enum.map(
          0..(@max_seats - 1),
          &seat_view(state, &1, hero_position, winner_positions(state))
        ),
      turn: turn(state),
      bet_to_match: (state.hand && state.hand.round.bet_to_match) || 0,
      result: if(revealing?(state), do: nil, else: result(state)),
      hero_actions: if(clock_open?(state), do: hero_actions(state.hand, hero_position), else: []),
      hero_hand: hero_hand(state, hero_position),
      buy_in: state.buy_in,
      clock_ms: state.turn_ms,
      hero_leaving?: player_id in state.pending_stands,
      creator?: state.creator != nil and state.creator == player_id,
      locked?: state.password_hash != nil,
      events: Enum.take(state.events.log, 30),
      chat: state.chat.log,
      settlement: Ledger.settlement(state.ledger, live_stacks(state))
    }
  end

  defp seat_view(state, position, hero_position, winner_positions) do
    info = Map.get(state.seats, position)
    played = playing_seat(state, position)

    %SeatView{
      position: position,
      nickname: info && info.nickname,
      stack: stack(state, info, played),
      committed: (played && played.committed) || 0,
      state: (played && played.hand_state) || :idle,
      cards: cards(state, played, position == hero_position),
      dealer?: dealer?(state, position),
      to_act?: to_act?(state, position),
      hero?: position == hero_position,
      winner?: position in winner_positions,
      main_winner?: position in main_winner_positions(state),
      won: seat_won(state, info, position, winner_positions),
      aggressor?: aggressor?(state, position),
      mucked?: position in state.mucked,
      away?: info != nil and Map.get(state.presence, info.player_id) == 0,
      hand_label: revealed_label(state, played, position)
    }
  end

  # The made-hand name shown over every seat still standing at showdown,
  # unless that player chose to muck.
  defp revealed_label(
         %{hand: %Hand{phase: :complete, result: %{reason: :showdown}} = hand} = state,
         played,
         position
       ) do
    if not revealing?(state) and played != nil and played.hand_state != :folded and
         position not in state.mucked do
      Evaluator.evaluate(played.hole_cards ++ hand.board).category
    end
  end

  defp revealed_label(_state, _played, _position), do: nil

  defp winner_positions(%{hand: %Hand{phase: :complete, result: %{winners: winners}}} = state) do
    if revealing?(state), do: [], else: winners
  end

  defp winner_positions(_state), do: []

  # Action exists only while somebody is on the clock: one source of truth
  # for "may I act", perfectly in step with the revealed felt.
  defp clock_open?(%{hand: %Hand{phase: phase}} = state) when phase != :complete,
    do: state.turn_deadline != nil

  defp clock_open?(_state), do: false

  # While the table still drips out board cards, the view stays on the
  # previous street: no result, no winners, no showdown reveals.
  defp revealing?(%{hand: %Hand{board: board}} = state), do: state.reveal.done < length(board)
  defp revealing?(_state), do: false

  defp revealed_board(%{hand: nil}), do: []

  defp revealed_board(%{hand: %Hand{board: board}} = state),
    do: Enum.take(board, state.reveal.done)

  defp seat_won(_state, nil, _position, _winners), do: nil

  defp seat_won(
         %{hand: %Hand{phase: :complete, result: %{payouts: payouts}}},
         info,
         position,
         winners
       ) do
    # winners is already [] while the board is still being revealed.
    if position in winners, do: Map.get(payouts, info.player_id)
  end

  defp seat_won(_state, _info, _position, _winners), do: nil

  # The main pot's winners get the loudest celebration.
  defp main_winner_positions(%{hand: %Hand{phase: :complete, result: %{pots: [main | _side]}}}),
    do: main.winners

  defp main_winner_positions(_state), do: []

  defp aggressor?(%{hand: %Hand{phase: phase, round: round}}, position) when phase != :complete,
    do: round.last_aggressor == position

  defp aggressor?(_state, _position), do: false

  # The hero's current made hand, readable at a glance. Preflop only a pocket
  # pair is worth naming; from the flop on the evaluator tells the truth.
  defp hero_hand(_state, nil), do: nil
  defp hero_hand(%{hand: nil}, _hero_position), do: nil

  defp hero_hand(%{hand: %Hand{} = hand}, hero_position) do
    hand.round.seats
    |> Enum.find(&(&1.position == hero_position))
    |> hand_category(hand.board)
  end

  defp hand_category(nil, _board), do: nil
  defp hand_category(%Seat{hand_state: :folded}, _board), do: nil

  defp hand_category(%Seat{hole_cards: [first, second]}, []),
    do: if(first.rank == second.rank, do: :pair, else: :high_card)

  defp hand_category(%Seat{hole_cards: [_, _] = hole}, board),
    do: Evaluator.evaluate(hole ++ board).category

  defp hand_category(_seat, _board), do: nil

  defp playing_seat(%{hand: nil}, _position), do: nil

  defp playing_seat(state, position),
    do: Enum.find(state.hand.round.seats, &(&1.position == position))

  # While the hand runs its stacks are the truth; once complete they have
  # been copied home to the seats (which also carry rebuys since).
  defp stack(_state, nil, _played), do: nil
  defp stack(_state, info, nil), do: info.stack

  defp stack(%{hand: %Hand{phase: phase}}, info, %Seat{} = played) do
    if phase == :complete, do: info.stack, else: played.stack
  end

  defp dealer?(state, position), do: state.hand != nil and state.button == position

  defp to_act?(%{hand: %Hand{} = hand}, position), do: hand.round.to_act == position
  defp to_act?(_state, _position), do: false

  defp cards(_state, nil, _hero?), do: nil
  # Folded cards leave the table for everyone, the owner included.
  defp cards(_state, %{hand_state: :folded}, _hero?), do: nil

  # Mucking hides the cards from everyone, the owner included — flipping
  # your own cards down IS the feedback that the muck worked. This clause
  # must come before the hero one for that reason.
  defp cards(
         %{hand: %Hand{phase: :complete, result: %{reason: :showdown}}} = state,
         played,
         hero?
       ) do
    cond do
      # Still dealing the runout: showdown stays face-down for everyone.
      revealing?(state) -> if hero?, do: played.hole_cards, else: :hidden
      played.position in state.mucked -> :hidden
      true -> played.hole_cards
    end
  end

  defp cards(_state, played, true), do: played.hole_cards
  defp cards(_state, _played, _hero?), do: :hidden

  defp pot(nil), do: 0
  defp pot(%Hand{} = hand), do: hand.round.seats |> Enum.map(& &1.contributed) |> Enum.sum()

  # Main pot first, then side pots. Only swept contributions count (current
  # street bets still sit in front of the players, PokerStars-style), so the
  # split appears once an all-in layered a settled betting round.
  defp pot_breakdown(nil), do: []

  defp pot_breakdown(%Hand{} = hand) do
    swept =
      Enum.map(hand.round.seats, fn %Seat{} = seat ->
        %Seat{seat | contributed: seat.contributed - seat.committed}
      end)

    {pots, _refunds} = Pot.build(swept)
    Enum.map(pots, & &1.amount)
  end

  defp result(%{hand: %Hand{phase: :complete, result: result} = hand} = state) do
    nicknames =
      Map.new(hand.round.seats, fn seat ->
        {seat.player_id, nickname_of(state, seat.player_id)}
      end)

    winners =
      Enum.map(result.winners, fn position ->
        seat = Enum.find(hand.round.seats, &(&1.position == position))

        %{
          nickname: nicknames[seat.player_id],
          category: winner_category(hand, seat)
        }
      end)

    pots =
      Enum.map(result.pots, fn pot ->
        %{
          amount: pot.amount,
          winners:
            Enum.map(pot.winners, fn position ->
              seat = Enum.find(hand.round.seats, &(&1.position == position))
              nicknames[seat.player_id]
            end)
        }
      end)

    %{
      reason: result.reason,
      payouts: Map.new(result.payouts, fn {id, won} -> {nicknames[id], won} end),
      winners: winners,
      pots: pots
    }
  end

  defp result(_state), do: nil

  defp winner_category(%Hand{result: %{reason: :showdown}} = hand, seat),
    do: Evaluator.evaluate(seat.hole_cards ++ hand.board).category

  defp winner_category(_hand, _seat), do: nil

  # A winner may have stood up before the result rendered; the ledger still
  # remembers who they were. Raw player ids never reach the screen.
  defp nickname_of(state, player_id) do
    Enum.find_value(state.seats, fn {_position, seat} ->
      if seat.player_id == player_id, do: seat.nickname
    end) || ledger_nickname(state, player_id)
  end

  defp ledger_nickname(state, player_id) do
    Enum.find_value(state.ledger, "???", fn entry ->
      if entry.player_id == player_id, do: entry.nickname
    end)
  end

  defp turn(%{hand: %Hand{round: %{to_act: position}}} = state)
       when position != nil and state.turn_deadline != nil do
    %{position: position, deadline_ms: state.turn_deadline, total_ms: state.turn_ms}
  end

  defp turn(_state), do: nil

  defp hero_actions(%Hand{phase: phase, round: round}, hero_position)
       when phase != :complete and hero_position != nil do
    if round.to_act == hero_position, do: BettingRound.legal_actions(round), else: []
  end

  defp hero_actions(_hand, _hero_position), do: []

  defp hero_position(state, player_id) do
    Enum.find_value(state.seats, fn {position, seat} ->
      if seat.player_id == player_id, do: position
    end)
  end

  defp live_stacks(state) do
    live = Map.new(state.seats, fn {_position, seat} -> {seat.player_id, seat.stack} end)

    if state.hand && state.hand.phase != :complete do
      Enum.reduce(state.hand.round.seats, live, fn seat, acc ->
        Map.put(acc, seat.player_id, seat.stack + seat.contributed)
      end)
    else
      live
    end
  end
end
