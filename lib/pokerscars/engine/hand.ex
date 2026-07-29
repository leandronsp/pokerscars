defmodule Pokerscars.Engine.Hand do
  @moduledoc """
  One hand from shuffle to settlement, as a pure state machine. Commands come
  through `act/3`, invalid ones return `{:error, atom}` — player actions
  arrive from the network and are a boundary. Every street closes into either
  the next street, a board runout (betting dead), an uncontested win, or a
  showdown. See the lifecycle diagram in docs/engine-design.md.
  """

  alias Pokerscars.Engine.{BettingRound, Button, Card, Deck, Pot, Seat, Showdown}

  @enforce_keys [:round, :deck, :button, :blinds]
  defstruct [:round, :deck, :button, :blinds, board: [], phase: :preflop, result: nil]

  @type entrants :: %{Seat.position() => {String.t(), Seat.chips()}}
  @type blinds :: {Seat.chips(), Seat.chips()}
  @type phase :: BettingRound.street() | :complete
  @type result :: %{
          reason: :uncontested | :showdown,
          payouts: %{String.t() => Seat.chips()}
        }

  @type t :: %__MODULE__{
          round: BettingRound.t(),
          deck: Deck.t(),
          button: Seat.position(),
          blinds: blinds(),
          board: [Card.t()],
          phase: phase(),
          result: result() | nil
        }

  @streets [:preflop, :flop, :turn, :river]

  @doc "Shuffles, deals, posts blinds. Needs at least two entrants."
  @spec start(entrants(), Seat.position(), blinds(), Deck.seed()) :: t()
  def start(entrants, button, {small_blind, big_blind} = blinds, seed)
      when map_size(entrants) >= 2 do
    positions = entrants |> Map.keys() |> Enum.sort()
    {sb_position, bb_position} = Button.blind_positions(positions, button)

    {seats, deck} =
      positions
      |> Enum.map(fn position ->
        {player_id, stack} = Map.fetch!(entrants, position)
        %Seat{position: position, player_id: player_id, stack: stack}
      end)
      |> deal_hole_cards(Deck.new() |> Deck.shuffle(seed))

    seats =
      Enum.map(seats, fn seat ->
        case seat.position do
          ^sb_position -> Seat.commit(seat, small_blind)
          ^bb_position -> Seat.commit(seat, big_blind)
          _other -> seat
        end
      end)

    %__MODULE__{
      round: BettingRound.preflop(seats, big_blind, bb_position),
      deck: deck,
      button: button,
      blinds: blinds
    }
    |> maybe_advance()
  end

  @doc "Applies `player_id`'s action and advances streets as rounds close."
  @spec act(t(), String.t(), BettingRound.action()) ::
          {:ok, t()} | {:error, BettingRound.action_error() | :hand_complete}
  def act(%__MODULE__{phase: :complete}, _player_id, _action), do: {:error, :hand_complete}

  def act(%__MODULE__{} = hand, player_id, action) do
    seat = Enum.find(hand.round.seats, &(&1.player_id == player_id))

    if seat == nil or seat.position != hand.round.to_act do
      {:error, :not_your_turn}
    else
      with {:ok, round} <- BettingRound.apply_action(hand.round, action) do
        {:ok, maybe_advance(%__MODULE__{hand | round: round})}
      end
    end
  end

  defp maybe_advance(%__MODULE__{} = hand) do
    cond do
      # Checked before the round closes: the last contender never gets a turn
      # (an open fold there would leave the pot ownerless).
      contenders(hand) |> length() == 1 -> settle_uncontested(hand)
      not BettingRound.closed?(hand.round) -> hand
      hand.phase == :river -> settle_showdown(hand)
      betting_dead?(hand) -> hand |> run_out() |> settle_showdown()
      true -> hand |> next_street() |> maybe_advance()
    end
  end

  defp next_street(%__MODULE__{} = hand) do
    street = next_in(@streets, hand.phase)
    {board, deck} = deal_board(hand, street)

    seats =
      Enum.map(hand.round.seats, fn %Seat{} = seat ->
        %Seat{seat | committed: 0, acted_this_round?: false, may_raise?: true}
      end)

    first = Button.next(seats |> in_hand() |> Enum.map(& &1.position), hand.button)
    {_small, big_blind} = hand.blinds

    %__MODULE__{
      hand
      | phase: street,
        board: board,
        deck: deck,
        round: BettingRound.open(seats, street, big_blind, first)
    }
  end

  defp run_out(%__MODULE__{} = hand) do
    {board, deck} =
      Enum.reduce(streets_after(hand.phase), {hand.board, hand.deck}, fn street, {board, deck} ->
        {cards, deck} = Deck.deal(deck, cards_for(street))
        {board ++ cards, deck}
      end)

    %__MODULE__{hand | board: board, deck: deck}
  end

  defp settle_showdown(%__MODULE__{} = hand) do
    payouts = Showdown.settle(hand.round.seats, hand.board, hand.button)
    finish(hand, payouts, :showdown)
  end

  defp settle_uncontested(%__MODULE__{} = hand) do
    [winner] = contenders(hand)
    {pots, refunds} = Pot.build(hand.round.seats)
    pot_total = pots |> Enum.map(& &1.amount) |> Enum.sum()

    payouts = Map.update(refunds, winner.position, pot_total, &(&1 + pot_total))
    finish(hand, payouts, :uncontested)
  end

  defp finish(%__MODULE__{round: %BettingRound{} = round} = hand, payouts_by_position, reason) do
    seats =
      Enum.map(hand.round.seats, fn %Seat{} = seat ->
        %Seat{seat | stack: seat.stack + Map.get(payouts_by_position, seat.position, 0)}
      end)

    payouts =
      Map.new(payouts_by_position, fn {position, amount} ->
        {Enum.find(seats, &(&1.position == position)).player_id, amount}
      end)

    %__MODULE__{
      hand
      | phase: :complete,
        round: %BettingRound{round | seats: seats, to_act: nil},
        result: %{reason: reason, payouts: payouts}
    }
  end

  defp deal_hole_cards(seats, deck) do
    Enum.map_reduce(seats, deck, fn %Seat{} = seat, deck ->
      {cards, deck} = Deck.deal(deck, 2)
      {%Seat{seat | hole_cards: cards}, deck}
    end)
  end

  defp deal_board(hand, street) do
    {cards, deck} = Deck.deal(hand.deck, cards_for(street))
    {hand.board ++ cards, deck}
  end

  defp cards_for(:flop), do: 3
  defp cards_for(:turn), do: 1
  defp cards_for(:river), do: 1

  defp streets_after(phase), do: @streets |> Enum.drop_while(&(&1 != phase)) |> tl()

  defp next_in(list, current), do: list |> Enum.drop_while(&(&1 != current)) |> Enum.at(1)

  defp contenders(hand), do: Enum.filter(hand.round.seats, &(&1.hand_state != :folded))

  defp betting_dead?(hand), do: length(in_hand(hand.round.seats)) <= 1

  defp in_hand(seats), do: Enum.filter(seats, &(&1.hand_state == :in_hand))
end
