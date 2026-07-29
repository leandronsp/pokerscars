defmodule PokerscarsWeb.PrefsController do
  @moduledoc "Stores display preferences (locale, currency) in the session."

  use PokerscarsWeb, :controller

  @locales ~w(pt_BR en)
  @currencies ~w(BRL USD EUR)

  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, params) do
    conn
    |> maybe_put(:locale, params["locale"], @locales)
    |> maybe_put(:currency, params["currency"], @currencies)
    |> redirect(to: return_path(conn))
  end

  defp maybe_put(conn, key, value, allowed) do
    if value in allowed, do: put_session(conn, key, value), else: conn
  end

  defp return_path(conn) do
    case get_req_header(conn, "referer") do
      [referer | _rest] -> URI.parse(referer).path || "/"
      [] -> "/"
    end
  end
end
