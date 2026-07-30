defmodule Pokerscars.Table.Restorer do
  @moduledoc """
  Brings every open table back after a boot: same code, same config, same
  ledger. Seats and hands are gone with the old process — anyone still
  seated at the crash gets an honest synthesized cash-out for their last
  known stack, so the comanda stays complete and zero-sum, and buys back
  in when they return.
  """

  alias Pokerscars.Table
  alias Pokerscars.Table.{Ledger, Store}

  require Logger

  @doc """
  Runs synchronously during supervision startup and starts no process:
  every table is back before the next child (the house rooms) boots, so
  the two can never race for the same code.
  """
  @spec start_link(term()) :: :ignore
  def start_link(_arg) do
    :ok = restore()
    :ignore
  end

  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(arg) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [arg]}, restart: :temporary}
  end

  @doc "Restores every open table that is not already running. Idempotent."
  @spec restore() :: :ok
  def restore do
    if Store.enabled?() do
      Store.open_tables()
      |> Enum.reject(&Table.exists?(&1.code))
      |> Enum.each(&restore_table/1)
    end

    :ok
  end

  defp restore_table(record) do
    # Read the stored ledger BEFORE synthesizing, or the fresh cash-outs
    # would be counted twice.
    entries = Store.entries(record.code)
    stranded = Store.stranded_stacks(record.code)
    cashed_out = Enum.map(stranded, &synthesize_cash_out(record.code, &1))
    ledger = cashed_out ++ entries

    result =
      Table.create(%{
        code: record.code,
        name: record.name,
        description: record.description,
        blinds: {record.blinds_small, record.blinds_big},
        buy_in: %{min: record.buy_in_min, max: record.buy_in_max},
        turn_ms: record.turn_ms,
        between_hands_ms: record.between_hands_ms,
        creator: record.creator,
        password_hash: record.password_hash,
        sleep_when_unwatched: record.sleep_when_unwatched,
        ledger: ledger
      })

    case result do
      {:ok, _code} ->
        :ok

      # Someone else opened this code first: their table wins, and one
      # failed restore never takes the rest of the list down with it.
      {:error, reason} ->
        Logger.warning("could not restore table #{record.code}: #{inspect(reason)}")
        :ok
    end
  end

  # Their chips were on the felt when the lights went out; the comanda
  # records them leaving with exactly that.
  defp synthesize_cash_out(code, stack_record) do
    entry = %Ledger{
      player_id: stack_record.player_id,
      nickname: stack_record.nickname,
      kind: :cash_out,
      amount: stack_record.stack,
      at: DateTime.utc_now(:second)
    }

    :ok = Store.append_entry(code, entry)
    :ok = Store.drop_stack(code, stack_record.player_id)
    entry
  end
end
