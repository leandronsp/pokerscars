defmodule Pokerscars.TableTest do
  use ExUnit.Case, async: true

  alias Pokerscars.Table
  alias Pokerscars.Table.View
  alias Pokerscars.Table.View.SeatView

  # Deterministic tables: fixed seed, instant hand start, long turn clock.
  defp create(overrides \\ %{}) do
    config =
      Map.merge(
        %{
          name: "test table",
          blinds: {1, 2},
          buy_in: %{min: 100, max: 1000},
          between_hands_ms: 1,
          turn_ms: 60_000,
          seed_fun: fn -> 7 end
        },
        overrides
      )

    {:ok, code} = Table.create(config)
    code
  end

  defp sit_two(code) do
    :ok = Table.sit(code, "id-ana", "ana", 0, 200)
    :ok = Table.sit(code, "id-bia", "bia", 1, 200)
    code
  end

  defp await_hand(code, player_id) do
    {:ok, view} = Table.view(code, player_id)

    if view.hand_no > 0 do
      view
    else
      Process.sleep(5)
      await_hand(code, player_id)
    end
  end

  test "a hand starts on its own once two players sit with a buy-in" do
    view = create() |> sit_two() |> await_hand("id-ana")

    assert view.phase == :preflop
    assert view.hand_no == 1
    assert view.pot == 3
  end

  test "sitting is validated: taken seat, double sit, buy-in out of range" do
    code = create()
    :ok = Table.sit(code, "id-ana", "ana", 0, 200)

    assert {:error, :seat_taken} = Table.sit(code, "id-bia", "bia", 0, 200)
    assert {:error, :already_seated} = Table.sit(code, "id-ana", "ana", 1, 200)
    assert {:error, :invalid_buy_in} = Table.sit(code, "id-bia", "bia", 1, 50)
    assert {:error, :table_not_found} = Table.sit("NOPE42", "id-x", "x", 0, 200)
  end

  test "each player sees their own cards, the opponent's stay hidden" do
    code = sit_two(create())
    ana = await_hand(code, "id-ana")
    bia = await_hand(code, "id-bia")

    assert %SeatView{hero?: true, cards: [_, _]} = seat(ana, 0)
    assert %SeatView{hero?: false, cards: :hidden} = seat(ana, 1)
    assert %SeatView{hero?: true, cards: [_, _]} = seat(bia, 1)
    assert %SeatView{hero?: false, cards: :hidden} = seat(bia, 0)
  end

  test "a spectator sees no cards at all" do
    view = create() |> sit_two() |> await_hand("id-zeca")

    assert %SeatView{cards: :hidden} = seat(view, 0)
    assert %SeatView{cards: :hidden} = seat(view, 1)
    assert view.hero_actions == []
  end

  test "only the player to act gets legal actions, and acting drives the hand" do
    code = sit_two(create())
    view = await_hand(code, "id-ana")

    # Heads-up, button 0: ana is SB and acts first.
    assert view.turn.position == 0
    assert Enum.any?(view.hero_actions, &match?({:call, 1}, &1))

    {:ok, bia_view} = Table.view(code, "id-bia")
    assert bia_view.hero_actions == []
    assert {:error, :not_your_turn} = Table.act(code, "id-bia", :fold)

    :ok = Table.act(code, "id-ana", :call)
    :ok = Table.act(code, "id-bia", :check)

    {:ok, view} = Table.view(code, "id-ana")
    assert view.phase == :flop
    assert length(view.board) == 3
  end

  test "an uncontested hand pays the winner and the next hand is scheduled" do
    code = sit_two(create())
    await_hand(code, "id-ana")

    :ok = Table.act(code, "id-ana", :fold)

    # The completed hand broadcasts, then hand 2 starts on the 1ms timer.
    view = await_hand_number(code, "id-ana", 2)
    assert view.phase == :preflop

    stacks = view.seats |> Enum.filter(& &1.nickname) |> Map.new(&{&1.nickname, &1.stack})
    # Hand 1: ana folded her SB to bia (199/201). Hand 2 blinds are already
    # posted with the button rotated — bia is SB (201-1), ana is BB (199-2).
    assert stacks == %{"ana" => 197, "bia" => 200}
  end

  test "the turn clock folds an absent player facing a bet" do
    code = create(%{turn_ms: 30}) |> sit_two()
    await_hand(code, "id-ana")

    :ok = Table.act(code, "id-ana", {:raise_to, 6})

    # Bia times out facing the raise and is folded: ana takes the pot of 4
    # plus her uncalled 4 back (202/198), then hand 2 posts blinds (200/197).
    view = await_hand_number(code, "id-ana", 2)
    stacks = view.seats |> Enum.filter(& &1.nickname) |> Map.new(&{&1.nickname, &1.stack})
    assert stacks == %{"ana" => 200, "bia" => 197}
  end

  test "standing up cashes out and settlement nets to zero" do
    code = sit_two(create())
    await_hand(code, "id-ana")

    :ok = Table.act(code, "id-ana", :fold)
    :ok = Table.stand(code, "id-ana")

    {:ok, view} = Table.view(code, "id-bia")
    balances = Map.new(view.settlement, &{&1.nickname, &1.result})

    assert balances == %{"ana" => -1, "bia" => 1}
    assert view.settlement |> Enum.map(& &1.result) |> Enum.sum() == 0
  end

  test "rebuy is rejected mid-hand and applied between hands" do
    # 500ms between hands: enough of a window to rebuy and read the view
    # after the fold, before hand 2 posts blinds.
    code = sit_two(create(%{between_hands_ms: 500}))
    await_hand(code, "id-ana")

    assert {:error, :hand_in_progress} = Table.rebuy(code, "id-ana", 200)

    :ok = Table.act(code, "id-ana", :fold)
    :ok = Table.rebuy(code, "id-ana", 200)

    {:ok, view} = Table.view(code, "id-ana")
    assert seat(view, 0).stack == 399
  end

  defp await_hand_number(code, player_id, number) do
    {:ok, view} = Table.view(code, player_id)

    if view.hand_no >= number and view.phase == :preflop do
      view
    else
      Process.sleep(5)
      await_hand_number(code, player_id, number)
    end
  end

  defp seat(%View{seats: seats}, position), do: Enum.find(seats, &(&1.position == position))
end
