defmodule PokerscarsWeb.Plugs.EnsurePlayerId do
  @moduledoc """
  Gives every browser session a stable anonymous `player_id`. Seats, ledger
  entries and hole-card projections all key on it — no accounts in the MVP.
  """

  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case get_session(conn, :player_id) do
      nil -> put_session(conn, :player_id, generate_id())
      _id -> conn
    end
  end

  defp generate_id, do: :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
end
