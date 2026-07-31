defmodule Pokerscars.SystemRoomsTest do
  # Fixed codes are global state: this suite runs alone.
  use ExUnit.Case, async: false

  alias Pokerscars.{Bots, SystemRooms, Table}

  test "boot opens the four house rooms idempotently, seated and untouchable" do
    :ok = SystemRooms.boot()
    :ok = SystemRooms.boot()

    rooms = Table.list() |> Enum.filter(& &1.system?)
    assert length(rooms) == 4
    assert Enum.all?(rooms, & &1.description)

    assert {:error, :not_owner} = Table.close("CASA01", "some-player")
    assert {:error, :not_owner} = Bots.add("CASA01", requester: "some-player")

    assert %{seated: 2, bots: 2} = Enum.find(rooms, &(&1.code == "CASA02"))
    assert %{seated: 5, bots: 5} = Enum.find(rooms, &(&1.code == "CASA03"))
    assert %{seated: 0, bots: 0} = Enum.find(rooms, &(&1.code == "CASA04"))
  end

  test "the sweep tops the bots back up, however the room came to exist" do
    :ok = SystemRooms.boot()

    # Murder CASA02's bots for good (no restart on shutdown).
    Pokerscars.Bots.Supervisor
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
    |> Enum.filter(fn pid ->
      Process.alive?(pid) and String.contains?(:sys.get_state(pid).player_id, "CASA02")
    end)
    |> Enum.each(&DynamicSupervisor.terminate_child(Pokerscars.Bots.Supervisor, &1))

    # And the table itself crashes: the supervisor rebirths it with empty
    # seats — exactly the restored-from-postgres shape.
    [{table_pid, _value}] = Registry.lookup(Pokerscars.Table.Registry, "CASA02")
    Process.exit(table_pid, :kill)

    await_seated("CASA02", 0)

    :ok = SystemRooms.boot()
    await_seated("CASA02", 2)
  end

  test "a room slow to answer never takes the sweep (or the boot) down" do
    :ok = SystemRooms.boot()

    # A table mid code-reload or mid-restore answers nothing: the sweep's
    # call times out. That must be a skip, not an app shutdown.
    [{pid, _value}] = Registry.lookup(Pokerscars.Table.Registry, "CASA02")
    :ok = :sys.suspend(pid)

    try do
      assert :ok = SystemRooms.boot()
    after
      :ok = :sys.resume(pid)
    end
  end

  defp await_seated(code, count, tries \\ 400) do
    seated =
      case Pokerscars.Table.view(code, "obs") do
        {:ok, view} -> Enum.count(view.seats, & &1.nickname)
        _missing -> -1
      end

    cond do
      seated == count -> :ok
      tries == 0 -> flunk("expected #{count} seated at #{code}, got #{seated}")
      true -> Process.sleep(10) && await_seated(code, count, tries - 1)
    end
  end
end
