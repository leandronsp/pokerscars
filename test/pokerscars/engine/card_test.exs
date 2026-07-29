defmodule Pokerscars.Engine.CardTest do
  use ExUnit.Case, async: true

  alias Pokerscars.Engine.Card

  test "parses rank and suit from fixture notation" do
    assert %Card{rank: 14, suit: :spades} = Card.parse("As")
    assert %Card{rank: 10, suit: :diamonds} = Card.parse("Td")
    assert %Card{rank: 2, suit: :clubs} = Card.parse("2c")
  end

  test "parses a space-separated list" do
    assert [%Card{rank: 14, suit: :hearts}, %Card{rank: 13, suit: :hearts}] =
             Card.parse_many("Ah Kh")
  end

  test "raises on unknown notation" do
    assert_raise KeyError, fn -> Card.parse("1x") end
  end
end
