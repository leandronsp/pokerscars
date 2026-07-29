defmodule Pokerscars.Engine.HandTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Pokerscars.Engine.{BettingRound, Hand}

  # Entrants as {player_id, stack} keyed by position; blinds 1/2, seed fixed.
  defp start(entrants, button, seed \\ 7) do
    Hand.start(entrants, button, {1, 2}, seed)
  end

  defp act!(hand, player, action) do
    {:ok, hand} = Hand.act(hand, player, action)
    hand
  end

  defp stacks(hand), do: Map.new(hand.round.seats, &{&1.player_id, &1.stack})

  test "starting posts blinds and deals two cards to everyone in hand" do
    hand = start(%{0 => {"ana", 200}, 1 => {"bia", 200}, 2 => {"caio", 200}}, _button = 0)

    assert hand.phase == :preflop
    assert Enum.all?(hand.round.seats, &(length(&1.hole_cards) == 2))
    # Button 0: SB is 1, BB is 2, first to act is 0.
    assert %{committed: 1} = seat(hand, "bia")
    assert %{committed: 2} = seat(hand, "caio")
    assert hand.round.to_act == 0
  end

  test "heads-up: the button posts the small blind and acts first preflop" do
    hand = start(%{0 => {"ana", 200}, 1 => {"bia", 200}}, 0)

    assert %{committed: 1} = seat(hand, "ana")
    assert %{committed: 2} = seat(hand, "bia")
    assert hand.round.to_act == 0

    # Postflop the button acts last.
    hand = hand |> act!("ana", :call) |> act!("bia", :check)
    assert hand.phase == :flop
    assert hand.round.to_act == 1
  end

  test "a blind bigger than the stack posts all-in" do
    hand = start(%{0 => {"ana", 200}, 1 => {"bia", 200}, 2 => {"caio", 1}}, 0)

    assert %{committed: 1, hand_state: :all_in} = seat(hand, "caio")
  end

  test "acting out of turn is rejected" do
    hand = start(%{0 => {"ana", 200}, 1 => {"bia", 200}, 2 => {"caio", 200}}, 0)

    assert {:error, :not_your_turn} = Hand.act(hand, "bia", :fold)
  end

  test "everyone folding preflop ends the hand without showdown or revealed cards" do
    hand =
      start(%{0 => {"ana", 200}, 1 => {"bia", 200}, 2 => {"caio", 200}}, 0)
      |> act!("ana", :fold)
      |> act!("bia", :fold)

    assert hand.phase == :complete
    assert hand.board == []
    assert hand.result.reason == :uncontested
    # BB wins the blinds: their 2 back plus the SB's 1.
    assert stacks(hand) == %{"ana" => 200, "bia" => 199, "caio" => 201}
  end

  test "everyone folding postflop never deals the remaining streets" do
    hand =
      start(%{0 => {"ana", 200}, 1 => {"bia", 200}}, 0)
      |> act!("ana", :call)
      |> act!("bia", :check)
      |> act!("bia", {:raise_to, 10})
      |> act!("ana", :fold)

    assert hand.phase == :complete
    assert length(hand.board) == 3
    assert stacks(hand) == %{"ana" => 198, "bia" => 202}
  end

  test "streets progress to showdown when betting stays alive" do
    hand =
      start(%{0 => {"ana", 200}, 1 => {"bia", 200}}, 0)
      |> act!("ana", :call)
      |> act!("bia", :check)

    assert hand.phase == :flop
    hand = hand |> act!("bia", :check) |> act!("ana", :check)
    assert hand.phase == :turn
    hand = hand |> act!("bia", :check) |> act!("ana", :check)
    assert hand.phase == :river
    hand = hand |> act!("bia", :check) |> act!("ana", :check)

    assert hand.phase == :complete
    assert hand.result.reason == :showdown
    assert length(hand.board) == 5
    assert Map.values(stacks(hand)) |> Enum.sum() == 400
  end

  test "all but one all-in runs the board out with no further betting" do
    hand =
      start(%{0 => {"ana", 200}, 1 => {"bia", 50}}, 0)
      |> act!("ana", {:raise_to, 200})
      |> act!("bia", :call)

    assert hand.phase == :complete
    assert hand.result.reason == :showdown
    assert length(hand.board) == 5
    # The uncalled 150 came straight back to ana.
    assert Map.values(stacks(hand)) |> Enum.sum() == 250
  end

  property "chips are conserved through any legal action sequence" do
    check all(
            seed <- integer(),
            stack_a <- integer(10..400),
            stack_b <- integer(10..400),
            stack_c <- integer(10..400),
            picks <- list_of(integer(0..4), length: 40)
          ) do
      entrants = %{0 => {"a", stack_a}, 1 => {"b", stack_b}, 2 => {"c", stack_c}}
      total = stack_a + stack_b + stack_c

      hand = play_out(Hand.start(entrants, 0, {1, 2}, seed), picks)

      assert hand.phase == :complete
      assert stacks(hand) |> Map.values() |> Enum.sum() == total
    end
  end

  defp play_out(%Hand{phase: :complete} = hand, _picks), do: hand
  defp play_out(hand, []), do: play_out(hand, [0])

  defp play_out(hand, [pick | rest]) do
    seat = Enum.find(hand.round.seats, &(&1.position == hand.round.to_act))
    options = hand.round |> BettingRound.legal_actions() |> Enum.map(&to_action(&1, seat))
    action = Enum.at(options, rem(pick, length(options)))

    {:ok, hand} = Hand.act(hand, seat.player_id, action)
    play_out(hand, rest)
  end

  defp to_action({:call, _amount}, _seat), do: :call
  defp to_action({:raise_to, min, max}, _seat), do: {:raise_to, Enum.random(min..max)}
  defp to_action(action, _seat), do: action

  defp seat(hand, player_id), do: Enum.find(hand.round.seats, &(&1.player_id == player_id))
end
