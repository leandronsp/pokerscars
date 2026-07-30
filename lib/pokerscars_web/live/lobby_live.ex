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
  def mount(_params, session, socket) do
    if connected?(socket), do: Table.subscribe_lobby()

    {:ok,
     assign(socket,
       player_id: session["player_id"],
       blind_options: @blind_options,
       clock_options: @clock_options,
       tables: Table.list(session["player_id"]),
       page_title: "pokerscars"
     )}
  end

  @impl Phoenix.LiveView
  def handle_info({:lobby_updated}, socket),
    do: {:noreply, assign(socket, tables: Table.list(socket.assigns.player_id))}

  @impl Phoenix.LiveView
  def handle_event(
        "create",
        %{"name" => name, "blinds" => blinds, "clock" => clock} = params,
        socket
      ) do
    [small, big] = blinds |> String.split("-") |> Enum.map(&String.to_integer/1)
    name = if String.trim(name) == "", do: gettext("Mesa dos amigos"), else: String.trim(name)
    password = String.trim(params["password"] || "")

    result =
      Table.create(%{
        name: name,
        blinds: {small, big},
        buy_in: %{min: big * 20, max: big * 200},
        turn_ms: String.to_integer(clock) * 1000,
        creator: socket.assigns.player_id,
        password_hash: if(password != "", do: :crypto.hash(:sha256, password))
      })

    case result do
      {:ok, code} ->
        to =
          if password == "",
            do: ~p"/t/#{code}",
            else: ~p"/t/#{code}?key=#{PokerscarsWeb.TableAccess.sign(code)}"

        {:noreply, push_navigate(socket, to: to)}

      {:error, :too_many_tables} ->
        {:noreply,
         put_flash(socket, :error, gettext("você já tem mesas demais abertas; encerra uma antes"))}

      {:error, :house_full} ->
        {:noreply, put_flash(socket, :error, gettext("o salão está lotado agora, tenta já já"))}

      {:error, :name_not_allowed} ->
        {:noreply, put_flash(socket, :error, gettext("esse nome não rola aqui, escolhe outro"))}
    end
  end

  def handle_event("close_table", %{"code" => code}, socket) do
    case Table.close(code, socket.assigns.player_id) do
      :ok ->
        {:noreply, assign(socket, tables: Table.list(socket.assigns.player_id))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("só quem criou a mesa pode encerrar"))}
    end
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
          <p class="pk-lobby-stats">
            {ngettext("%{count} mesa aberta", "%{count} mesas abertas", length(@tables))} · {ngettext(
              "%{count} jogador",
              "%{count} jogadores",
              seated_total(@tables)
            )} · {ngettext("%{count} vaga", "%{count} vagas", seats_open(@tables))}
          </p>
        </div>

        <div class="pk-lobby-grid">
          <div class="pk-lobby-forms">
            <form class="pk-panel" phx-submit="create">
              <h2 class="pk-panel-title">{gettext("criar mesa")}</h2>
              <label class="pk-field">
                <span>{gettext("nome da mesa")}</span>
                <input type="text" name="name" placeholder={gettext("sexta dos cara")} maxlength="40" />
              </label>
              <div class="pk-field">
                <span>{gettext("blinds")}</span>
                <div class="pk-choice-row">
                  <label :for={{label, value} <- @blind_options} class="pk-choice">
                    <input type="radio" name="blinds" value={value} checked={value == "25-50"} />
                    <span>{label}</span>
                  </label>
                </div>
              </div>
              <div class="pk-field">
                <span>{gettext("tempo de ação")}</span>
                <div class="pk-choice-row">
                  <label :for={{label, value} <- @clock_options} class="pk-choice">
                    <input type="radio" name="clock" value={value} checked={value == "45"} />
                    <span>{label}</span>
                  </label>
                </div>
              </div>
              <label class="pk-field">
                <span>{gettext("senha (opcional — sala fica trancada)")}</span>
                <input type="text" name="password" maxlength="24" autocomplete="off" />
              </label>
              <button type="submit" class="pk-btn pk-btn--raise pk-btn--wide">
                {gettext("abrir a mesa")}
              </button>
            </form>
          </div>

          <div class="pk-lobby-right">
            <form class="pk-join-inline" phx-submit="join">
              <input
                type="text"
                name="code"
                placeholder={gettext("código da mesa")}
                aria-label={gettext("código da mesa")}
                maxlength="6"
                autocapitalize="characters"
                class="pk-input--code"
                required
              />
              <button
                type="submit"
                class="pk-btn pk-btn--ghost pk-join-go"
                aria-label={gettext("entrar na mesa")}
                title={gettext("entrar na mesa")}
              >
                <.icon name="hero-arrow-right-end-on-rectangle" class="size-5" />
              </button>
            </form>

            <div class="pk-panel pk-open-tables">
              <h2 class="pk-panel-title">{gettext("mesas abertas")}</h2>
              <p :if={@tables == []} class="pk-open-empty">
                {gettext("nenhuma mesa rolando agora. abre a primeira!")}
              </p>
              <div
                :for={table <- @tables}
                class={[
                  "pk-table-card",
                  table.locked? && "pk-table-card--locked",
                  table.seated_me? && "pk-table-card--mine"
                ]}
              >
                <div class="pk-table-card-top">
                  <span class="pk-table-card-name">
                    <.icon :if={table.locked?} name="hero-lock-closed" class="size-3.5 pk-lock" /> {table.name}
                    <span :if={table.system?} class="pk-badge-house">{gettext("mesa da casa")}</span>
                    <span :if={table.seated >= 9} class="pk-badge-full">{gettext("lotada")}</span>
                    <span :if={table.seated_me?} class="pk-badge-me">{gettext("você está nessa")}</span>
                  </span>
                  <div class="pk-table-card-actions">
                    <.link
                      navigate={~p"/t/#{table.code}"}
                      class={[
                        "pk-btn pk-btn--slim",
                        (table.seated_me? && "pk-btn--raise") || "pk-btn--call"
                      ]}
                    >
                      {(table.seated_me? && gettext("voltar")) || gettext("entrar")}
                    </.link>
                    <.link
                      navigate={~p"/t/#{table.code}"}
                      class="pk-btn pk-btn--ghost pk-btn--slim pk-btn--icon"
                      title={gettext("espiar")}
                    >
                      <.icon name="hero-eye" class="size-4" />
                    </.link>
                    <button
                      :if={table.mine?}
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
                <span :if={table.description} class="pk-table-card-desc">{table.description}</span>
                <div class="pk-table-card-foot">
                  <div class="pk-mini-felt" aria-hidden="true">
                    <span
                      :for={index <- 0..8}
                      class={["pk-mini-seat", index < table.seated && "pk-mini-seat--on"]}
                    />
                  </div>
                  <span class="pk-table-card-meta">
                    {gettext("blinds")} {PokerscarsWeb.Money.chips(elem(table.blinds, 0), @currency)} / {PokerscarsWeb.Money.chips(
                      elem(table.blinds, 1),
                      @currency
                    )} · {ngettext("%{count} jogador", "%{count} jogadores", table.seated)} · {ngettext(
                      "%{count} vaga",
                      "%{count} vagas",
                      9 - table.seated
                    )}
                    <span :if={table.hand_no > 0}>
                      · {gettext("mão #%{n}", n: table.hand_no)}
                    </span>
                    · <span class="pk-code">{table.code}</span>
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <p class="pk-lobby-foot">
          {gettext("fichas sem valor real · código aberto, AGPL · sirva-se")}
        </p>
      </div>
    </Layouts.app>
    """
  end

  defp seated_total(tables), do: tables |> Enum.map(& &1.seated) |> Enum.sum()
  defp seats_open(tables), do: tables |> Enum.map(&(9 - &1.seated)) |> Enum.sum()
end
