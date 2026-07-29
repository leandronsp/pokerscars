defmodule PokerscarsWeb.LobbyLive do
  @moduledoc "Create a table or join one by code. The whole front door."

  use PokerscarsWeb, :live_view

  alias Pokerscars.Table

  @blind_options [
    {"0,05 / 0,10", "5-10"},
    {"0,25 / 0,50", "25-50"},
    {"0,50 / 1,00", "50-100"},
    {"1,00 / 2,00", "100-200"}
  ]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket), do: Table.subscribe_lobby()

    {:ok,
     assign(socket,
       blind_options: @blind_options,
       tables: Table.list(),
       page_title: "pokerscars"
     )}
  end

  @impl Phoenix.LiveView
  def handle_info({:lobby_updated}, socket), do: {:noreply, assign(socket, tables: Table.list())}

  @impl Phoenix.LiveView
  def handle_event("create", %{"name" => name, "blinds" => blinds}, socket) do
    [small, big] = blinds |> String.split("-") |> Enum.map(&String.to_integer/1)
    name = if String.trim(name) == "", do: gettext("Mesa dos amigos"), else: String.trim(name)

    {:ok, code} =
      Table.create(%{
        name: name,
        blinds: {small, big},
        buy_in: %{min: big * 20, max: big * 200}
      })

    {:noreply, push_navigate(socket, to: ~p"/t/#{code}")}
  end

  def handle_event("join", %{"code" => code}, socket) do
    code = code |> String.trim() |> String.upcase()

    if Table.exists?(code) do
      {:noreply, push_navigate(socket, to: ~p"/t/#{code}")}
    else
      {:noreply, put_flash(socket, :error, gettext("mesa não encontrada"))}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="pk-lobby">
        <div class="pk-lobby-hero">
          <h1 class="pk-lobby-title">pokerscars</h1>
          <p class="pk-lobby-tagline">{gettext("poker entre amigos, sem enrolação")}</p>
        </div>

        <div class="pk-lobby-cards">
          <form class="pk-panel" phx-submit="create">
            <h2 class="pk-panel-title">{gettext("criar mesa")}</h2>
            <label class="pk-field">
              <span>{gettext("nome da mesa")}</span>
              <input type="text" name="name" placeholder={gettext("sexta dos cara")} maxlength="40" />
            </label>
            <label class="pk-field">
              <span>{gettext("blinds")}</span>
              <select name="blinds">
                <option
                  :for={{label, value} <- @blind_options}
                  value={value}
                  selected={value == "25-50"}
                >
                  {label}
                </option>
              </select>
            </label>
            <button type="submit" class="pk-btn pk-btn--raise pk-btn--wide">
              {gettext("abrir a mesa")}
            </button>
          </form>

          <form class="pk-panel" phx-submit="join">
            <h2 class="pk-panel-title">{gettext("entrar numa mesa")}</h2>
            <label class="pk-field">
              <span>{gettext("código da mesa")}</span>
              <input
                type="text"
                name="code"
                placeholder="ABC234"
                maxlength="6"
                autocapitalize="characters"
                class="pk-input--code"
              />
            </label>
            <button type="submit" class="pk-btn pk-btn--call pk-btn--wide">
              {gettext("entrar")}
            </button>
          </form>
        </div>

        <div :if={@tables != []} class="pk-panel pk-open-tables">
          <h2 class="pk-panel-title">{gettext("mesas abertas")}</h2>
          <.link :for={table <- @tables} navigate={~p"/t/#{table.code}"} class="pk-open-table">
            <span class="pk-open-table-name">{table.name}</span>
            <span class="pk-open-table-meta">
              {gettext("blinds")} {PokerscarsWeb.Money.chips(elem(table.blinds, 0))} / {PokerscarsWeb.Money.chips(
                elem(table.blinds, 1)
              )} · {ngettext("%{count} jogador", "%{count} jogadores", table.seated)}
            </span>
            <span class="pk-code">{table.code}</span>
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
