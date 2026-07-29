defmodule PokerscarsWeb.RestoreLocale do
  @moduledoc "LiveView on_mount hook: locale and currency travel in the session."

  import Phoenix.Component, only: [assign: 3]

  @spec on_mount(:default, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, session, socket) do
    locale = session["locale"] || "pt_BR"
    # put_locale returns the previous locale; nothing to do with it.
    _previous = Gettext.put_locale(PokerscarsWeb.Gettext, locale)

    {:cont,
     socket
     |> assign(:locale, locale)
     |> assign(:currency, session["currency"] || "BRL")}
  end
end
