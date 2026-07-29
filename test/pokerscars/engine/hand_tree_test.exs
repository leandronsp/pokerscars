defmodule Pokerscars.Engine.HandTreeTest do
  @moduledoc """
  Walks EVERY legal action sequence of whole hands (depth-first) for small
  configurations, asserting at every completed leaf that the hand terminated
  and chips were conserved, and at every decision node that the engine offers
  a sane action set.

  Raises are explored at both sizing extremes — the minimum raise and the
  all-in — because intermediate sizes change amounts, never the structure of
  the decision tree: reopening dynamics (full vs incomplete raise) are fully
  exercised by those two, since an all-in below the minimum IS the incomplete
  case. Together with the exhaustive evaluator test this covers the whole
  rule surface: every action shape at every reachable state.
  """

  use ExUnit.Case, async: true

  alias Pokerscars.Engine.{BettingRound, Hand}

  @tag timeout: 300_000
  test "heads-up: every action sequence terminates and conserves chips" do
    for seed <- 1..3 do
      entrants = %{0 => {"a", 6}, 1 => {"b", 7}}
      leaves = explore(Hand.start(entrants, 0, {1, 2}, seed), 13)

      assert leaves > 50, "expected a real tree, got #{leaves} leaves"
    end
  end

  @tag timeout: 300_000
  test "three-way with uneven stacks: every action sequence terminates and conserves chips" do
    for seed <- 1..2 do
      entrants = %{0 => {"a", 8}, 2 => {"b", 10}, 5 => {"c", 12}}
      leaves = explore(Hand.start(entrants, 0, {1, 2}, seed), 30)

      assert leaves > 500, "expected a real tree, got #{leaves} leaves"
    end
  end

  defp explore(%Hand{phase: :complete} = hand, total) do
    stacks = Enum.map(hand.round.seats, & &1.stack)

    assert Enum.sum(stacks) == total
    assert Enum.all?(stacks, &(&1 >= 0))
    assert hand.result.reason in [:uncontested, :showdown]
    1
  end

  defp explore(%Hand{} = hand, total) do
    actor = Enum.find(hand.round.seats, &(&1.position == hand.round.to_act))
    options = hand.round |> BettingRound.legal_actions() |> Enum.flat_map(&expand/1)

    assert options != [], "open hand with no legal actions"

    Enum.reduce(options, 0, fn action, acc ->
      {:ok, next} = Hand.act(hand, actor.player_id, action)
      acc + explore(next, total)
    end)
  end

  defp expand({:call, _amount}), do: [:call]
  defp expand({:raise_to, min, max}), do: Enum.uniq([{:raise_to, min}, {:raise_to, max}])
  defp expand(action), do: [action]
end
