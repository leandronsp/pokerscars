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

  @clock_options [{"30s", "30"}, {"45s", "45"}, {"60s", "60"}, {"90s", "90"}]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket), do: Table.subscribe_lobby()

    {:ok,
     assign(socket,
       blind_options: @blind_options,
       clock_options: @clock_options,
       tables: Table.list(),
       page_title: "pokerscars"
     )}
  end

  @impl Phoenix.LiveView
  def handle_info({:lobby_updated}, socket), do: {:noreply, assign(socket, tables: Table.list())}

  @impl Phoenix.LiveView
  def handle_event("create", %{"name" => name, "blinds" => blinds, "clock" => clock}, socket) do
    [small, big] = blinds |> String.split("-") |> Enum.map(&String.to_integer/1)
    name = if String.trim(name) == "", do: gettext("Mesa dos amigos"), else: String.trim(name)

    {:ok, code} =
      Table.create(%{
        name: name,
        blinds: {small, big},
        buy_in: %{min: big * 20, max: big * 200},
        turn_ms: String.to_integer(clock) * 1000
      })

    {:noreply, push_navigate(socket, to: ~p"/t/#{code}")}
  end

  def handle_event("close_table", %{"code" => code}, socket) do
    _result = Table.close(code)
    {:noreply, assign(socket, tables: Table.list())}
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
    <Layouts.app flash={@flash} locale={@locale} currency={@currency}>
      <div class="pk-lobby">
        <div class="pk-lobby-hero">
          <h1 class="pk-lobby-title">pokerscars</h1>
          <p class="pk-lobby-tagline">{gettext("poker entre amigos, sem enrolação")}</p>
        </div>

        <div class="pk-lobby-grid">
          <div class="pk-lobby-forms">
            <form class="pk-panel" phx-submit="create">
              <h2 class="pk-panel-title">{gettext("criar mesa")}</h2>
              <label class="pk-field">
                <span>{gettext("nome da mesa")}</span>
                <input type="text" name="name" placeholder={gettext("sexta dos cara")} maxlength="40" />
              </label>
              <div class="pk-field-row">
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
                <label class="pk-field">
                  <span>{gettext("tempo de ação")}</span>
                  <select name="clock">
                    <option
                      :for={{label, value} <- @clock_options}
                      value={value}
                      selected={value == "45"}
                    >
                      {label}
                    </option>
                  </select>
                </label>
              </div>
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

          <div class="pk-panel pk-open-tables">
            <h2 class="pk-panel-title">{gettext("mesas abertas")}</h2>
            <p :if={@tables == []} class="pk-open-empty">
              {gettext("nenhuma mesa rolando agora — abre a primeira!")}
            </p>
            <div :for={table <- @tables} class="pk-table-card">
              <div class="pk-mini-felt" aria-hidden="true">
                <span
                  :for={index <- 0..8}
                  class={["pk-mini-seat", index < table.seated && "pk-mini-seat--on"]}
                />
              </div>
              <div class="pk-table-card-info">
                <span class="pk-table-card-name">{table.name}</span>
                <span class="pk-table-card-meta">
                  {gettext("blinds")} {PokerscarsWeb.Money.chips(elem(table.blinds, 0), @currency)} / {PokerscarsWeb.Money.chips(
                    elem(table.blinds, 1),
                    @currency
                  )}
                </span>
                <span class="pk-table-card-meta">
                  {ngettext("%{count} jogador", "%{count} jogadores", table.seated)} ·
                  <span class="pk-code">{table.code}</span>
                </span>
              </div>
              <div class="pk-table-card-actions">
                <.link navigate={~p"/t/#{table.code}"} class="pk-btn pk-btn--call pk-btn--slim">
                  {gettext("entrar")}
                </.link>
                <.link
                  navigate={~p"/t/#{table.code}"}
                  class="pk-btn pk-btn--ghost pk-btn--slim pk-btn--icon"
                  title={gettext("espiar")}
                >
                  <.icon name="hero-eye" class="size-4" />
                </.link>
                <button
                  class="pk-btn pk-btn--ghost pk-btn--slim pk-btn--icon pk-btn--danger-ghost"
                  phx-click="close_table"
                  phx-value-code={table.code}
                  data-confirm={gettext("Encerrar a mesa? Isso derruba todo mundo.")}
                  title={gettext("encerrar")}
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
