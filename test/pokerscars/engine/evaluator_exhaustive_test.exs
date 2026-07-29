defmodule Pokerscars.Engine.EvaluatorExhaustiveTest do
  @moduledoc """
  Categorizes every one of the C(52,5) = 2,598,960 five-card hands and checks
  the distribution against the mathematically known frequency table. This is
  total coverage of the evaluator's input space, not a sample.

  Seven-card correctness follows by construction: `evaluate/1` is the maximum
  over all 21 five-card subsets under `HandRank.compare/2` (a total order),
  so if every five-card categorization is right — proven here — the seven-card
  result is right too. The monotonicity and permutation properties in
  `EvaluatorTest` pin that reduction.
  """

  use ExUnit.Case, async: true

  alias Pokerscars.Engine.{Deck, Evaluator, HandRank}

  # The textbook 5-card poker frequencies. Their sum is C(52,5).
  @known_frequencies %{
    straight_flush: 40,
    four_of_a_kind: 624,
    full_house: 3_744,
    flush: 5_108,
    straight: 10_200,
    three_of_a_kind: 54_912,
    two_pair: 123_552,
    pair: 1_098_240,
    high_card: 1_302_540
  }

  @tag timeout: 300_000
  test "every possible five-card hand lands in the mathematically correct category" do
    cards = Deck.new().cards |> List.to_tuple()

    frequencies =
      for a <- 0..47,
          b <- (a + 1)..48,
          c <- (b + 1)..49,
          d <- (c + 1)..50,
          e <- (d + 1)..51,
          reduce: %{} do
        acc ->
          %HandRank{category: category} =
            Evaluator.evaluate([
              elem(cards, a),
              elem(cards, b),
              elem(cards, c),
              elem(cards, d),
              elem(cards, e)
            ])

          Map.update(acc, category, 1, &(&1 + 1))
      end

    assert frequencies == @known_frequencies
    assert frequencies |> Map.values() |> Enum.sum() == 2_598_960
  end
end
