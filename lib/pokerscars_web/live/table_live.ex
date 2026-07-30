defmodule PokerscarsWeb.TableLive do
  @moduledoc """
  The table screen. Renders the player's `Table.View` projection verbatim and
  forwards commands — no game rules live here. Re-projects on every
  `{:table_updated, code}` broadcast.
  """

  use PokerscarsWeb, :live_view

  alias Pokerscars.Table

  @impl Phoenix.LiveView
  def mount(%{"code" => code} = params, session, socket) do
    cond do
      not Table.exists?(code) ->
        {:ok,
         socket
         |> put_flash(:error, gettext("mesa não encontrada"))
         |> push_navigate(to: ~p"/")}

      Table.locked?(code) and not PokerscarsWeb.TableAccess.valid?(params["key"], code) ->
        # No subscription, no projection: the room stays dark until unlocked.
        {:ok,
         assign(socket,
           code: code,
           locked_gate?: true,
           player_id: session["player_id"],
           page_title: gettext("sala trancada")
         )}

      true ->
        if connected?(socket), do: Table.subscribe(code)

        socket =
          socket
          |> assign(
            code: code,
            locked_gate?: false,
            access_key: params["key"],
            player_id: session["player_id"],
            sitting: nil,
            sizing?: false,
            raise_to: 0,
            all_in_armed?: false,
            panel: nil
          )
          |> refresh()

        {:ok, socket}
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

  def handle_event("preset_raise", %{"amount" => amount}, socket) do
    %{code: code, player_id: player_id} = socket.assigns
    _result = Table.act(code, player_id, {:raise_to, clamp(socket, String.to_integer(amount))})
    {:noreply, socket |> assign(sizing?: false, all_in_armed?: false) |> refresh()}
  end

  def handle_event("arm_all_in", _params, socket),
    do: {:noreply, assign(socket, all_in_armed?: true)}

  def handle_event("muck", _params, socket) do
    _result = Table.muck(socket.assigns.code, socket.assigns.player_id)
    {:noreply, refresh(socket)}
  end

  def handle_event("add_bot", _params, socket) do
    case Pokerscars.Bots.add(socket.assigns.code, requester: socket.assigns.player_id) do
      :ok ->
        {:noreply, refresh(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("não deu, tenta de novo"))}
    end
  end

  def handle_event("toggle_ledger", _params, socket),
    do: {:noreply, assign(socket, panel: if(socket.assigns.panel, do: nil, else: :cash))}

  @panels %{"config" => :config, "cash" => :cash, "log" => :log}

  def handle_event("panel", %{"tab" => tab}, socket),
    do: {:noreply, assign(socket, panel: Map.fetch!(@panels, tab))}

  def handle_event("share", _params, socket) do
    path =
      case socket.assigns[:access_key] do
        nil ->
          "/t/#{socket.assigns.code}"

        _key ->
          "/t/#{socket.assigns.code}?key=#{PokerscarsWeb.TableAccess.sign(socket.assigns.code)}"
      end

    {:noreply,
     socket
     |> push_event("copy", %{path: path})
     |> put_flash(:info, gettext("link copiado"))}
  end

  def handle_event("unlock", %{"password" => password}, socket) do
    %{code: code} = socket.assigns

    if Table.check_password(code, password) do
      key = PokerscarsWeb.TableAccess.sign(code)
      {:noreply, push_navigate(socket, to: ~p"/t/#{code}?key=#{key}")}
    else
      {:noreply, put_flash(socket, :error, gettext("senha errada"))}
    end
  end

  def handle_event("rebuy", %{"amount" => amount}, socket) do
    %{code: code, player_id: player_id} = socket.assigns

    case Table.rebuy(code, player_id, parse_reais(amount)) do
      :ok -> {:noreply, refresh(socket)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("stand", _params, socket) do
    _result = Table.stand(socket.assigns.code, socket.assigns.player_id)
    socket = refresh(socket)

    if socket.assigns.view.hero_leaving? do
      {:noreply, put_flash(socket, :info, gettext("você sai quando a mão acabar"))}
    else
      {:noreply, assign(socket, panel: nil)}
    end
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

  # Pot-fraction raises for the always-visible preset chips: call first,
  # then raise that fraction of the resulting pot on top, clamped to bounds.
  defp raise_presets(view) do
    case Enum.find(view.hero_actions, &match?({:raise_to, _min, _max}, &1)) do
      nil ->
        []

      {:raise_to, min, max} ->
        hero = Enum.find(view.seats, & &1.hero?)
        owed = view.bet_to_match - ((hero && hero.committed) || 0)
        pot_after_call = view.pot + owed

        fractions = [
          {"1/2", view.bet_to_match + div(pot_after_call, 2)},
          {"2/3", view.bet_to_match + div(pot_after_call * 2, 3)},
          {gettext("pote"), view.bet_to_match + pot_after_call}
        ]

        chips =
          for {label, target} <- fractions,
              amount = target |> max(min) |> min(max),
              amount < max,
              uniq: true,
              do: {label, amount, false}

        chips ++ [{gettext("all-in"), max, true}]
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
  defp error_message(:invalid_buy_in), do: gettext("valor fora dos limites da mesa")
  defp error_message(:hand_in_progress), do: gettext("espera a mão acabar")
  defp error_message(_reason), do: gettext("não deu, tenta de novo")

  defp display_slot(position, hero_position), do: Integer.mod(position - hero_position, 9)

  defp victory(%{result: %{winners: winners, pots: pots}}, currency) when winners != [] do
    labels = pot_labels(length(pots))

    line =
      pots
      |> Enum.zip(labels)
      |> Enum.map_join(" · ", fn {pot, label} -> pot_line(pot, label, currency) end)

    detail =
      case winners do
        [%{category: category} | _rest] when category != nil ->
          gettext("com %{hand}", hand: hand_name(category))

        _no_showdown ->
          nil
      end

    %{line: line, detail: detail}
  end

  defp victory(_view, _currency), do: nil

  defp pot_labels(1), do: [nil]

  defp pot_labels(count),
    do: [gettext("pote principal") | List.duplicate(gettext("pote lateral"), count - 1)]

  defp pot_line(%{winners: [winner], amount: amount}, nil, currency),
    do: gettext("%{name} leva %{amount}", name: winner, amount: money(amount, currency))

  defp pot_line(%{winners: [winner], amount: amount}, label, currency),
    do:
      gettext("%{name} leva o %{pot} (%{amount})",
        name: winner,
        pot: label,
        amount: money(amount, currency)
      )

  defp pot_line(%{winners: winners, amount: amount}, label, currency) do
    gettext("%{names} dividem o %{pot} (%{amount})",
      names: Enum.join(winners, " + "),
      pot: label || gettext("pote"),
      amount: money(amount, currency)
    )
  end

  defp money(cents, currency), do: PokerscarsWeb.Money.chips(cents, currency)

  defp status_line(view) do
    seated = Enum.count(view.seats, & &1.nickname)

    cond do
      view.phase != nil and view.phase != :complete ->
        acting = Enum.find(view.seats, & &1.to_act?)
        acting && gettext("vez de %{name}", name: acting.nickname)

      seated < 2 ->
        gettext("esperando mais gente sentar")

      true ->
        gettext("próxima mão já vai começar")
    end
  end

  defp waiting?(view), do: view.phase == nil or view.phase == :complete

  # Table settings: same content on the desktop side card and the mobile drawer.
  defp table_config(assigns) do
    ~H"""
    <div class="pk-config">
      <div class="pk-side-rows">
        <div class="pk-side-row">
          <span>{gettext("blinds")}</span>
          <strong>
            {PokerscarsWeb.Money.chips(elem(@view.blinds, 0), @currency)} / {PokerscarsWeb.Money.chips(
              elem(@view.blinds, 1),
              @currency
            )}
          </strong>
        </div>
        <div class="pk-side-row">
          <span>{gettext("tempo de ação")}</span>
          <strong>{div(@view.clock_ms, 1000)}s</strong>
        </div>
        <div class="pk-side-row">
          <span>{gettext("buy-in")}</span>
          <strong>
            {PokerscarsWeb.Money.chips(@view.buy_in.min, @currency)} – {PokerscarsWeb.Money.chips(
              @view.buy_in.max,
              @currency
            )}
          </strong>
        </div>
        <div class="pk-side-row">
          <span>{gettext("código")}</span>
          <strong class="pk-code">{@view.code}</strong>
        </div>
      </div>
      <button class="pk-btn pk-btn--call pk-btn--wide pk-btn--slim" phx-click="share">
        {gettext("copiar link da mesa")}
      </button>
      <button
        :if={@view.creator? and free_seat?(@view)}
        class="pk-btn pk-btn--ghost pk-btn--wide pk-btn--slim"
        phx-click="add_bot"
      >
        {gettext("chamar bot")}
      </button>
    </div>
    """
  end

  # The table's diary, newest first. Hand markers act as section headers;
  # each event type carries its own color so the eye can scan for what matters.
  defp event_log(assigns) do
    ~H"""
    <ol class="pk-events" id="pk-events">
      <li :if={@view.events == []} class="pk-ev pk-ev--empty">{gettext("nada ainda")}</li>
      <li
        :for={event <- grouped_events(@view.events)}
        :key={event.id}
        id={"pk-ev-#{event.id}"}
        class={["pk-ev", "pk-ev--#{event_kind(event)}"]}
      >
        {event_text(event, @currency)}
      </li>
    </ol>
    """
  end

  # In the newest-first stream a hand's marker trails its own events. Lift
  # each marker above them so the log reads as sections, the running hand
  # headed at the top and each winner right under their hand's header.
  defp grouped_events(events) do
    {groups, rest} =
      Enum.reduce(events, {[], []}, fn
        %{type: :hand_started} = marker, {groups, buffer} ->
          {[[marker | Enum.reverse(buffer)] | groups], []}

        event, {groups, buffer} ->
          {groups, [event | buffer]}
      end)

    [Enum.reverse(rest) | groups] |> Enum.reverse() |> List.flatten()
  end

  defp event_kind(%{type: :action, data: %{action: kind}}), do: kind
  defp event_kind(%{type: type}), do: type

  defp event_text(%{type: :hand_started, data: data}, _currency),
    do: gettext("mão #%{n}", n: data.hand_no)

  defp event_text(%{type: :sit, data: data}, currency),
    do:
      gettext("%{name} sentou com %{amount}",
        name: data.nickname,
        amount: money(data.amount, currency)
      )

  defp event_text(%{type: :rebuy, data: data}, currency),
    do:
      gettext("%{name} recomprou %{amount}",
        name: data.nickname,
        amount: money(data.amount, currency)
      )

  defp event_text(%{type: :stand, data: data}, currency),
    do:
      gettext("%{name} saiu com %{amount}",
        name: data.nickname,
        amount: money(data.amount, currency)
      )

  defp event_text(%{type: :won, data: data}, currency),
    do:
      gettext("%{name} leva %{amount}", name: data.nickname, amount: money(data.amount, currency))

  defp event_text(%{type: :action, data: %{action: :fold} = data}, _currency),
    do: auto_tag(gettext("%{name} desistiu", name: data.nickname), data)

  defp event_text(%{type: :action, data: %{action: :check} = data}, _currency),
    do: auto_tag(gettext("%{name} passou", name: data.nickname), data)

  defp event_text(%{type: :action, data: %{action: :call} = data}, currency),
    do:
      auto_tag(
        gettext("%{name} pagou %{amount}",
          name: data.nickname,
          amount: money(data.amount, currency)
        ),
        data
      )

  defp event_text(%{type: :action, data: %{action: :raise} = data}, currency),
    do:
      auto_tag(
        gettext("%{name} aumentou para %{amount}",
          name: data.nickname,
          amount: money(data.amount, currency)
        ),
        data
      )

  defp auto_tag(text, %{auto?: true}), do: text <> " · " <> gettext("tempo esgotado")
  defp auto_tag(text, _data), do: text

  defp free_seat?(view), do: Enum.any?(view.seats, &(&1.nickname == nil))

  # The cashier: same content on the desktop side card and the mobile drawer.
  # The receipt doubles as the live ranking: settlement comes sorted by
  # balance and keeps everyone who ever bought in, seated or gone.
  defp cashier(assigns) do
    ~H"""
    <div class="pk-cashier">
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
              <td>{PokerscarsWeb.Money.chips(row.buy_in, @currency)}</td>
              <td class={if row.result >= 0, do: "pk-pos", else: "pk-neg"}>
                {PokerscarsWeb.Money.chips(row.result, @currency)}
              </td>
            </tr>
          </tbody>
        </table>
        <p class="pk-receipt-note">
          {gettext("saldo = fichas na mesa + saques - compras.")}<br />
          {gettext("fichas sem valor real. valeu, volte sempre ★")}
        </p>
      </div>

      <div :if={hero?(@view)} class="pk-cashier-actions">
        <form class="pk-drawer-row" phx-submit="rebuy">
          <input
            type="text"
            name="amount"
            inputmode="decimal"
            required
            value={PokerscarsWeb.Money.chips(elem(@view.blinds, 1) * 100, @currency)}
          />
          <button type="submit" class="pk-btn pk-btn--call pk-btn--slim">{gettext("rebuy")}</button>
        </form>
        <p class="pk-cashier-hint">
          {gettext("rebuy: mín %{min} · máx %{max}",
            min: PokerscarsWeb.Money.chips(@view.buy_in.min, @currency),
            max: PokerscarsWeb.Money.chips(@view.buy_in.max, @currency)
          )}
        </p>
        <button
          :if={not @view.hero_leaving?}
          class="pk-btn pk-btn--fold pk-btn--wide"
          phx-click="stand"
        >
          {gettext("sair e sacar %{amount}",
            amount: PokerscarsWeb.Money.chips(hero_stack(@view), @currency)
          )}
        </button>
        <p :if={@view.hero_leaving?} class="pk-cashier-hint pk-cashier-hint--leaving">
          {gettext("você sai quando a mão acabar")}
        </p>
        <p class="pk-cashier-hint">
          {gettext("← lobby só troca de tela; teu lugar e tuas fichas ficam.")}
        </p>
      </div>
    </div>
    """
  end

  # Pot-to-winner chip flights: one wave per pot, main pot first, each
  # keyed by hand so the animation runs exactly once.
  defp chip_flights_for(%{result: %{pots: pots}, hand_no: hand_no} = view, hero_position)
       when pots != [] do
    for {pot, pot_index} <- Enum.with_index(pots),
        winner <- pot.winners,
        seat = Enum.find(view.seats, &(&1.nickname == winner)),
        seat != nil do
      %{
        id: "flight-#{hand_no}-#{pot_index}-#{seat.position}",
        slot: display_slot(seat.position, hero_position),
        delay_ms: pot_index * 600
      }
    end
  end

  defp chip_flights_for(_view, _hero_position), do: []

  defp hero_stack(view) do
    hero = Enum.find(view.seats, & &1.hero?)
    (hero && hero.stack) || 0
  end

  @impl Phoenix.LiveView
  def render(%{locked_gate?: true} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} locale={@locale} currency={@currency}>
      <div class="pk-lobby">
        <form class="pk-panel pk-modal pk-gate" phx-submit="unlock">
          <h2 class="pk-panel-title">
            <.icon name="hero-lock-closed" class="size-4 pk-lock" /> {gettext("sala trancada")}
          </h2>
          <p class="pk-gate-hint">
            {gettext("pede a senha (ou o link) pra quem criou a mesa")}
          </p>
          <label class="pk-field">
            <span>{gettext("senha da sala")}</span>
            <input type="password" name="password" required autocomplete="off" autofocus />
          </label>
          <button type="submit" class="pk-btn pk-btn--raise pk-btn--wide">{gettext("entrar")}</button>
          <.link navigate={~p"/"} class="pk-btn pk-btn--ghost pk-btn--wide pk-btn--slim">
            ← {gettext("lobby")}
          </.link>
        </form>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} locale={@locale} currency={@currency}>
      <div class={["pk-table-page", not hero?(@view) && "pk-spectating"]}>
        <div class="pk-table-head">
          <.link navigate={~p"/"} class="pk-btn pk-btn--ghost pk-btn--slim">
            ← {gettext("lobby")}
          </.link>
          <span class="pk-table-name pk-mobile-only">{@view.name}</span>
          <span class="pk-head-spacer"></span>
          <button
            :if={@view.creator? and free_seat?(@view)}
            class="pk-btn pk-btn--ghost pk-btn--slim pk-mobile-only"
            phx-click="add_bot"
            aria-label={gettext("chamar bot")}
          >
            <.icon name="hero-user-plus" class="size-4" />
          </button>
          <button
            class="pk-btn pk-btn--ghost pk-btn--slim pk-mobile-only"
            phx-click="toggle_ledger"
            aria-label={gettext("menu da mesa")}
          >
            <.icon name="hero-ellipsis-vertical" class="size-4" />
          </button>
        </div>

        <div class="pk-table-layout">
          <div class="pk-side-stack">
            <aside class="pk-side pk-side--info">
              <h2 class="pk-side-title">{@view.name}</h2>
              {table_config(assigns)}
            </aside>
            <aside class="pk-side pk-side--log">
              <h2 class="pk-side-title">{gettext("eventos")}</h2>
              {event_log(assigns)}
            </aside>
          </div>

          <div class="pk-felt-column">
            <.felt id="pk-felt">
              <.seat
                :for={seat <- @view.seats}
                :key={seat.position}
                seat={seat}
                slot={display_slot(seat.position, @hero_position)}
                turn={@view.turn}
                currency={@currency}
                can_sit?={not hero?(@view)}
                waiting?={waiting?(@view)}
              />
              <.board
                board={@view.board}
                pot={@view.pot}
                pots={@view.pots}
                bet={@view.bet_to_match}
                victory={victory(@view, @currency)}
                currency={@currency}
              />
              <.chip_flights flights={chip_flights_for(@view, @hero_position)} />
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
                    currency={@currency}
                  />
                <% @view.hero_actions != [] -> %>
                  <.action_bar
                    actions={@view.hero_actions}
                    presets={raise_presets(@view)}
                    all_in_armed?={@all_in_armed?}
                    currency={@currency}
                  />
                <% can_muck?(@view) -> %>
                  <div class="pk-status-stack">
                    <div class="pk-status">{status_line(@view)}</div>
                    <button class="pk-btn pk-btn--ghost pk-btn--slim" phx-click="muck">
                      {gettext("esconder cartas")}
                    </button>
                  </div>
                <% not hero?(@view) -> %>
                  <div class="pk-cta">
                    <strong>{gettext("você está só assistindo")}</strong>
                    {gettext("toca num assento livre pra entrar no jogo")}
                  </div>
                <% true -> %>
                  <div class="pk-status">{status_line(@view)}</div>
              <% end %>
            </div>
          </div>

          <aside class="pk-side pk-side--cash">
            <h2 class="pk-side-title">{gettext("caixa da mesa")}</h2>
            {cashier(assigns)}
          </aside>
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
                {gettext("buy-in")} ({PokerscarsWeb.Money.symbol(@currency)}) · {gettext("mín")} {PokerscarsWeb.Money.chips(
                  buy_in_min(@view)
                )}
              </span>
              <input
                type="text"
                name="amount"
                inputmode="decimal"
                required
                value={PokerscarsWeb.Money.chips(elem(@view.blinds, 1) * 100)}
              />
            </label>
            <div class="pk-modal-actions">
              <button type="button" class="pk-btn pk-btn--ghost" phx-click="cancel_sit">
                {gettext("voltar")}
              </button>
              <button type="submit" class="pk-btn pk-btn--raise">{gettext("sentar")}</button>
            </div>
          </form>
        </div>

        <div :if={@panel} class="pk-drawer">
          <div class="pk-drawer-head">
            <div class="pk-tabs">
              <button
                class={["pk-tab", @panel == :config && "pk-tab--active"]}
                phx-click="panel"
                phx-value-tab="config"
              >
                {gettext("mesa")}
              </button>
              <button
                class={["pk-tab", @panel == :cash && "pk-tab--active"]}
                phx-click="panel"
                phx-value-tab="cash"
              >
                {gettext("caixa")}
              </button>
              <button
                class={["pk-tab", @panel == :log && "pk-tab--active"]}
                phx-click="panel"
                phx-value-tab="log"
              >
                {gettext("eventos")}
              </button>
            </div>
            <button class="pk-btn pk-btn--ghost pk-btn--slim" phx-click="toggle_ledger">✕</button>
          </div>
          <%= case @panel do %>
            <% :config -> %>
              {table_config(assigns)}
            <% :log -> %>
              {event_log(assigns)}
            <% _cash -> %>
              {cashier(assigns)}
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp hero?(view), do: Enum.any?(view.seats, & &1.hero?)

  # Losers at showdown may hide their revealed cards during the pause.
  defp can_muck?(%{result: %{reason: :showdown}} = view) do
    hero = Enum.find(view.seats, & &1.hero?)
    hero != nil and hero.hand_label != nil and not hero.winner? and not hero.mucked?
  end

  defp can_muck?(_view), do: false

  defp buy_in_min(view), do: elem(view.blinds, 1) * 20

  # render/1 helpers take assigns; raise_bounds wants the socket shape.
  defp assigns_to_socket(assigns), do: %{assigns: assigns}
end
