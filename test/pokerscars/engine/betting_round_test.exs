defmodule Pokerscars.Engine.BettingRoundTest do
  use ExUnit.Case, async: true

  alias Pokerscars.Engine.{BettingRound, Seat}

  # Blinds 1/2 throughout, matching the worked examples in docs/engine-design.md.

  defp seat(position, stack, opts \\ []) do
    %Seat{
      position: position,
      player_id: "p#{position}",
      stack: stack,
      status: :active,
      hand_state: Keyword.get(opts, :hand_state, :in_hand),
      hole_cards: [],
      committed: Keyword.get(opts, :committed, 0),
      contributed: Keyword.get(opts, :committed, 0),
      acted_this_round?: Keyword.get(opts, :acted, false),
      may_raise?: true
    }
  end

  # Preflop, blinds already posted: SB at 0 (committed 1), BB at 1 (committed 2).
  defp preflop(stacks) do
    seats =
      stacks
      |> Enum.with_index()
      |> Enum.map(fn
        {stack, 0} -> seat(0, stack - 1, committed: 1)
        {stack, 1} -> seat(1, stack - 2, committed: 2)
        {stack, position} -> seat(position, stack)
      end)

    BettingRound.preflop(seats, 2)
  end

  defp postflop(stacks) do
    seats = stacks |> Enum.with_index() |> Enum.map(fn {stack, pos} -> seat(pos, stack) end)
    BettingRound.open(seats, :flop, 2, 0)
  end

  defp act!(round, action) do
    {:ok, round} = BettingRound.apply_action(round, action)
    round
  end

  test "everyone limps, round stays open until the big blind acts" do
    round = preflop([200, 200, 200]) |> act!(:call) |> act!(:call)

    refute BettingRound.closed?(round)
    assert round.to_act == 1
    assert {:raise_to, 4, _max} = raise_option(round)
  end

  test "big blind checks the option and the round closes" do
    round = preflop([200, 200, 200]) |> act!(:call) |> act!(:call) |> act!(:check)

    assert BettingRound.closed?(round)
    assert round.to_act == nil
  end

  test "preflop minimum open is twice the big blind, postflop minimum bet is the big blind" do
    assert {:raise_to, 4, 200} = raise_option(preflop([200, 200]))
    assert {:raise_to, 2, 200} = raise_option(postflop([200, 200]))
  end

  test "bet 100 raised to 300 makes the next minimum raise-to 500" do
    round = postflop([1000, 1000, 1000]) |> act!({:raise_to, 100}) |> act!({:raise_to, 300})

    assert {:raise_to, 500, _max} = raise_option(round)
  end

  test "incomplete all-in does not reopen the action for the original bettor" do
    # A bets 100, B is all-in for 140 (increment 40 < 100): A may only call or fold.
    round = postflop([1000, 140, 1000]) |> act!({:raise_to, 100}) |> act!({:raise_to, 140})
    round = act!(round, :fold)

    assert round.to_act == 0
    assert raise_option(round) == nil
    assert {:error, :action_not_reopened} = BettingRound.apply_action(round, {:raise_to, 300})
  end

  test "after an incomplete all-in a player yet to act keeps the full raise increment" do
    # A bets 100, B all-in 140: C's minimum raise is 240, not 180.
    round = postflop([1000, 140, 1000]) |> act!({:raise_to, 100}) |> act!({:raise_to, 140})

    assert round.to_act == 2
    assert {:raise_to, 240, _max} = raise_option(round)
  end

  test "a full all-in raise reopens the action for a player who already acted" do
    # A bets 100, B all-in 240 (full raise), C calls: A may re-raise, minimum 380.
    round =
      postflop([1000, 240, 1000])
      |> act!({:raise_to, 100})
      |> act!({:raise_to, 240})
      |> act!(:call)

    assert round.to_act == 0
    assert {:raise_to, 380, 1000} = raise_option(round)
  end

  test "calling with a short stack caps at the stack and goes all-in" do
    round = postflop([1000, 60, 1000]) |> act!({:raise_to, 100}) |> act!(:call)

    all_in = Enum.at(round.seats, 1)
    assert all_in.hand_state == :all_in
    assert all_in.stack == 0
    assert all_in.committed == 60
  end

  test "all-in seats are skipped in the action order" do
    round = postflop([1000, 60, 1000]) |> act!({:raise_to, 100}) |> act!(:call) |> act!(:call)

    assert BettingRound.closed?(round)
  end

  test "the last player facing an all-in field may only fold or call" do
    round = postflop([1000, 60, 80]) |> act!({:raise_to, 100})
    round = act!(round, :call)
    round = act!(round, :call)

    assert BettingRound.closed?(round)

    round = postflop([100, 60, 2000]) |> act!({:raise_to, 100}) |> act!(:call)
    assert round.to_act == 2
    assert raise_option(round) == nil
  end

  test "checking when facing a bet is rejected" do
    round = postflop([1000, 1000]) |> act!({:raise_to, 100})

    assert {:error, :cannot_check} = BettingRound.apply_action(round, :check)
  end

  test "raising below the minimum with chips behind is rejected" do
    round = postflop([1000, 1000]) |> act!({:raise_to, 100})

    assert {:error, :raise_too_small} = BettingRound.apply_action(round, {:raise_to, 150})
  end

  test "raising beyond the stack is rejected" do
    round = postflop([1000, 500]) |> act!({:raise_to, 100})

    assert {:error, :insufficient_chips} = BettingRound.apply_action(round, {:raise_to, 600})
  end

  defp raise_option(round) do
    round |> BettingRound.legal_actions() |> Enum.find(&match?({:raise_to, _, _}, &1))
  end
end
