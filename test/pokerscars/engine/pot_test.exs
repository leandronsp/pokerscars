defmodule Pokerscars.Engine.PotTest do
  use ExUnit.Case, async: true

  alias Pokerscars.Engine.{Pot, Seat}

  defp seat(position, contributed, hand_state \\ :in_hand) do
    %Seat{
      position: position,
      player_id: "p#{position}",
      stack: 0,
      hand_state: hand_state,
      contributed: contributed
    }
  end

  test "three all-ins of 300, 500 and 800 build main and side pots plus a refund" do
    seats = [seat(0, 300, :all_in), seat(1, 500, :all_in), seat(2, 800, :all_in)]

    {pots, refunds} = Pot.build(seats)

    assert [%Pot{amount: 900, eligible: [0, 1, 2]}, %Pot{amount: 400, eligible: [1, 2]}] = pots
    assert refunds == %{2 => 300}
  end

  test "an uncalled bet is refunded, not potted" do
    # Bettor's 500 was called only up to 200; the 300 on top comes back.
    seats = [seat(0, 200, :folded), seat(1, 500)]

    {pots, refunds} = Pot.build(seats)

    assert [%Pot{amount: 400, eligible: [1]}] = pots
    assert refunds == %{1 => 300}
  end

  test "a folded player's chips remain in the pots they paid into" do
    seats = [seat(0, 400, :folded), seat(1, 400), seat(2, 400)]

    {pots, refunds} = Pot.build(seats)

    assert [%Pot{amount: 1200, eligible: [1, 2]}] = pots
    assert refunds == %{}
  end

  test "a folded short contribution stays in the main pot layer only" do
    seats = [seat(0, 100, :folded), seat(1, 400, :all_in), seat(2, 400)]

    {pots, refunds} = Pot.build(seats)

    assert [%Pot{amount: 900, eligible: [1, 2]}] = pots
    assert refunds == %{}
  end

  test "seats that contributed nothing build no pots" do
    seats = [seat(0, 0), seat(1, 0)]

    assert {[], %{}} = Pot.build(seats)
  end
end
