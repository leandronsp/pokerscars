defmodule Pokerscars.Engine.Evaluator do
  @moduledoc """
  Best five-card hand from 5, 6 or 7 cards: categorize every 5-card
  combination, keep the maximum. No lookup tables by design — at 9 seats a
  showdown is ~189 categorizations, and readable code wins over microseconds.
  See docs/engine-design.md.
  """

  alias Pokerscars.Engine.{Card, HandRank}

  @doc "Evaluates 5, 6 or 7 cards to the best five-card hand."
  @spec evaluate([Card.t()]) :: HandRank.t()
  def evaluate(cards) when length(cards) in 5..7 do
    cards
    |> combinations(5)
    |> Enum.map(&categorize_five/1)
    |> Enum.reduce(&max_rank/2)
  end

  defp max_rank(rank, best), do: if(HandRank.compare(rank, best) == :gt, do: rank, else: best)

  defp combinations(_cards, 0), do: [[]]
  defp combinations([], _size), do: []

  defp combinations([head | tail], size) do
    with_head = for combo <- combinations(tail, size - 1), do: [head | combo]
    with_head ++ combinations(tail, size)
  end

  defp categorize_five(five) do
    ranks = five |> Enum.map(& &1.rank) |> Enum.sort(:desc)

    groups =
      ranks
      |> Enum.frequencies()
      |> Enum.sort_by(fn {rank, count} -> {count, rank} end, :desc)

    flush? = match?([_], Enum.uniq_by(five, & &1.suit))
    {category, tiebreak} = classify(groups, flush?, straight_high(ranks), ranks)

    %HandRank{category: category, tiebreak: tiebreak, cards: five}
  end

  defp classify(_groups, true, high, _ranks) when high != nil, do: {:straight_flush, [high]}

  defp classify([{quad, 4}, {kicker, 1}], _flush?, _high, _ranks),
    do: {:four_of_a_kind, [quad, kicker]}

  defp classify([{trip, 3}, {pair, 2}], _flush?, _high, _ranks), do: {:full_house, [trip, pair]}
  defp classify(_groups, true, _high, ranks), do: {:flush, ranks}
  defp classify(_groups, _flush?, high, _ranks) when high != nil, do: {:straight, [high]}

  defp classify([{trip, 3} | kickers], _flush?, _high, _ranks),
    do: {:three_of_a_kind, [trip | singles(kickers)]}

  defp classify([{high, 2}, {low, 2}, {kicker, 1}], _flush?, _high, _ranks),
    do: {:two_pair, [high, low, kicker]}

  defp classify([{pair, 2} | kickers], _flush?, _high, _ranks),
    do: {:pair, [pair | singles(kickers)]}

  defp classify(_groups, _flush?, _high, ranks), do: {:high_card, ranks}

  defp singles(groups), do: Enum.map(groups, fn {rank, 1} -> rank end)

  # Five distinct descending ranks are a straight when they span exactly four;
  # the wheel is the one straight the descending sort cannot express.
  defp straight_high([14, 5, 4, 3, 2]), do: 5

  defp straight_high([high | _] = ranks) do
    if ranks == Enum.to_list(high..(high - 4)//-1), do: high, else: nil
  end
end
