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
           page_title: gettext("sala trancada · pokerscars")
         )}

      true ->
        _presence =
          if connected?(socket) do
            :ok = Table.subscribe(code)
            # Presence: the table monitors this socket; when a player's last
            # socket dies the seat dims and the grace clock starts.
            Table.attach(code, session["player_id"])
          end

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
            panel: nil,
            rail: :cash,
            chat_seen_id: -1,
            confirm_stand?: false,
            config_panel: :settings
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

  def handle_event("config_panel", %{"panel" => panel}, socket) do
    panel = if panel == "info", do: :info, else: :settings
    {:noreply, assign(socket, config_panel: panel)}
  end

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

  def handle_event("show", _params, socket) do
    _result = Table.show(socket.assigns.code, socket.assigns.player_id)
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

  @panels %{"config" => :config, "cash" => :cash, "log" => :log, "chat" => :chat}

  def handle_event("panel", %{"tab" => tab}, socket),
    do: {:noreply, socket |> assign(panel: Map.fetch!(@panels, tab)) |> mark_chat_seen()}

  @rails %{"cash" => :cash, "log" => :log, "chat" => :chat}

  def handle_event("rail", %{"tab" => tab}, socket),
    do: {:noreply, socket |> assign(rail: Map.fetch!(@rails, tab)) |> mark_chat_seen()}

  def handle_event("chat_preset", %{"key" => key}, socket) do
    payload = {:preset, String.to_existing_atom(key)}
    send_chat(socket, payload)
  end

  def handle_event("chat_text", %{"text" => text}, socket) do
    case send_chat(socket, {:text, text}) do
      {:noreply, socket} -> {:noreply, push_event(socket, "chat-sent", %{})}
    end
  end

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
    cents = parse_reais(amount)

    case Table.rebuy(code, player_id, cents) do
      :ok ->
        socket = refresh(socket)
        {:noreply, put_flash(socket, :info, rebuy_message(socket, cents))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("confirm_stand", _params, socket),
    do: {:noreply, assign(socket, confirm_stand?: true)}

  def handle_event("cancel_stand", _params, socket),
    do: {:noreply, assign(socket, confirm_stand?: false)}

  def handle_event("stand", _params, socket) do
    _result = Table.stand(socket.assigns.code, socket.assigns.player_id)
    socket = socket |> assign(confirm_stand?: false) |> refresh()

    if socket.assigns.view.hero_leaving? do
      {:noreply, put_flash(socket, :info, gettext("você sai quando a mão acabar"))}
    else
      {:noreply, assign(socket, panel: nil)}
    end
  end

  defp mark_chat_seen(socket) do
    open? = socket.assigns[:rail] == :chat or socket.assigns[:panel] == :chat

    case {open?, socket.assigns.view.chat} do
      {true, [latest | _rest]} -> assign(socket, chat_seen_id: latest.id)
      _closed_or_empty -> socket
    end
  end

  defp chat_dot?(view, rail, seen_id) do
    case view.chat do
      [latest | _rest] -> rail != :chat and latest.id > seen_id
      [] -> false
    end
  end

  defp send_chat(socket, payload) do
    case Table.chat(socket.assigns.code, socket.assigns.player_id, payload) do
      :ok ->
        {:noreply, refresh(socket)}

      {:error, :throttled} ->
        {:noreply, put_flash(socket, :error, gettext("calma aí, uma mensagem por vez"))}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  defp rebuy_message(socket, cents) do
    amount = money(cents, socket.assigns.currency)

    if socket.assigns.view.phase in [nil, :complete] do
      gettext("rebuy de %{amount} feito", amount: amount)
    else
      gettext("rebuy de %{amount} entra quando a mão acabar", amount: amount)
    end
  end

  defp refresh(socket) do
    case Table.view(socket.assigns.code, socket.assigns.player_id) do
      {:ok, view} ->
        hero = Enum.find(view.seats, & &1.hero?)

        socket
        |> maybe_sound(socket.assigns[:view], view)
        |> assign(
          view: view,
          hero_position: (hero && hero.position) || 0,
          page_title: "#{view.name} · pokerscars",
          og_desc: og_desc(view)
        )
        |> mark_chat_seen()
        |> close_sizing_if_stale(view)

      {:error, :table_not_found} ->
        socket
        |> put_flash(:info, gettext("a mesa foi encerrada"))
        |> push_navigate(to: ~p"/")
    end
  end

  # What a pasted table link says about itself: the game, the stakes and
  # whether there is still a seat.
  defp og_desc(view) do
    {small, big} = view.blinds
    free = Enum.count(view.seats, &(&1.nickname == nil))
    blinds = "#{PokerscarsWeb.Money.chips(small)} / #{PokerscarsWeb.Money.chips(big)}"

    gettext("mesa de poker entre amigos · blinds %{blinds} · %{seats}",
      blinds: blinds,
      seats: ngettext("%{count} vaga aberta", "%{count} vagas abertas", free)
    )
  end

  # The server decides when a cue happens by diffing consecutive
  # projections; the client decides whether to play it (user prefs).
  defp maybe_sound(socket, nil, _new_view), do: socket

  defp maybe_sound(socket, old_view, new_view) do
    [action_sound(old_view, new_view), sound_for(old_view, new_view)]
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(socket, &push_event(&2, "sound", %{kind: &1}))
  end

  # Somebody just made a move worth hearing: an all-in beats a raise.
  defp action_sound(old_view, new_view) do
    same_round? = old_view.hand_no == new_view.hand_no and old_view.phase == new_view.phase

    cond do
      same_round? and all_in_appeared?(old_view, new_view) -> "all_in"
      same_round? and new_view.bet_to_match > old_view.bet_to_match -> "raise"
      true -> nil
    end
  end

  defp all_in_appeared?(old_view, new_view) do
    before =
      for seat <- old_view.seats, seat.state == :all_in, into: MapSet.new(), do: seat.position

    Enum.any?(
      new_view.seats,
      &(&1.state == :all_in and not MapSet.member?(before, &1.position))
    )
  end

  defp sound_for(old_view, new_view) do
    hero = Enum.find(new_view.seats, & &1.hero?)

    cond do
      turn_reached_hero?(old_view, new_view, hero) -> "turn"
      hand_ended?(old_view, new_view) and hero != nil and hero.winner? -> "win"
      hand_ended?(old_view, new_view) -> "end"
      true -> nil
    end
  end

  defp hand_ended?(old_view, new_view),
    do: new_view.phase == :complete and old_view.phase != :complete

  defp turn_reached_hero?(_old_view, _new_view, nil), do: false

  defp turn_reached_hero?(old_view, new_view, hero) do
    new_view.turn != nil and new_view.turn.position == hero.position and
      (old_view.turn == nil or old_view.turn.position != hero.position)
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
  defp error_message(:name_not_allowed), do: gettext("esse nome não rola aqui, escolhe outro")
  defp error_message(_reason), do: gettext("não deu, tenta de novo")

  defp display_slot(position, hero_position), do: Integer.mod(position - hero_position, 9)

  # One clause per winning crew, their pots summed: "rita leva 250,00", not
  # a sentence per side pot repeating the same name across the felt.
  defp victory(%{result: %{winners: winners, pots: pots}}, currency) when winners != [] do
    line =
      pots
      |> Enum.group_by(& &1.winners)
      |> Enum.map(fn {names, group} -> {names, group |> Enum.map(& &1.amount) |> Enum.sum()} end)
      |> Enum.sort_by(fn {_names, amount} -> -amount end)
      |> Enum.map_join(" · ", &victory_share(&1, currency))

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

  defp victory_share({[name], amount}, currency),
    do: gettext("%{name} leva %{amount}", name: name, amount: money(amount, currency))

  defp victory_share({names, amount}, currency),
    do:
      gettext("%{names} dividem %{amount}",
        names: Enum.join(names, " + "),
        amount: money(amount, currency)
      )

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
  # `where` keeps hook ids unique; only the side instance plays sounds.
  attr :view, Pokerscars.Table.View, required: true
  attr :currency, :string, required: true
  attr :where, :string, required: true
  attr :config_panel, :atom, required: true

  defp table_config(assigns) do
    ~H"""
    <div class="pk-config">
      <div class="pk-config-switch" role="tablist">
        <button
          class={["pk-config-icon", @config_panel == :settings && "pk-config-icon--on"]}
          phx-click="config_panel"
          phx-value-panel="settings"
          role="tab"
          aria-label={gettext("ajustes da mesa")}
          title={gettext("ajustes da mesa")}
        >
          <.icon name="hero-wrench-screwdriver" class="size-4" />
        </button>
        <button
          class={["pk-config-icon", @config_panel == :info && "pk-config-icon--on"]}
          phx-click="config_panel"
          phx-value-panel="info"
          role="tab"
          aria-label={gettext("informações da mesa")}
          title={gettext("informações da mesa")}
        >
          <.icon name="hero-information-circle" class="size-4" />
        </button>
      </div>
      <%= if @config_panel == :settings do %>
        <.table_settings view={@view} where={@where} />
      <% else %>
        <.table_info view={@view} currency={@currency} />
      <% end %>
    </div>
    """
  end

  # Settings: sound/voice prefs under a wrench icon.
  attr :view, Pokerscars.Table.View, required: true
  attr :where, :string, required: true

  defp table_settings(assigns) do
    ~H"""
    <div
      id={"pk-sounds-#{@where}"}
      phx-hook="Sounds"
      phx-update="ignore"
      data-primary={@where == "side" || nil}
      class="pk-sound-prefs"
    >
      <label class="pk-sound-master">
        <span class="pk-sound-title">{gettext("sons")}</span>
        <input type="checkbox" data-sound-pref="enabled" />
      </label>
      <label class="pk-sound-opt">
        <input type="checkbox" data-sound-pref="turn" />
        <span>{gettext("sua vez")}</span>
      </label>
      <label class="pk-sound-opt">
        <input type="checkbox" data-sound-pref="win" />
        <span>{gettext("vitória")}</span>
      </label>
      <label class="pk-sound-opt">
        <input type="checkbox" data-sound-pref="end" />
        <span>{gettext("fim da mão")}</span>
      </label>
      <label class="pk-sound-opt">
        <input type="checkbox" data-sound-pref="raise" />
        <span>{gettext("aumento")}</span>
      </label>
      <label class="pk-sound-opt">
        <input type="checkbox" data-sound-pref="all_in" />
        <span>{gettext("all-in")}</span>
      </label>
    </div>
    """
  end

  # Info: the room's stats and actions under an info icon.
  attr :view, Pokerscars.Table.View, required: true
  attr :currency, :string, required: true

  defp table_info(assigns) do
    ~H"""
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
        <span>{gettext("vagas")}</span>
        <strong class={(free_seat?(@view) && "pk-vagas--open") || "pk-vagas--full"}>
          {gettext("%{free} de 9", free: free_count(@view))}
        </strong>
      </div>
      <div class="pk-side-row">
        <span>{gettext("código")}</span>
        <strong class="pk-code">{@view.code}</strong>
      </div>
      <div class="pk-side-row">
        <span>{gettext("aberta")}</span>
        <strong>{PokerscarsWeb.Age.since(@view.created_at)}</strong>
      </div>
      <div class="pk-side-row">
        <span>{gettext("tempo de jogo")}</span>
        <strong>{PokerscarsWeb.Age.play(@view.played_ms)}</strong>
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

  defp free_seat?(view), do: free_count(view) > 0
  defp free_count(view), do: Enum.count(view.seats, &(&1.nickname == nil))

  # The chat panel: newest at the bottom via column-reverse, presets as a
  # tap row, free text only in locked rooms. `where` keeps DOM ids unique
  # between the desktop card and the drawer.
  attr :view, Pokerscars.Table.View, required: true
  attr :where, :string, required: true

  defp chat_panel(assigns) do
    ~H"""
    <div class="pk-chat">
      <ol class="pk-chat-log" id={"pk-chat-log-#{@where}"}>
        <li :if={@view.chat == []} class="pk-chat-empty">{gettext("ninguém falou nada ainda")}</li>
        <li
          :for={message <- @view.chat}
          :key={message.id}
          id={"pk-chat-#{@where}-#{message.id}"}
          class="pk-chat-msg"
        >
          <strong>{message.nickname}</strong> {chat_body(message.payload)}
        </li>
      </ol>
      <div :if={hero?(@view)} class="pk-chat-presets">
        <button
          :for={key <- Pokerscars.Table.Chat.presets()}
          class="pk-chip"
          phx-click="chat_preset"
          phx-value-key={key}
        >
          {chat_phrase(key)}
        </button>
      </div>
      <form
        :if={hero?(@view) and @view.locked?}
        class="pk-chat-form"
        phx-submit="chat_text"
        id={"pk-chat-form-#{@where}"}
      >
        <input name="text" maxlength="200" autocomplete="off" placeholder={gettext("fala aí")} />
        <button type="submit" class="pk-btn pk-btn--call pk-btn--slim">{gettext("enviar")}</button>
      </form>
    </div>
    """
  end

  defp chat_body({:preset, key}), do: chat_phrase(key)
  defp chat_body({:text, text}), do: text

  defp chat_phrase(:nice_hand), do: gettext("boa mão!")
  defp chat_phrase(:kkkk), do: "kkkkk"
  defp chat_phrase(:bluff), do: gettext("blefou né")
  defp chat_phrase(:gg), do: "gg"
  defp chat_phrase(:hurry), do: gettext("vai logo")
  defp chat_phrase(:pay_to_see), do: gettext("pago pra ver")
  defp chat_phrase(:that_hurt), do: gettext("essa doeu")
  defp chat_phrase(:respect), do: gettext("respeita")
  defp chat_phrase(:good_evening), do: gettext("boa noite pessoal")
  defp chat_phrase(:wow), do: "uia"
  defp chat_phrase(:clap), do: "👏"
  defp chat_phrase(:fire), do: "🔥"
  defp chat_phrase(:handshake), do: "🤝"

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
        <div class="pk-ledger-scroll">
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
        </div>
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
          phx-click="confirm_stand"
        >
          {gettext("sair e sacar %{amount}",
            amount: PokerscarsWeb.Money.chips(hero_stack(@view), @currency)
          )}
        </button>
        <p :if={@view.hero_leaving?} class="pk-cashier-hint pk-cashier-hint--leaving">
          {gettext("você sai quando a mão acabar")}
        </p>
        <p class="pk-cashier-hint">
          {gettext("← lobby só troca de tela; seu lugar e suas fichas ficam.")}
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
            phx-click="panel"
            phx-value-tab="chat"
            aria-label={gettext("chat da mesa")}
          >
            <.icon name="hero-chat-bubble-left-ellipsis" class="size-4" />
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
              <.table_config
                view={@view}
                currency={@currency}
                where="side"
                config_panel={@config_panel}
              />
            </aside>
          </div>

          <div class="pk-felt-column">
            <%!-- Stable slot: the per-message child churns inside it, never
                  as a felt sibling (sibling churn re-renders the cards). --%>
            <div class="pk-chat-ticker-slot pk-mobile-only" aria-live="polite">
              <div
                :if={ticker = List.first(@view.chat)}
                id={"pk-ticker-#{ticker.id}"}
                class="pk-chat-ticker"
              >
                <strong>{ticker.nickname}</strong> {chat_body(ticker.payload)}
              </div>
            </div>
            <.felt id="pk-felt" phx-hook="Intro">
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
                {gettext("sua mão")} · <strong>{hand_name(@view.hero_hand)}</strong>
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
                <% can_show?(@view) -> %>
                  <div class="pk-status-stack">
                    <div class="pk-status">{status_line(@view)}</div>
                    <button class="pk-btn pk-btn--ghost pk-btn--slim" phx-click="show">
                      {gettext("mostrar cartas")}
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

          <div class="pk-side-stack">
            <aside class="pk-side pk-side--panel">
              <div class="pk-tabs">
                <button
                  class={["pk-tab", @rail == :cash && "pk-tab--active"]}
                  phx-click="rail"
                  phx-value-tab="cash"
                >
                  {gettext("caixa")}
                </button>
                <button
                  class={["pk-tab", @rail == :log && "pk-tab--active"]}
                  phx-click="rail"
                  phx-value-tab="log"
                >
                  {gettext("eventos")}
                </button>
                <button
                  class={["pk-tab", @rail == :chat && "pk-tab--active"]}
                  phx-click="rail"
                  phx-value-tab="chat"
                >
                  {gettext("chat")}
                  <span :if={chat_dot?(@view, @rail, @chat_seen_id)} class="pk-tab-dot"></span>
                </button>
              </div>
              <div class="pk-rail-body">
                <%= case @rail do %>
                  <% :log -> %>
                    {event_log(assigns)}
                  <% :chat -> %>
                    <.chat_panel view={@view} where="rail" />
                  <% _cash -> %>
                    {cashier(assigns)}
                <% end %>
              </div>
            </aside>
          </div>
        </div>

        <div :if={@sitting} class="pk-modal-backdrop">
          <form class="pk-panel pk-modal" phx-submit="sit" phx-click-away="cancel_sit">
            <h2 class="pk-panel-title">{gettext("sentar na mesa")}</h2>
            <label class="pk-field">
              <span>{gettext("seu apelido")}</span>
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

        <div :if={@confirm_stand?} class="pk-modal-backdrop">
          <div class="pk-panel pk-modal" phx-click-away="cancel_stand">
            <h2 class="pk-panel-title">{gettext("sacar e sair da mesa?")}</h2>
            <p class="pk-confirm-text">
              {gettext(
                "você vai sacar %{amount} e liberar seu assento. o saldo fica na comanda da noite; pra voltar é um novo buy-in.",
                amount: money(hero_stack(@view), @currency)
              )}
            </p>
            <p :if={@view.phase not in [nil, :complete]} class="pk-confirm-text pk-confirm-warn">
              {gettext("tem mão rolando: você sai quando ela acabar.")}
            </p>
            <div class="pk-modal-actions">
              <button class="pk-btn pk-btn--ghost" phx-click="cancel_stand">
                {gettext("ficar na mesa")}
              </button>
              <button class="pk-btn pk-btn--fold" phx-click="stand">
                {gettext("sair e sacar %{amount}",
                  amount: PokerscarsWeb.Money.chips(hero_stack(@view), @currency)
                )}
              </button>
            </div>
          </div>
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
              <button
                class={["pk-tab", @panel == :chat && "pk-tab--active"]}
                phx-click="panel"
                phx-value-tab="chat"
              >
                {gettext("chat")}
              </button>
            </div>
            <button class="pk-btn pk-btn--ghost pk-btn--slim" phx-click="toggle_ledger">✕</button>
          </div>
          <%= case @panel do %>
            <% :config -> %>
              <.table_config
                view={@view}
                currency={@currency}
                where="drawer"
                config_panel={@config_panel}
              />
            <% :log -> %>
              {event_log(assigns)}
            <% :chat -> %>
              <.chat_panel view={@view} where="drawer" />
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
  defp can_show?(%{result: %{reason: :showdown}} = view) do
    hero = Enum.find(view.seats, & &1.hero?)
    hero != nil and hero.hand_label != nil and not hero.winner? and not hero.shown?
  end

  defp can_show?(_view), do: false

  defp buy_in_min(view), do: elem(view.blinds, 1) * 20

  # render/1 helpers take assigns; raise_bounds wants the socket shape.
  defp assigns_to_socket(assigns), do: %{assigns: assigns}
end
