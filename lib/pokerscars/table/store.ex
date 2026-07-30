defmodule Pokerscars.Table.Store do
  @moduledoc """
  Durability for the tables context: open tables, their ledgers and a
  stack snapshot per seated player, all in Postgres. The game never
  depends on the database to play — every write is best-effort behind
  `enabled?/0` and a rescue, and a restart restores what money-truth
  requires: the table and its comanda. Hands, chat and events stay
  transient by design.
  """

  import Ecto.Query

  alias Pokerscars.Repo
  alias Pokerscars.Table.Ledger

  require Logger

  defmodule TableRecord do
    @moduledoc "One open (or closed) table as stored."

    use Ecto.Schema

    @type t :: %__MODULE__{}

    schema "tables" do
      field :code, :string
      field :name, :string
      field :description, :string
      field :blinds_small, :integer
      field :blinds_big, :integer
      field :buy_in_min, :integer
      field :buy_in_max, :integer
      field :turn_ms, :integer
      field :between_hands_ms, :integer
      field :creator, :string
      field :password_hash, :binary
      field :sleep_when_unwatched, :boolean, default: false
      field :closed_at, :utc_datetime

      timestamps()
    end
  end

  defmodule EntryRecord do
    @moduledoc "One ledger line as stored."

    use Ecto.Schema

    @type t :: %__MODULE__{}

    schema "ledger_entries" do
      field :table_code, :string
      field :player_id, :string
      field :nickname, :string
      field :kind, Ecto.Enum, values: [:buy_in, :cash_out]
      field :amount, :integer
      field :at, :utc_datetime
    end
  end

  defmodule StackRecord do
    @moduledoc "The last known stack of a seated player."

    use Ecto.Schema

    @type t :: %__MODULE__{}

    schema "stack_snapshots" do
      field :table_code, :string
      field :player_id, :string
      field :nickname, :string
      field :stack, :integer

      timestamps()
    end
  end

  @doc "Whether persistence is on. Tests turn it off globally."
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:pokerscars, :persist_tables, true)

  @doc "Upserts a table's configuration by code."
  @spec save_table(map()) :: :ok
  def save_table(config) do
    best_effort(fn ->
      {small, big} = config.blinds

      _record =
        Repo.insert!(
          %TableRecord{
            code: config.code,
            name: config.name,
            description: config[:description],
            blinds_small: small,
            blinds_big: big,
            buy_in_min: config.buy_in.min,
            buy_in_max: config.buy_in.max,
            turn_ms: Map.get(config, :turn_ms, 45_000),
            between_hands_ms: Map.get(config, :between_hands_ms, 12_000),
            creator: config[:creator],
            password_hash: config[:password_hash],
            sleep_when_unwatched: Map.get(config, :sleep_when_unwatched, false)
          },
          on_conflict: {:replace_all_except, [:id, :code, :inserted_at]},
          conflict_target: :code
        )
    end)
  end

  @doc "Marks a table closed: it will not be restored."
  @spec close_table(String.t()) :: :ok
  def close_table(code) do
    best_effort(fn ->
      {_count, _rows} =
        from(t in TableRecord, where: t.code == ^code)
        |> Repo.update_all(set: [closed_at: DateTime.utc_now(:second)])
    end)
  end

  @doc "Appends one ledger entry."
  @spec append_entry(String.t(), Ledger.t()) :: :ok
  def append_entry(code, %Ledger{} = entry) do
    best_effort(fn ->
      _record =
        Repo.insert!(%EntryRecord{
          table_code: code,
          player_id: entry.player_id,
          nickname: entry.nickname,
          kind: entry.kind,
          amount: entry.amount,
          at: DateTime.truncate(entry.at, :second)
        })
    end)
  end

  @doc "Upserts the last known stacks of the seated players."
  @spec snapshot_stacks(String.t(), [map()]) :: :ok
  def snapshot_stacks(_code, []), do: :ok

  def snapshot_stacks(code, seats) do
    best_effort(fn ->
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      rows =
        Enum.map(seats, fn seat ->
          %{
            table_code: code,
            player_id: seat.player_id,
            nickname: seat.nickname,
            stack: seat.stack,
            inserted_at: now,
            updated_at: now
          }
        end)

      {_count, _rows} =
        Repo.insert_all(StackRecord, rows,
          on_conflict: {:replace, [:stack, :nickname, :updated_at]},
          conflict_target: [:table_code, :player_id]
        )
    end)
  end

  @doc "Forgets a player's snapshot (they cashed out properly)."
  @spec drop_stack(String.t(), String.t()) :: :ok
  def drop_stack(code, player_id) do
    best_effort(fn ->
      {_count, _rows} =
        from(s in StackRecord, where: s.table_code == ^code and s.player_id == ^player_id)
        |> Repo.delete_all()
    end)
  end

  @doc "Every table that was open when the lights went out."
  @spec open_tables() :: [TableRecord.t()]
  def open_tables do
    Repo.all(from(t in TableRecord, where: is_nil(t.closed_at)))
  end

  @doc "A table's ledger, newest first, as in-memory entries."
  @spec entries(String.t()) :: [Ledger.t()]
  def entries(code) do
    from(e in EntryRecord, where: e.table_code == ^code, order_by: [desc: e.id])
    |> Repo.all()
    |> Enum.map(fn record ->
      %Ledger{
        player_id: record.player_id,
        nickname: record.nickname,
        kind: record.kind,
        amount: record.amount,
        at: record.at
      }
    end)
  end

  @doc "Players who were still seated when the lights went out."
  @spec stranded_stacks(String.t()) :: [StackRecord.t()]
  def stranded_stacks(code) do
    Repo.all(from(s in StackRecord, where: s.table_code == ^code))
  end

  # The game must never die of a database hiccup: log and move on.
  defp best_effort(fun) do
    if enabled?() do
      _result = fun.()
      :ok
    else
      :ok
    end
  rescue
    exception ->
      Logger.warning("table store write failed: #{Exception.message(exception)}")
      :ok
  end
end
