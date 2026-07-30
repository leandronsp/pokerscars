defmodule Pokerscars.BotsTest do
  use ExUnit.Case, async: true

  alias Pokerscars.{Bots, Table}

  defp create_table do
    {:ok, code} =
      Table.create(%{
        name: "bot arena",
        blinds: {1, 2},
        buy_in: %{min: 100, max: 1000},
        between_hands_ms: 1,
        turn_ms: 5_000
      })

    code
  end

  defp await(code, fun, tries \\ 400) do
    {:ok, view} = Table.view(code, "observer")

    cond do
      fun.(view) -> view
      tries == 0 -> flunk("condition never reached; view: #{inspect(view, limit: 6)}")
      true -> Process.sleep(10) && await(code, fun, tries - 1)
    end
  end

  test "a bot sits itself at a free seat with a 100BB buy-in" do
    code = create_table()

    assert :ok = Bots.add(code, delay_ms: 10)

    view = await(code, &Enum.any?(&1.seats, fn seat -> seat.nickname != nil end))
    bot_seat = Enum.find(view.seats, & &1.nickname)
    assert bot_seat.nickname =~ "bot-"
    assert bot_seat.stack == 200
  end

  test "two bots play whole hands against each other unattended" do
    code = create_table()

    assert :ok = Bots.add(code, delay_ms: 10)
    assert :ok = Bots.add(code, delay_ms: 10)

    view = await(code, &(&1.hand_no >= 3))

    assert view.hand_no >= 3
    assert view.settlement |> Enum.map(& &1.result) |> Enum.sum() == 0
  end

  test "a killed bot resurrects into its seat and keeps the game moving" do
    code = create_table()

    assert :ok = Bots.add(code, delay_ms: 500)
    assert :ok = Bots.add(code, delay_ms: 500)

    view = await(code, &(&1.hand_no >= 1 and &1.turn != nil))
    %{position: position} = view.turn
    %{nickname: nickname} = Enum.find(view.seats, &(&1.position == position))

    pid = bot_pid("bot-" <> code <> "-" <> nickname)
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    # The resurrected bot must act well before the 5s turn clock would;
    # 2s of polling proves the game moved on its own.
    hand_no = view.hand_no

    _view =
      await(
        code,
        &(&1.hand_no > hand_no or &1.turn == nil or &1.turn.position != position),
        200
      )
  end

  defp bot_pid(player_id) do
    Pokerscars.Bots.Supervisor
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _mods} -> pid end)
    |> Enum.find(fn pid -> Process.alive?(pid) and :sys.get_state(pid).player_id == player_id end)
  end

  test "adding a bot to a full table fails politely" do
    code = create_table()

    for position <- 0..8,
        do: :ok = Table.sit(code, "id-#{position}", "p#{position}", position, 200)

    assert {:error, :table_full} = Bots.add(code)
  end
end
