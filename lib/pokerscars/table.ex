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

  # Pre-public spam gates: a creator holds a few tables at most, and the
  # house has a ceiling. Creatorless tables (tests, internal) are exempt.
  @max_tables_per_creator 5
  @max_open_tables 500

  # The house's own rooms: nobody matches this id, so nobody closes them or
  # summons bots into them. See Pokerscars.SystemRooms.
  @system_creator "system"

  @doc "The creator id owned by the app itself."
  @spec system_creator() :: player_id()
  def system_creator, do: @system_creator

  @doc "Creates a table and returns its join code."
  @spec create(map()) :: {:ok, code()} | {:error, :house_full | :too_many_tables}
  def create(config) do
    cond do
      Registry.count(@registry) >= @max_open_tables ->
        {:error, :house_full}

      creator_table_count(config[:creator]) >= @max_tables_per_creator ->
        {:error, :too_many_tables}

      config[:code] != nil and exists?(config[:code]) ->
        {:error, :code_taken}

      true ->
        code = config[:code] || generate_code()

        {:ok, _pid} =
          DynamicSupervisor.start_child(@supervisor, {Server, Map.put(config, :code, code)})

        :ok = broadcast_lobby()
        {:ok, code}
    end
  end

  defp creator_table_count(nil), do: 0

  defp creator_table_count(creator) do
    @registry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [:"$2"]}])
    |> Enum.count(fn pid ->
      try do
        GenServer.call(pid, :summary).creator == creator
      catch
        :exit, _reason -> false
      end
    end)
  end

  @spec exists?(code()) :: boolean()
  def exists?(code), do: Registry.lookup(@registry, code) != []

  @doc """
  Every open table's lobby card: code, name, blinds, seated count, whether
  it is locked and whether the viewer created it. Creator ids never leave.
  """
  @spec list(player_id() | nil) :: [map()]
  def list(viewer \\ nil) do
    @registry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.flat_map(fn {_code, pid} ->
      try do
        [GenServer.call(pid, :summary)]
      catch
        # A table shutting down mid-listing is not the lobby's problem.
        :exit, _reason -> []
      end
    end)
    |> Enum.map(fn summary ->
      summary
      |> Map.put(:mine?, summary.creator == viewer and viewer != nil)
      |> Map.put(:system?, summary.creator == @system_creator)
      |> Map.delete(:creator)
    end)
    |> Enum.sort_by(&{not &1.system?, -&1.seated})
  end

  @doc "The creator's player id, or nil for creatorless (internal) tables."
  @spec creator(code()) :: player_id() | nil
  def creator(code) do
    case call(code, :summary) do
      %{creator: creator} -> creator
      _error -> nil
    end
  end

  @doc "True when the room only admits people with the password or the link."
  @spec locked?(code()) :: boolean()
  def locked?(code) do
    case call(code, :summary) do
      %{locked?: locked?} -> locked?
      _error -> false
    end
  end

  @doc "Checks a locked room's password."
  @spec check_password(code(), String.t()) :: boolean()
  def check_password(code, password) do
    case call(code, {:check_password, password}) do
      true -> true
      _other -> false
    end
  end

  @doc """
  Closes a table for good: viewers are told first, then the process stops.
  Anyone at the lobby may close a table — it is a friends app, the social
  contract is the authorization layer.
  """
  @spec close(code(), player_id() | :admin) :: :ok | {:error, :table_not_found | :not_owner}
  def close(code, requester \\ :admin) do
    case Registry.lookup(@registry, code) do
      [{pid, _value}] ->
        %{creator: creator} = GenServer.call(pid, :summary)

        if requester == :admin or creator == nil or creator == requester do
          :ok = Phoenix.PubSub.broadcast(Pokerscars.PubSub, topic(code), {:table_closed, code})
          :ok = DynamicSupervisor.terminate_child(@supervisor, pid)
          broadcast_lobby()
        else
          {:error, :not_owner}
        end

      [] ->
        {:error, :table_not_found}
    end
  end

  @doc "Subscribes the caller to `{:lobby_updated}` broadcasts."
  @spec subscribe_lobby() :: :ok
  def subscribe_lobby, do: Phoenix.PubSub.subscribe(Pokerscars.PubSub, "lobby")

  @doc false
  @spec broadcast_lobby() :: :ok
  def broadcast_lobby, do: Phoenix.PubSub.broadcast(Pokerscars.PubSub, "lobby", {:lobby_updated})

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

  @doc "Hides the caller's revealed cards during the showdown pause."
  @spec muck(code(), player_id()) :: :ok | {:error, atom()}
  def muck(code, player_id), do: call(code, {:muck, player_id})

  @doc "Says something at the table. Seated players only; see Table.Chat for the rules."
  @spec chat(code(), player_id(), Pokerscars.Table.Chat.payload()) :: :ok | {:error, atom()}
  def chat(code, player_id, payload), do: call(code, {:chat, player_id, payload})

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
      [{pid, _value}] ->
        try do
          GenServer.call(pid, message)
        catch
          # The table died between lookup and call (crash, restart window):
          # to the caller that is the same as the table not existing.
          :exit, {:noproc, _call} -> {:error, :table_not_found}
        end

      [] ->
        {:error, :table_not_found}
    end
  end

  defp generate_code do
    code = for _digit <- 1..6, into: "", do: <<Enum.random(@code_alphabet)>>
    if exists?(code), do: generate_code(), else: code
  end
end
