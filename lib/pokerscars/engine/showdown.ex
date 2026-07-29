defmodule Pokerscars.Engine.Showdown do
  @moduledoc """
  Settles a hand that reached showdown: builds the pots, finds each pot's
  winners among its eligible seats, splits with the odd chips going to the
  first winners clockwise from the seat after the button (TDA rule).
  """

  alias Pokerscars.Engine.{Card, Evaluator, HandRank, Pot, Seat}

  @doc "Payouts per position, refunds included. The board must be complete."
  @spec settle([Seat.t()], [Card.t()], Seat.position()) :: %{Seat.position() => Pot.chips()}
  def settle(seats, [_, _, _, _, _] = board, button) do
    {pots, refunds} = Pot.build(seats)

    Enum.reduce(pots, refunds, fn pot, payouts ->
      distribute(pot.amount, winners(pot, seats, board), button, payouts)
    end)
  end

  @doc "The positions that won at least one pot — the ones worth celebrating."
  @spec winners([Seat.t()], [Card.t()]) :: [Seat.position()]
  def winners(seats, board) do
    seats |> breakdown(board) |> Enum.flat_map(& &1.winners) |> Enum.uniq() |> Enum.sort()
  end

  @doc "Each pot with its winners, main pot first — the settlement, spelled out."
  @spec breakdown([Seat.t()], [Card.t()]) ::
          [%{amount: Pot.chips(), winners: [Seat.position()]}]
  def breakdown(seats, board) do
    {pots, _refunds} = Pot.build(seats)
    Enum.map(pots, &%{amount: &1.amount, winners: winners(&1, seats, board)})
  end

  defp winners(%Pot{eligible: eligible}, seats, board) do
    ranked =
      for seat <- seats, seat.position in eligible do
        {seat.position, Evaluator.evaluate(seat.hole_cards ++ board)}
      end

    best = ranked |> Enum.map(&elem(&1, 1)) |> Enum.reduce(&best_rank/2)

    for {position, rank} <- ranked, HandRank.compare(rank, best) == :eq, do: position
  end

  defp best_rank(rank, best), do: if(HandRank.compare(rank, best) == :gt, do: rank, else: best)

  defp distribute(amount, winners, button, payouts) do
    base = div(amount, length(winners))
    extra = rem(amount, length(winners))
    ordered = Enum.sort_by(winners, &Integer.mod(&1 - button - 1, 10))

    ordered
    |> Enum.with_index()
    |> Enum.reduce(payouts, fn {position, index}, acc ->
      share = base + if(index < extra, do: 1, else: 0)
      Map.update(acc, position, share, &(&1 + share))
    end)
  end
end
