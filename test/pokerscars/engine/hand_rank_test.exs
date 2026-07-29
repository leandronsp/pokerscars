defmodule Pokerscars.Engine.HandRankTest do
  use ExUnit.Case, async: true

  alias Pokerscars.Engine.HandRank

  defp rank(category, tiebreak),
    do: %HandRank{category: category, tiebreak: tiebreak, cards: []}

  test "category decides before tiebreak" do
    assert :gt = HandRank.compare(rank(:flush, [7, 5, 4, 3, 2]), rank(:straight, [14]))
    assert :lt = HandRank.compare(rank(:pair, [14, 13, 12, 11]), rank(:two_pair, [2, 3, 4]))
  end

  test "equal categories break ties lexicographically" do
    assert :gt = HandRank.compare(rank(:pair, [13, 12, 8, 5]), rank(:pair, [13, 11, 10, 9]))
    assert :eq = HandRank.compare(rank(:pair, [13, 12, 8, 5]), rank(:pair, [13, 12, 8, 5]))
  end
end
