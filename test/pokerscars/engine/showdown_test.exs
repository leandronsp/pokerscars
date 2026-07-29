defmodule Pokerscars.Engine.ShowdownTest do
  use ExUnit.Case, async: true

  alias Pokerscars.Engine.{Card, Seat, Showdown}

  defp seat(position, contributed, hole, hand_state \\ :in_hand) do
    %Seat{
      position: position,
      player_id: "p#{position}",
      stack: 0,
      hand_state: hand_state,
      contributed: contributed,
      hole_cards: Card.parse_many(hole)
    }
  end

  defp board, do: Card.parse_many("Kh 8c 5d 3s 2h")

  test "the best hand takes the pot" do
    seats = [seat(0, 100, "Ks Qd"), seat(1, 100, "Kd Jd")]

    payouts = Showdown.settle(seats, board(), _button = 0)

    assert payouts == %{0 => 200}
  end

  test "a side pot can be won by a different player than the main pot" do
    # Short stack holds the best hand and takes the main pot; the side pot
    # goes to the better of the two remaining hands.
    seats = [
      seat(0, 300, "Kd Ks", :all_in),
      seat(1, 800, "8h 8d", :all_in),
      seat(2, 800, "Ad 5c", :all_in)
    ]

    payouts = Showdown.settle(seats, board(), 0)

    assert payouts == %{0 => 900, 1 => 1000}
  end

  test "an exact tie splits the pot, odd chip to the first winner left of the button" do
    # Board plays for both. A folded 1-chip contribution makes the pot 101:
    # 50 each plus the odd chip to the first winner after the button.
    seats = [seat(0, 50, "2c 2d"), seat(1, 50, "2s 3d"), seat(2, 1, "9h 9d", :folded)]
    royal_board = Card.parse_many("As Ks Qs Js Ts")

    assert %{0 => 50, 1 => 51} = Showdown.settle(seats, royal_board, 0)
    assert %{0 => 51, 1 => 50} = Showdown.settle(seats, royal_board, 1)
  end

  test "a three-way split pays the remainder clockwise from the button" do
    royal_board = Card.parse_many("As Ks Qs Js Ts")

    seats = [
      seat(0, 100, "2c 2d"),
      seat(1, 100, "2s 3d"),
      seat(2, 100, "3s 3d"),
      seat(3, 1, "9h 9d", :folded)
    ]

    assert %{0 => 100, 1 => 101, 2 => 100} = Showdown.settle(seats, royal_board, 0)
    assert %{0 => 100, 1 => 100, 2 => 101} = Showdown.settle(seats, royal_board, 1)
  end

  test "folded seats never win, their chips go to the survivors" do
    seats = [seat(0, 100, "Ad Ah", :folded), seat(1, 100, "2s 3d")]

    assert %{1 => 200} = Showdown.settle(seats, board(), 0)
  end
end
