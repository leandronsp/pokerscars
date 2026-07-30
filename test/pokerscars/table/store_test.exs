defmodule Pokerscars.Table.StoreTest do
  # Persistence writes come from table processes: this suite runs alone
  # with a shared sandbox and persistence switched on.
  use ExUnit.Case, async: false

  alias Pokerscars.Table
  alias Pokerscars.Table.{Ledger, Restorer, Store}

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Pokerscars.Repo, shared: true)
    Application.put_env(:pokerscars, :persist_tables, true)

    on_exit(fn ->
      Application.put_env(:pokerscars, :persist_tables, false)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)

    :ok
  end

  defp await_gone(code, tries \\ 200) do
    cond do
      not Table.exists?(code) -> :ok
      tries == 0 -> flunk("table never left the registry")
      true -> Process.sleep(5) && await_gone(code, tries - 1)
    end
  end

  defp create(overrides \\ %{}) do
    {:ok, code} =
      Table.create(
        Map.merge(
          %{
            name: "persisted table",
            blinds: {1, 2},
            buy_in: %{min: 100, max: 1_000},
            between_hands_ms: 60_000,
            turn_ms: 60_000,
            reveal_ms: 1,
            creator: "id-owner",
            seed_fun: fn -> 7 end
          },
          overrides
        )
      )

    code
  end

  test "a crashed table comes back with its ledger, stranded stacks cashed out" do
    code = create()
    :ok = Table.sit(code, "id-ana", "ana", 0, 200)
    :ok = Table.sit(code, "id-bia", "bia", 1, 300)

    # The lights go out mid-night: process gone, nothing closed it.
    [{pid, _value}] = Registry.lookup(Pokerscars.Table.Registry, code)
    :ok = DynamicSupervisor.terminate_child(Pokerscars.Table.Supervisor, pid)
    await_gone(code)

    :ok = Restorer.restore()

    assert Table.exists?(code)
    {:ok, view} = Table.view(code, "id-obs")

    # Nobody is seated, but the comanda remembers the whole night and
    # still nets to zero: everyone left with what they had.
    assert Enum.all?(view.seats, &(&1.nickname == nil))
    assert view.settlement |> Enum.map(& &1.result) |> Enum.sum() == 0
    names = view.settlement |> Enum.map(& &1.nickname) |> Enum.sort()
    assert names == ["ana", "bia"]

    # Restoring again is a no-op; the running table wins.
    :ok = Restorer.restore()
    assert Table.exists?(code)
  end

  test "config survives the round trip, closed tables stay closed" do
    code =
      create(%{
        name: "sexta trancada",
        password_hash: :crypto.hash(:sha256, "segredo"),
        blinds: {25, 50},
        buy_in: %{min: 1_000, max: 10_000}
      })

    [{pid, _value}] = Registry.lookup(Pokerscars.Table.Registry, code)
    :ok = DynamicSupervisor.terminate_child(Pokerscars.Table.Supervisor, pid)
    await_gone(code)
    :ok = Restorer.restore()

    assert Table.locked?(code)
    assert Table.check_password(code, "segredo")
    assert Table.creator(code) == "id-owner"

    :ok = Table.close(code, "id-owner")
    :ok = Restorer.restore()
    refute Table.exists?(code)
  end

  test "the write-through ledger matches the in-memory one" do
    code = create()
    :ok = Table.sit(code, "id-ana", "ana", 0, 200)
    :ok = Table.rebuy(code, "id-ana", 100)
    :ok = Table.stand(code, "id-ana")

    stored = Store.entries(code)
    assert length(stored) == 3
    assert %Ledger{kind: :cash_out, amount: 300} = hd(stored)
    assert Store.stranded_stacks(code) == []
  end
end
