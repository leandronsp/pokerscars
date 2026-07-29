defmodule Pokerscars.Table.View do
  @moduledoc """
  A player's projection of the table — the one place that decides what a
  socket may see. Hole cards render only for the hero, everyone else's stay
  `:hidden` until a showdown reveals the contenders'. The web layer renders
  this struct verbatim and never touches server state.
  """

  alias Pokerscars.Engine.{BettingRound, Card, Hand}
  alias Pokerscars.Table.{Ledger, Server}

  defmodule SeatView do
    @moduledoc "One seat as a given player sees it."

    alias Pokerscars.Engine.{Card, Seat}

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
      hero?: false
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
            hero?: boolean()
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
    hand_no: 0,
    board: [],
    pot: 0,
    settlement: []
  ]

  @type turn :: %{position: non_neg_integer(), deadline_ms: integer(), total_ms: pos_integer()}
  @type result :: %{reason: :uncontested | :showdown, payouts: %{String.t() => non_neg_integer()}}
  @type t :: %__MODULE__{
          code: String.t(),
          name: String.t(),
          blinds: {pos_integer(), pos_integer()},
          seats: [SeatView.t()],
          phase: Hand.phase() | nil,
          turn: turn() | nil,
          result: result() | nil,
          hero_actions: [
            BettingRound.action()
            | {:call, non_neg_integer()}
            | {:raise_to, non_neg_integer(), non_neg_integer()}
          ],
          hand_no: non_neg_integer(),
          board: [Card.t()],
          pot: non_neg_integer(),
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
      board: (state.hand && state.hand.board) || [],
      pot: pot(state.hand),
      seats: Enum.map(0..(@max_seats - 1), &seat_view(state, &1, hero_position)),
      turn: turn(state),
      result: state.hand && state.hand.result,
      hero_actions: hero_actions(state.hand, hero_position),
      settlement: Ledger.settlement(state.ledger, live_stacks(state))
    }
  end

  defp seat_view(state, position, hero_position) do
    info = Map.get(state.seats, position)
    played = state.hand && Enum.find(state.hand.round.seats, &(&1.position == position))
    hero? = position == hero_position

    # While the hand runs its stacks are the truth; once complete they have
    # been copied home to the seats (which also carry rebuys since).
    live_stack =
      if state.hand && state.hand.phase != :complete && played,
        do: played.stack,
        else: info && info.stack

    %SeatView{
      position: position,
      nickname: info && info.nickname,
      stack: live_stack,
      committed: (played && played.committed) || 0,
      state: (played && played.hand_state) || :idle,
      cards: cards(state.hand, played, hero?),
      dealer?: state.button == position and state.hand != nil,
      to_act?: state.hand != nil and state.hand.round.to_act == position,
      hero?: hero?
    }
  end

  defp cards(_hand, nil, _hero?), do: nil
  defp cards(_hand, %{hand_state: :folded}, _hero?), do: nil
  defp cards(_hand, played, true), do: played.hole_cards

  defp cards(%Hand{phase: :complete, result: %{reason: :showdown}}, played, _hero?),
    do: played.hole_cards

  defp cards(_hand, _played, _hero?), do: :hidden

  defp pot(nil), do: 0
  defp pot(%Hand{} = hand), do: hand.round.seats |> Enum.map(& &1.contributed) |> Enum.sum()

  defp turn(%{hand: %Hand{round: %{to_act: position}}} = state) when position != nil do
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
