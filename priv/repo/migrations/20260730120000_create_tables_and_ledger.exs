defmodule Pokerscars.Repo.Migrations.CreateTablesAndLedger do
  use Ecto.Migration

  def change do
    create table(:tables) do
      add :code, :string, null: false
      add :name, :string, null: false
      add :description, :string
      add :blinds_small, :integer, null: false
      add :blinds_big, :integer, null: false
      add :buy_in_min, :integer, null: false
      add :buy_in_max, :integer, null: false
      add :turn_ms, :integer, null: false
      add :between_hands_ms, :integer, null: false
      add :creator, :string
      add :password_hash, :binary
      add :sleep_when_unwatched, :boolean, null: false, default: false
      add :closed_at, :utc_datetime

      timestamps()
    end

    create unique_index(:tables, [:code])

    create table(:ledger_entries) do
      add :table_code, :string, null: false
      add :player_id, :string, null: false
      add :nickname, :string, null: false
      add :kind, :string, null: false
      add :amount, :integer, null: false
      add :at, :utc_datetime, null: false
    end

    create index(:ledger_entries, [:table_code])

    create table(:stack_snapshots) do
      add :table_code, :string, null: false
      add :player_id, :string, null: false
      add :nickname, :string, null: false
      add :stack, :integer, null: false

      timestamps()
    end

    create unique_index(:stack_snapshots, [:table_code, :player_id])
  end
end
