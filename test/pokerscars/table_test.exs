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

  # The big stacks raise to 150, the short stack calls all-in for less;
  # once the round settles the pot must layer into main and side.
  defp drive_all_in(_code, 0), do: flunk("pot never split")

  defp drive_all_in(code, tries) do
    {:ok, view} = Table.view(code, "id-ana")

    if length(view.pots) > 1 do
      view
    else
      %{position: position} = view.turn
      %{nickname: nickname} = Enum.find(view.seats, &(&1.position == position))
      _result = act_toward_split(code, "id-" <> nickname, nickname)
      drive_all_in(code, tries - 1)
    end
  end

  defp act_toward_split(code, player, "bia"), do: Table.act(code, player, :call)

  defp act_toward_split(code, player, _big) do
    case Table.act(code, player, {:raise_to, 150}) do
      :ok -> :ok
      {:error, _reason} -> Table.act(code, player, :call)
    end
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

  test "a rebuy placed mid-hand queues and lands when the hand ends" do
    # 500ms between hands: enough of a window to read the view after the
    # fold, before hand 2 posts blinds.
    code = sit_two(create(%{between_hands_ms: 500}))
    await_hand(code, "id-ana")

    assert :ok = Table.rebuy(code, "id-ana", 200)

    {:ok, mid_hand} = Table.view(code, "id-ana")
    assert seat(mid_hand, 0).stack == 199

    :ok = Table.act(code, "id-ana", :fold)

    {:ok, view} = Table.view(code, "id-ana")
    assert seat(view, 0).stack == 399
  end

  test "an all-in for less splits the pot live into main and side" do
    code = create(%{between_hands_ms: 60_000})
    :ok = Table.sit(code, "id-ana", "ana", 0, 200)
    :ok = Table.sit(code, "id-bia", "bia", 1, 100)
    :ok = Table.sit(code, "id-calo", "calo", 2, 200)
    await_hand(code, "id-ana")

    view = drive_all_in(code, 30)

    assert view.pots == [300, 100]
  end

  test "slurs are rejected at the boundary: nicknames and table names" do
    code = create()

    assert {:error, :name_not_allowed} = Table.sit(code, "id-x", "M4c4co", 0, 200)

    assert {:error, :name_not_allowed} =
             Table.create(%{
               name: "mesa do v1ad0",
               blinds: {1, 2},
               buy_in: %{min: 100, max: 1000}
             })
  end

  test "chat: seated players talk, spectators read, public rooms are preset-only" do
    code = create(%{between_hands_ms: 60_000})
    :ok = Table.sit(code, "id-ana", "ana", 0, 200)

    assert {:error, :not_seated} = Table.chat(code, "id-lurker", {:preset, :gg})
    assert {:error, :presets_only} = Table.chat(code, "id-ana", {:text, "oi"})
    assert :ok = Table.chat(code, "id-ana", {:preset, :nice_hand})
    assert :ok = Table.chat(code, "id-ana", {:preset, :gg})

    {:ok, view} = Table.view(code, "id-ana")

    assert [%{nickname: "ana", payload: {:preset, :gg}}, %{payload: {:preset, :nice_hand}}] =
             view.chat
  end

  test "chat: private rooms allow free text, throttle applies, log caps at ten" do
    code = create(%{between_hands_ms: 60_000, password_hash: :crypto.hash(:sha256, "x")})
    :ok = Table.sit(code, "id-ana", "ana", 0, 200)

    assert :ok = Table.chat(code, "id-ana", {:text, "bora jogar"})
    assert :ok = Table.chat(code, "id-ana", {:text, "sobe o blind"})
    assert :ok = Table.chat(code, "id-ana", {:preset, :kkkk})
    assert {:error, :throttled} = Table.chat(code, "id-ana", {:text, "spam"})

    {:ok, view} = Table.view(code, "id-ana")
    assert [%{payload: {:preset, :kkkk}}, %{payload: {:text, "sobe o blind"}} | _rest] = view.chat
    assert length(view.chat) == 3
  end

  test "the table keeps an event diary, newest first" do
    code = sit_two(create(%{between_hands_ms: 60_000}))
    await_hand(code, "id-ana")

    :ok = Table.act(code, "id-ana", :fold)

    {:ok, view} = Table.view(code, "id-ana")

    assert [
             %{type: :won, data: %{nickname: "bia", amount: 3}},
             %{type: :action, data: %{nickname: "ana", action: :fold, auto?: false}},
             %{type: :hand_started, data: %{hand_no: 1}},
             %{type: :sit, data: %{nickname: "bia", amount: 200}},
             %{type: :sit, data: %{nickname: "ana", amount: 200}}
           ] = view.events
  end

  test "a winner who already stood up is still named by nickname, never by id" do
    code = sit_two(create(%{between_hands_ms: 60_000}))
    await_hand(code, "id-ana")

    # Bia asks to leave mid-hand; ana folds, bia wins and her stand executes.
    :ok = Table.stand(code, "id-bia")
    :ok = Table.act(code, "id-ana", :fold)

    {:ok, view} = Table.view(code, "id-ana")
    assert [%{nickname: "bia"}] = view.result.winners
    refute inspect(view.result) =~ "id-bia"
  end

  test "folded cards leave the table for everyone, the owner included" do
    code = sit_two(create(%{between_hands_ms: 60_000}))
    await_hand(code, "id-ana")

    :ok = Table.act(code, "id-ana", :fold)

    {:ok, ana} = Table.view(code, "id-ana")
    {:ok, bia} = Table.view(code, "id-bia")

    assert seat(ana, 0).cards == nil
    assert seat(bia, 0).cards == nil
  end

  test "only the creator may close a table" do
    {:ok, code} =
      Table.create(%{
        name: "dona",
        blinds: {1, 2},
        buy_in: %{min: 100, max: 1000},
        creator: "id-dona"
      })

    assert {:error, :not_owner} = Table.close(code, "id-intrusa")
    assert Table.exists?(code)
    assert :ok = Table.close(code, "id-dona")
    # Registry cleanup on process death is async; give it a beat.
    assert await_gone(code)
  end

  test "a creator is capped at five open tables" do
    base = %{name: "spam", blinds: {1, 2}, buy_in: %{min: 100, max: 1000}, creator: "id-spammer"}

    codes = for _n <- 1..5, do: elem(Table.create(base), 1)

    assert {:error, :too_many_tables} = Table.create(base)

    for code <- codes, do: :ok = Table.close(code, "id-spammer")
  end

  test "only the creator can summon bots to an owned table" do
    {:ok, code} =
      Table.create(%{
        name: "dos bots",
        blinds: {1, 2},
        buy_in: %{min: 100, max: 1000},
        creator: "id-dona"
      })

    assert {:error, :not_owner} = Pokerscars.Bots.add(code, requester: "id-intrusa")
    assert :ok = Pokerscars.Bots.add(code, requester: "id-dona", delay_ms: 10)
  end

  defp await_gone(code, tries \\ 100) do
    cond do
      not Table.exists?(code) -> true
      tries == 0 -> false
      true -> Process.sleep(5) && await_gone(code, tries - 1)
    end
  end

  test "a locked room checks its password and shows a lock in the lobby list" do
    {:ok, code} =
      Table.create(%{
        name: "trancada",
        blinds: {1, 2},
        buy_in: %{min: 100, max: 1000},
        creator: "id-dona",
        password_hash: :crypto.hash(:sha256, "segredo")
      })

    assert Table.locked?(code)
    assert Table.check_password(code, "segredo")
    refute Table.check_password(code, "chute")

    listed = Enum.find(Table.list("id-dona"), &(&1.code == code))
    assert listed.locked?
    assert listed.mine?
    refute Map.has_key?(listed, :creator)
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
