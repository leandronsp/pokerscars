defmodule PokerscarsWeb.LobbyLive do
  @moduledoc "Create a table or join one by code. The whole front door."

  use PokerscarsWeb, :live_view

  alias Pokerscars.Table
  alias PokerscarsWeb.Age

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
       page_title: "pokerscars",
       og_title: gettext("pokerscars · no-limit texas hold'em entre amigos")
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
        <div class="pk-lobby-scene" aria-hidden="true">
          <span
            :for={{{rank, suit}, index} <- Enum.with_index(scene_cards(), 1)}
            class={[
              "pk-scene-card",
              "pk-scene-card-#{index}",
              suit in ~w(♥ ♦) && "pk-scene-card--red"
            ]}
          >
            <span class="pk-card-index">{rank}<i>{suit}</i></span>
            <span class="pk-card-index pk-card-index--flip">{rank}<i>{suit}</i></span>
            <span
              :for={{x, y, kind} <- pips(rank)}
              class={[
                "pk-card-pip",
                kind == :down && "pk-card-pip--down",
                kind == :big && "pk-card-pip--big",
                kind == :crown && "pk-card-pip--crown"
              ]}
              style={"left: #{x}%; top: #{y}%;"}
            >
              {if kind == :crown, do: "♛", else: suit}
            </span>
          </span>
          <svg class="pk-scene-piano" viewBox="0 0 160 150" xmlns="http://www.w3.org/2000/svg">
            <rect x="10" y="8" width="140" height="86" rx="4" fill="#2a190a" />
            <rect x="6" y="2" width="148" height="9" rx="2" fill="#3d2712" />
            <rect x="38" y="22" width="11" height="42" rx="3" fill="#1a1006" />
            <rect x="111" y="22" width="11" height="42" rx="3" fill="#1a1006" />
            <rect x="58" y="30" width="44" height="26" rx="2" fill="#1f1206" />
            <rect x="30" y="66" width="100" height="5" rx="1" fill="#3d2712" />
            <rect x="2" y="92" width="156" height="9" rx="2" fill="#3d2712" />
            <rect x="8" y="101" width="144" height="18" fill="#d9c9a6" />
            <rect
              :for={x <- [14, 22, 38, 46, 54, 70, 78, 94, 102, 110, 126, 134]}
              x={x}
              y="101"
              width="5"
              height="11"
              fill="#1a1006"
            />
            <rect x="8" y="119" width="144" height="4" fill="#241608" />
            <rect x="14" y="123" width="11" height="21" fill="#2a190a" />
            <rect x="135" y="123" width="11" height="21" fill="#2a190a" />
            <rect x="62" y="136" width="36" height="6" rx="2" fill="#1f1206" />
            <rect x="70" y="130" width="6" height="8" rx="2" fill="#7c5d26" />
            <rect x="84" y="130" width="6" height="8" rx="2" fill="#7c5d26" />
          </svg>
          <svg class="pk-scene-table" viewBox="0 0 220 170" xmlns="http://www.w3.org/2000/svg">
            <rect x="102" y="70" width="16" height="64" fill="#241608" />
            <path d="M74 152 L110 126 L146 152 Z" fill="#2a190a" />
            <rect x="66" y="148" width="88" height="7" rx="3" fill="#1f1206" />
            <ellipse cx="110" cy="52" rx="104" ry="30" fill="#3d2712" />
            <ellipse cx="110" cy="49" rx="96" ry="25" fill="#2f4636" />
            <ellipse cx="110" cy="48" rx="70" ry="16" fill="#38523f" opacity="0.7" />
            <g fill="#cfbb8f" stroke="#5a422a" stroke-width="0.6">
              <rect x="60" y="38" width="16" height="22" rx="2" transform="rotate(-14 68 49)" />
              <rect x="78" y="42" width="16" height="22" rx="2" transform="rotate(8 86 53)" />
              <rect x="118" y="35" width="16" height="22" rx="2" transform="rotate(20 126 46)" />
              <rect x="138" y="44" width="16" height="22" rx="2" transform="rotate(-9 146 55)" />
              <rect x="100" y="47" width="16" height="22" rx="2" transform="rotate(3 108 58)" />
              <rect x="52" y="52" width="16" height="22" rx="2" transform="rotate(24 60 63)" />
              <rect x="160" y="40" width="16" height="22" rx="2" transform="rotate(-18 168 51)" />
            </g>
            <g font-size="9">
              <text x="63" y="53" fill="#7a241c" transform="rotate(-14 68 49)">♥</text>
              <text x="81" y="57" fill="#2c1e10" transform="rotate(8 86 53)">♠</text>
              <text x="121" y="50" fill="#2c1e10" transform="rotate(20 126 46)">♣</text>
              <text x="141" y="59" fill="#7a241c" transform="rotate(-9 146 55)">♦</text>
            </g>
            <ellipse cx="90" cy="62" rx="7" ry="2.6" fill="#b3852f" />
            <ellipse cx="90" cy="59.5" rx="7" ry="2.6" fill="#caa64b" />
            <ellipse cx="176" cy="58" rx="7" ry="2.6" fill="#8a3324" />
            <ellipse cx="176" cy="55.5" rx="7" ry="2.6" fill="#a04a30" />
          </svg>
        </div>
        <div class="pk-lobby-hero">
          <div class="pk-hero-text">
            <h1 class="pk-lobby-title">♠ pokerscars</h1>
            <p class="pk-lobby-holdem">♦ no-limit texas hold'em ♣</p>
          </div>
          <div class="pk-hero-board">
            <span class="pk-hero-board-row">
              {ngettext("%{count} mesa aberta", "%{count} mesas abertas", length(@tables))}
            </span>
            <span class="pk-hero-board-row">
              {players_line(@tables)}
            </span>
            <span :if={bots_online(@tables) > 0} class="pk-hero-board-row">
              {ngettext("%{count} bot", "%{count} bots", bots_online(@tables))}
            </span>
            <span class="pk-hero-board-row">
              {ngettext("%{count} vaga", "%{count} vagas", seats_open(@tables))}
            </span>
          </div>
        </div>

        <div class="pk-lobby-grid">
          <div class="pk-lobby-forms">
            <form class="pk-panel pk-create-felt" phx-submit="create">
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
                style="text-align: center"
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

            <div class="pk-open-tables">
              <h2 class="pk-panel-title">{gettext("mesas abertas")}</h2>
              <p :if={@tables == []} class="pk-open-empty">
                {gettext("nenhuma mesa rolando agora. abre a primeira!")}
              </p>
              <div class="pk-open-grid">
                <div
                  :for={table <- @tables}
                  class={[
                    "pk-table-card",
                    table.locked? && "pk-table-card--locked",
                    table.seated >= 9 && "pk-table-card--full",
                    table.seated_me? && "pk-table-card--mine"
                  ]}
                >
                  <div class="pk-mini-felt" aria-hidden="true">
                    <span
                      :for={index <- 0..8}
                      class={["pk-mini-seat", index < table.seated && "pk-mini-seat--on"]}
                    />
                    <span :if={table.locked?} class="pk-felt-lock">
                      <.icon name="hero-lock-closed" class="size-3" />
                    </span>
                  </div>
                  <span class="pk-table-card-name">
                    <.icon :if={table.locked?} name="hero-lock-closed" class="size-3.5 pk-lock" /> {table.name}
                  </span>
                  <span
                    :if={table.system? or table.seated >= 9 or table.seated_me?}
                    class="pk-table-card-badges"
                  >
                    <span :if={table.system?} class="pk-badge-house">{gettext("mesa da casa")}</span>
                    <span :if={table.seated >= 9} class="pk-badge-full">{gettext("lotada")}</span>
                    <span :if={table.seated_me?} class="pk-badge-me">{gettext("você está nessa")}</span>
                  </span>
                  <span :if={table.description} class="pk-table-card-desc">{table.description}</span>
                  <span class="pk-table-card-meta">
                    {PokerscarsWeb.Money.chips(elem(table.blinds, 0), @currency)} / {PokerscarsWeb.Money.chips(
                      elem(table.blinds, 1),
                      @currency
                    )} · {ngettext("%{count} vaga", "%{count} vagas", 9 - table.seated)}
                  </span>
                  <span class="pk-table-card-meta">
                    <span :if={table.hand_no > 0}>{gettext("mão #%{n}", n: table.hand_no)} · </span>
                    <span class="pk-code">{table.code}</span>
                  </span>
                  <span class="pk-table-card-meta pk-table-card-meta--age">
                    {gettext("aberta %{age}", age: Age.since(table.created_at))}<span :if={
                      table.played_ms >= 60_000
                    }> · {gettext(
                      "%{time} de jogo",
                      time: Age.play(table.played_ms)
                    )}</span>
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
              </div>
            </div>
          </div>
        </div>

        <footer class="pk-lobby-foot">
          <span>
            {gettext("poker entre amigos, sem enrolação")} · {gettext("fichas sem valor real")}
          </span>
          <span>
            <.link navigate={~p"/termos"}>{gettext("termos de uso")}</.link>
            · <a href="https://github.com/leandronsp/pokerscars">{gettext("código aberto (AGPL)")}</a>
            · {gettext("feito por")} <a href="https://github.com/leandronsp">@leandronsp</a>
          </span>
        </footer>
      </div>
    </Layouts.app>
    """
  end

  # An empty saloon says so in words: "0 jogador" reads like a bug.
  defp players_line(tables) do
    case tables |> Enum.map(&(&1.seated - &1.bots)) |> Enum.sum() do
      0 -> gettext("nenhum jogador online")
      n -> ngettext("%{count} jogador online", "%{count} jogadores online", n)
    end
  end

  defp bots_online(tables), do: tables |> Enum.map(& &1.bots) |> Enum.sum()
  defp seats_open(tables), do: tables |> Enum.map(&(9 - &1.seated)) |> Enum.sum()

  # The dead man's hand: aces and eights, plus the two disputed fifth cards.
  defp scene_cards,
    do: [{"A", "♠"}, {"A", "♣"}, {"8", "♠"}, {"8", "♥"}, {"9", "♦"}, {"Q", "♦"}]

  # Pip coordinates {x%, y%, kind} follow the classic deck layouts; pips on
  # the bottom half render upside down, as on a real card.
  defp pips("A"), do: [{50, 50, :big}]

  defp pips("8") do
    for(x <- [31, 69], y <- [24, 50], do: {x, y, :up}) ++
      for(x <- [31, 69], do: {x, 76, :down}) ++
      [{50, 37, :up}, {50, 63, :down}]
  end

  defp pips("9") do
    for(x <- [31, 69], y <- [22, 41], do: {x, y, :up}) ++
      for(x <- [31, 69], y <- [59, 78], do: {x, y, :down}) ++
      [{50, 50, :up}]
  end

  defp pips("Q"), do: [{50, 46, :crown}, {50, 74, :down}]
end
