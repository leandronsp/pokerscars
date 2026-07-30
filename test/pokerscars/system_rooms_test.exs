defmodule Pokerscars.SystemRoomsTest do
  # Fixed codes are global state: this suite runs alone.
  use ExUnit.Case, async: false

  alias Pokerscars.{Bots, SystemRooms, Table}

  test "boot opens the three house rooms idempotently, seated and untouchable" do
    :ok = SystemRooms.boot()
    :ok = SystemRooms.boot()

    rooms = Table.list() |> Enum.filter(& &1.system?)
    assert length(rooms) == 3
    assert Enum.all?(rooms, & &1.description)

    assert {:error, :not_owner} = Table.close("CASA01", "some-player")
    assert {:error, :not_owner} = Bots.add("CASA01", requester: "some-player")

    assert %{seated: 2} = Enum.find(rooms, &(&1.code == "CASA02"))
    assert %{seated: 5} = Enum.find(rooms, &(&1.code == "CASA03"))
  end
end
