defmodule PokerscarsWeb.Plugs.SetLocale do
  @moduledoc "Applies the session's locale to Gettext for plain HTTP renders."

  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    # put_locale returns the previous locale; nothing to do with it.
    _previous = Gettext.put_locale(PokerscarsWeb.Gettext, get_session(conn, :locale) || "pt_BR")
    conn
  end
end
