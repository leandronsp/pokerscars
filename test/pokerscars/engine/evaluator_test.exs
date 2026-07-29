defmodule Pokerscars.Engine.EvaluatorTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Pokerscars.Engine.{Card, Deck, Evaluator, HandRank}

  @fifty_two Deck.new().cards

  defp eval(notation), do: notation |> Card.parse_many() |> Evaluator.evaluate()

  defp strip(%HandRank{category: category, tiebreak: tiebreak}), do: {category, tiebreak}

  test "wheel ranks as a five-high straight, below six-high" do
    assert %HandRank{category: :straight, tiebreak: [5]} = eval("As 2d 3c 4h 5s 9d Jc")
    assert :lt = HandRank.compare(eval("As 2d 3c 4h 5s 9d Jc"), eval("2d 3c 4h 5s 6d 9h Jc"))
  end

  test "a suited wheel is a five-high straight flush" do
    assert %HandRank{category: :straight_flush, tiebreak: [5]} = eval("As 2s 3s 4s 5s 9d Jc")
  end

  test "a straight flush beats four of a kind" do
    straight_flush = eval("5s 6s 7s 8s 9s Ad Kd")
    quads = eval("8s 8h 8d 8c As Kd 2c")

    assert %HandRank{category: :straight_flush, tiebreak: [9]} = straight_flush
    assert :gt = HandRank.compare(straight_flush, quads)
  end

  test "flush and separate straight in seven cards is a flush, not a straight flush" do
    assert %HandRank{category: :flush, tiebreak: [10, 9, 7, 6, 5]} = eval("9h 8d 7h 6h 5h Th 2c")
  end

  test "six and seven card flushes take the best five of the suit" do
    assert %HandRank{category: :flush, tiebreak: [14, 10, 8, 6, 4]} = eval("Ah Th 8h 6h 4h 2h Kd")
    assert %HandRank{category: :flush, tiebreak: [14, 10, 8, 6, 4]} = eval("Ah Th 8h 6h 4h 2h 3h")
  end

  test "two sets make a full house of the higher set" do
    assert %HandRank{category: :full_house, tiebreak: [9, 7]} = eval("9s 9h 9d 7s 7h 7d Kc")
  end

  test "three pairs keep the top two, kicker may be the third pair's rank" do
    assert %HandRank{category: :two_pair, tiebreak: [14, 13, 12]} = eval("As Ah Ks Kh Qs Qh 2d")
  end

  test "quads take the highest remaining card as kicker" do
    assert %HandRank{category: :four_of_a_kind, tiebreak: [8, 14]} = eval("8s 8h 8d 8c As Kd 2c")
  end

  test "when the board plays, both hands tie exactly" do
    board = "Ad Kh Qs Jc Td"
    assert :eq = HandRank.compare(eval(board <> " 2c 3c"), eval(board <> " 4h 5h"))
  end

  test "same pair, kicker decides" do
    board = "Kh 8c 5d 3s 2h"
    assert :gt = HandRank.compare(eval(board <> " Ks Qd"), eval(board <> " Kd Jd"))
  end

  property "card order never changes the evaluation" do
    check all(cards <- uniq_list_of(member_of(@fifty_two), length: 7)) do
      assert strip(Evaluator.evaluate(cards)) == strip(Evaluator.evaluate(Enum.shuffle(cards)))
    end
  end

  property "adding cards never lowers the rank" do
    check all(cards <- uniq_list_of(member_of(@fifty_two), length: 7)) do
      five = Enum.take(cards, 5)

      assert HandRank.compare(Evaluator.evaluate(cards), Evaluator.evaluate(five)) in [:gt, :eq]
    end
  end

  property "relabeling suits never changes category or tiebreak" do
    swap = %{spades: :hearts, hearts: :spades, diamonds: :clubs, clubs: :diamonds}

    check all(cards <- uniq_list_of(member_of(@fifty_two), length: 7)) do
      swapped =
        Enum.map(cards, fn %Card{} = card ->
          %Card{card | suit: Map.fetch!(swap, card.suit)}
        end)

      assert strip(Evaluator.evaluate(cards)) == strip(Evaluator.evaluate(swapped))
    end
  end
end
