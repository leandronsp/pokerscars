defmodule Pokerscars.Table do
  @moduledoc """
  The running-tables context: create a table, sit with a buy-in, act, watch.
  One GenServer per table is the aggregate root; this module is the only door
  other contexts and the web layer may use. State is projected per player by
  `view/2` — hole cards never leave the process for anyone else's eyes.
  """

  alias Pokerscars.Table.{Server, View}

  @registry Pokerscars.Table.Registry
  @supervisor Pokerscars.Table.Supervisor
  # No 0/O/1/I/L: codes get read out loud over voice chat.
  @code_alphabet ~c"ABCDEFGHJKMNPQRSTUVWXYZ23456789"

  @type code :: String.t()
  @type player_id :: String.t()

  @doc "Creates a table and returns its join code."
  @spec create(map()) :: {:ok, code()}
  def create(config) do
    code = generate_code()

    {:ok, _pid} =
      DynamicSupervisor.start_child(@supervisor, {Server, Map.put(config, :code, code)})

    {:ok, code}
  end

  @spec exists?(code()) :: boolean()
  def exists?(code), do: Registry.lookup(@registry, code) != []

  @doc "Takes a seat with a buy-in. The buy-in is recorded in the ledger."
  @spec sit(code(), player_id(), String.t(), non_neg_integer(), pos_integer()) ::
          :ok | {:error, atom()}
  def sit(code, player_id, nickname, position, amount),
    do: call(code, {:sit, player_id, nickname, position, amount})

  @doc "Adds chips to a seated player, applied between hands."
  @spec rebuy(code(), player_id(), pos_integer()) :: :ok | {:error, atom()}
  def rebuy(code, player_id, amount), do: call(code, {:rebuy, player_id, amount})

  @doc "Leaves the table, cashing the stack out to the ledger."
  @spec stand(code(), player_id()) :: :ok | {:error, atom()}
  def stand(code, player_id), do: call(code, {:stand, player_id})

  @spec act(code(), player_id(), Pokerscars.Engine.BettingRound.action()) ::
          :ok | {:error, atom()}
  def act(code, player_id, action), do: call(code, {:act, player_id, action})

  @doc "This player's projection of the table. Everyone else's cards stay hidden."
  @spec view(code(), player_id()) :: {:ok, View.t()} | {:error, atom()}
  def view(code, player_id), do: call(code, {:view, player_id})

  @doc "Subscribes the caller to `{:table_updated, code}` broadcasts."
  @spec subscribe(code()) :: :ok
  def subscribe(code), do: Phoenix.PubSub.subscribe(Pokerscars.PubSub, topic(code))

  @doc false
  @spec topic(code()) :: String.t()
  def topic(code), do: "table:#{code}"

  @doc false
  @spec via(code()) :: {:via, Registry, {module(), code()}}
  def via(code), do: {:via, Registry, {@registry, code}}

  defp call(code, message) do
    case Registry.lookup(@registry, code) do
      [{pid, _value}] -> GenServer.call(pid, message)
      [] -> {:error, :table_not_found}
    end
  end

  defp generate_code do
    code = for _digit <- 1..6, into: "", do: <<Enum.random(@code_alphabet)>>
    if exists?(code), do: generate_code(), else: code
  end
end
