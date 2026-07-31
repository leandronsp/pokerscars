defmodule Pokerscars.Repo.Migrations.AddPlayedMsToTables do
  use Ecto.Migration

  def change do
    alter table(:tables) do
      # bigint: house tables run bots around the clock; int4 milliseconds
      # would overflow in under a month of accumulated play.
      add :played_ms, :bigint, null: false, default: 0
    end
  end
end
