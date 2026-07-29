defmodule PokerscarsWeb.TableLive do
  @moduledoc """
  The table screen. Renders the player's `Table.View` projection verbatim and
  forwards commands — no game rules live here. Re-projects on every
  `{:table_updated, code}` broadcast.
  """

  use PokerscarsWeb, :live_view

  alias Pokerscars.Table

  @impl Phoenix.LiveView
  def mount(%{"code" => code}, session, socket) do
    if Table.exists?(code) do
      if connected?(socket), do: Table.subscribe(code)

      socket =
        socket
        |> assign(
          code: code,
          player_id: session["player_id"],
          sitting: nil,
          sizing?: false,
          raise_to: 0,
          all_in_armed?: false,
          ledger_open?: false
        )
        |> refresh()

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("mesa não encontrada"))
       |> push_navigate(to: ~p"/")}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:table_updated, _code}, socket), do: {:noreply, refresh(socket)}

  def handle_info({:table_closed, _code}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, gettext("a mesa foi encerrada"))
     |> push_navigate(to: ~p"/")}
  end

  @impl Phoenix.LiveView
  def handle_event("open_sit", %{"position" => position}, socket) do
    {:noreply, assign(socket, sitting: String.to_integer(position))}
  end

  def handle_event("cancel_sit", _params, socket), do: {:noreply, assign(socket, sitting: nil)}

  def handle_event("sit", _params, %{assigns: %{sitting: nil}} = socket), do: {:noreply, socket}

  def handle_event("sit", %{"nickname" => nickname, "amount" => amount}, socket) do
    %{code: code, player_id: player_id, sitting: position} = socket.assigns

    case Table.sit(code, player_id, String.trim(nickname), position, parse_reais(amount)) do
      :ok -> {:noreply, socket |> assign(sitting: nil) |> refresh()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("act", %{"action" => action}, socket) do
    %{code: code, player_id: player_id} = socket.assigns
    _result = Table.act(code, player_id, String.to_existing_atom(action))
    {:noreply, socket |> assign(sizing?: false, all_in_armed?: false) |> refresh()}
  end

  def handle_event("open_sizing", _params, socket) do
    case raise_bounds(socket) do
      {:raise_to, min, _max} -> {:noreply, assign(socket, sizing?: true, raise_to: min)}
      nil -> {:noreply, socket}
    end
  end

  def handle_event("close_sizing", _params, socket),
    do: {:noreply, assign(socket, sizing?: false, all_in_armed?: false)}

  def handle_event("set_raise", %{"value" => value}, socket) do
    {:noreply,
     assign(socket, raise_to: clamp(socket, String.to_integer(value)), all_in_armed?: false)}
  end

  def handle_event("preset", %{"kind" => kind}, socket) do
    case raise_bounds(socket) do
      nil ->
        {:noreply, socket}

      bounds ->
        {:noreply, assign(socket, raise_to: preset(socket, kind, bounds), all_in_armed?: false)}
    end
  end

  def handle_event("confirm_raise", _params, socket) do
    %{code: code, player_id: player_id, raise_to: raise_to} = socket.assigns

    case raise_bounds(socket) do
      {:raise_to, _min, max} when raise_to == max ->
        if socket.assigns.all_in_armed? do
          _result = Table.act(code, player_id, {:raise_to, raise_to})
          {:noreply, socket |> assign(sizing?: false, all_in_armed?: false) |> refresh()}
        else
          {:noreply, assign(socket, all_in_armed?: true)}
        end

      {:raise_to, _min, _max} ->
        _result = Table.act(code, player_id, {:raise_to, raise_to})
        {:noreply, socket |> assign(sizing?: false) |> refresh()}

      nil ->
        {:noreply, assign(socket, sizing?: false)}
    end
  end

  def handle_event("add_bot", _params, socket) do
    case Pokerscars.Bots.add(socket.assigns.code) do
      :ok ->
        {:noreply, refresh(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("não deu, tenta de novo"))}
    end
  end

  def handle_event("toggle_ledger", _params, socket),
    do: {:noreply, assign(socket, ledger_open?: not socket.assigns.ledger_open?)}

  def handle_event("rebuy", %{"amount" => amount}, socket) do
    %{code: code, player_id: player_id} = socket.assigns

    case Table.rebuy(code, player_id, parse_reais(amount)) do
      :ok -> {:noreply, refresh(socket)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("stand", _params, socket) do
    _result = Table.stand(socket.assigns.code, socket.assigns.player_id)
    {:noreply, socket |> assign(ledger_open?: false) |> refresh()}
  end

  defp refresh(socket) do
    case Table.view(socket.assigns.code, socket.assigns.player_id) do
      {:ok, view} ->
        hero = Enum.find(view.seats, & &1.hero?)

        socket
        |> assign(view: view, hero_position: (hero && hero.position) || 0, page_title: view.name)
        |> close_sizing_if_stale(view)

      {:error, :table_not_found} ->
        socket
        |> put_flash(:info, gettext("a mesa foi encerrada"))
        |> push_navigate(to: ~p"/")
    end
  end

  defp close_sizing_if_stale(socket, view) do
    if socket.assigns[:sizing?] && view.hero_actions == [] do
      assign(socket, sizing?: false, all_in_armed?: false)
    else
      socket
    end
  end

  defp raise_bounds(socket) do
    Enum.find(socket.assigns.view.hero_actions, &match?({:raise_to, _min, _max}, &1))
  end

  defp clamp(socket, value) do
    case raise_bounds(socket) do
      {:raise_to, min, max} -> value |> max(min) |> min(max)
      nil -> value
    end
  end

  # Pot-fraction raises: call first, then raise that fraction of the
  # resulting pot on top. All clamped to the legal bounds.
  defp preset(socket, kind, {:raise_to, min, max}) do
    view = socket.assigns.view
    hero = Enum.find(view.seats, & &1.hero?)
    owed = view.bet_to_match - ((hero && hero.committed) || 0)
    pot_after_call = view.pot + owed

    target =
      case kind do
        "half" -> view.bet_to_match + div(pot_after_call, 2)
        "two_thirds" -> view.bet_to_match + div(pot_after_call * 2, 3)
        "pot" -> view.bet_to_match + pot_after_call
        "all_in" -> max
      end

    target |> max(min) |> min(max)
  end

  defp parse_reais(input) do
    normalized = input |> String.trim() |> String.replace(".", "") |> String.replace(",", ".")

    case Float.parse(normalized) do
      {reais, _rest} -> round(reais * 100)
      :error -> 0
    end
  end

  defp error_message(:seat_taken), do: gettext("esse assento acabou de ser ocupado")
  defp error_message(:already_seated), do: gettext("você já está sentado nessa mesa")
  defp error_message(:invalid_buy_in), do: gettext("buy-in fora dos limites da mesa")
  defp error_message(:hand_in_progress), do: gettext("espera a mão acabar")
  defp error_message(_reason), do: gettext("não deu, tenta de novo")

  defp display_slot(position, hero_position), do: Integer.mod(position - hero_position, 9)

  defp victory(%{result: %{payouts: payouts, winners: winners}}) when winners != [] do
    line =
      winners
      |> Enum.map_join(" · ", fn %{nickname: nickname} ->
        gettext("%{name} leva %{amount}",
          name: nickname,
          amount: PokerscarsWeb.Money.chips(Map.get(payouts, nickname, 0))
        )
      end)

    detail =
      case winners do
        [%{category: category} | _rest] when category != nil ->
          gettext("com %{hand}", hand: hand_name(category))

        _no_showdown ->
          nil
      end

    %{line: line, detail: detail}
  end

  defp victory(_view), do: nil

  defp hand_name(:high_card), do: gettext("carta alta")
  defp hand_name(:pair), do: gettext("par")
  defp hand_name(:two_pair), do: gettext("dois pares")
  defp hand_name(:three_of_a_kind), do: gettext("trinca")
  defp hand_name(:straight), do: gettext("sequência")
  defp hand_name(:flush), do: gettext("flush")
  defp hand_name(:full_house), do: gettext("full house")
  defp hand_name(:four_of_a_kind), do: gettext("quadra")
  defp hand_name(:straight_flush), do: gettext("straight flush")

  defp status_line(view) do
    seated = Enum.count(view.seats, & &1.nickname)

    cond do
      view.phase != nil and view.phase != :complete ->
        acting = Enum.find(view.seats, & &1.to_act?)
        acting && gettext("vez de %{name}", name: acting.nickname)

      seated < 2 ->
        gettext("esperando mais gente sentar…")

      true ->
        gettext("próxima mão já vai começar")
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class={["pk-table-page", not hero?(@view) && "pk-spectating"]}>
        <div class="pk-table-head">
          <span class="pk-table-name">{@view.name}</span>
          <span class="pk-table-meta">
            {gettext("blinds")} {PokerscarsWeb.Money.chips(elem(@view.blinds, 0))} / {PokerscarsWeb.Money.chips(
              elem(@view.blinds, 1)
            )} · {gettext("código")} <strong class="pk-code">{@view.code}</strong>
          </span>
          <span :if={hero_nickname(@view)} class="pk-you">
            {gettext("você:")} <strong>{hero_nickname(@view)}</strong>
          </span>
          <button
            :if={Enum.any?(@view.seats, &(&1.nickname == nil))}
            class="pk-btn pk-btn--ghost pk-btn--slim"
            phx-click="add_bot"
          >
            {gettext("chamar bot")}
          </button>
          <button class="pk-btn pk-btn--ghost pk-btn--slim" phx-click="toggle_ledger">
            {gettext("caixa")}
          </button>
        </div>

        <.felt id="pk-felt">
          <%= for seat <- @view.seats do %>
            <.seat seat={seat} slot={display_slot(seat.position, @hero_position)} turn={@view.turn} />
            <.bet_chips seat={seat} slot={display_slot(seat.position, @hero_position)} />
          <% end %>
          <.board
            board={@view.board}
            pot={@view.pot}
            bet={@view.bet_to_match}
            victory={victory(@view)}
          />
        </.felt>

        <div class="pk-bar-zone">
          <div :if={@view.hero_hand} class="pk-hand-now">
            {gettext("tua mão")} · <strong>{hand_name(@view.hero_hand)}</strong>
          </div>
          <%= cond do %>
            <% @sizing? and raise_bounds(assigns_to_socket(assigns)) != nil -> %>
              <.sizing_panel
                bounds={raise_bounds(assigns_to_socket(assigns))}
                raise_to={@raise_to}
                all_in_armed?={@all_in_armed?}
              />
            <% @view.hero_actions != [] -> %>
              <.action_bar actions={@view.hero_actions} />
            <% not hero?(@view) -> %>
              <div class="pk-cta">
                <strong>{gettext("você está só assistindo")}</strong>
                {gettext("— toca num assento livre (\"sentar\") pra entrar no jogo")}
              </div>
            <% true -> %>
              <div class="pk-status">{status_line(@view)}</div>
          <% end %>
        </div>

        <div :if={@sitting} class="pk-modal-backdrop">
          <form class="pk-panel pk-modal" phx-submit="sit" phx-click-away="cancel_sit">
            <h2 class="pk-panel-title">{gettext("sentar na mesa")}</h2>
            <label class="pk-field">
              <span>{gettext("teu apelido")}</span>
              <input type="text" name="nickname" required maxlength="16" autofocus />
            </label>
            <label class="pk-field">
              <span>
                {gettext("buy-in (R$)")} · {gettext("mín")} {PokerscarsWeb.Money.chips(
                  buy_in_min(@view)
                )}
              </span>
              <input type="text" name="amount" inputmode="decimal" required placeholder="50,00" />
            </label>
            <div class="pk-modal-actions">
              <button type="button" class="pk-btn pk-btn--ghost" phx-click="cancel_sit">
                {gettext("voltar")}
              </button>
              <button type="submit" class="pk-btn pk-btn--raise">{gettext("sentar")}</button>
            </div>
          </form>
        </div>

        <div :if={@ledger_open?} class="pk-drawer">
          <div class="pk-drawer-head">
            <h2 class="pk-panel-title">{gettext("caixa da mesa")}</h2>
            <button class="pk-btn pk-btn--ghost pk-btn--slim" phx-click="toggle_ledger">✕</button>
          </div>
          <div class="pk-receipt">
            <div class="pk-receipt-head">
              {@view.name}
              <div class="pk-receipt-sub">
                {gettext("comanda da noite")} · {gettext("mesa")} {@view.code}
              </div>
            </div>
            <table class="pk-ledger">
              <thead>
                <tr>
                  <th>{gettext("quem")}</th>
                  <th>{gettext("comprou")}</th>
                  <th>{gettext("saldo")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @view.settlement}>
                  <td>{row.nickname}</td>
                  <td>{PokerscarsWeb.Money.chips(row.buy_in)}</td>
                  <td class={if row.result >= 0, do: "pk-pos", else: "pk-neg"}>
                    {PokerscarsWeb.Money.chips(row.result)}
                  </td>
                </tr>
              </tbody>
            </table>
            <p class="pk-receipt-note">
              {gettext("saldo = fichas na mesa + saques - compras.")}<br />
              {gettext("acerto por fora, no pix. valeu, volte sempre ★")}
            </p>
          </div>
          <form :if={hero?(@view)} class="pk-drawer-row" phx-submit="rebuy">
            <input type="text" name="amount" inputmode="decimal" placeholder="50,00" />
            <button type="submit" class="pk-btn pk-btn--call pk-btn--slim">{gettext("rebuy")}</button>
          </form>
          <button :if={hero?(@view)} class="pk-btn pk-btn--fold pk-btn--wide" phx-click="stand">
            {gettext("sair da mesa (saca as fichas)")}
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp hero?(view), do: Enum.any?(view.seats, & &1.hero?)

  defp hero_nickname(view), do: Enum.find_value(view.seats, &(&1.hero? && &1.nickname))

  defp buy_in_min(view), do: elem(view.blinds, 1) * 20

  # render/1 helpers take assigns; raise_bounds wants the socket shape.
  defp assigns_to_socket(assigns), do: %{assigns: assigns}
end
