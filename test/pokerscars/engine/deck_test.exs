defmodule Pokerscars.Engine.DeckTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Pokerscars.Engine.Deck

  test "a new deck holds 52 distinct cards" do
    assert %Deck{cards: cards} = Deck.new()
    assert length(cards) == 52
    assert length(Enum.uniq(cards)) == 52
  end

  test "the same seed produces the same order, a different seed does not" do
    assert Deck.shuffle(Deck.new(), 42) == Deck.shuffle(Deck.new(), 42)
    refute Deck.shuffle(Deck.new(), 1) == Deck.shuffle(Deck.new(), 2)
  end

  test "deal splits the top cards from the rest" do
    {dealt, %Deck{cards: rest}} = Deck.new() |> Deck.shuffle(7) |> Deck.deal(2)

    assert length(dealt) == 2
    assert length(rest) == 50
    assert Enum.sort(dealt ++ rest) == Enum.sort(Deck.new().cards)
  end

  property "shuffle is a permutation of the 52 cards" do
    check all(seed <- integer()) do
      %Deck{cards: shuffled} = Deck.shuffle(Deck.new(), seed)
      assert Enum.sort(shuffled) == Enum.sort(Deck.new().cards)
    end
  end
end
