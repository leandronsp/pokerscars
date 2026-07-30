defmodule PokerscarsWeb.TableComponents do
  @moduledoc """
  The felt and everything anchored to it. Geometry follows the design doc:
  every seat is one angle (0° = hero, bottom-center, increasing screen-left)
  projected onto the felt ellipse through `--sx`/`--sy` custom properties.
  Bets reuse the same trick at a smaller radius; the dealer disc and the
  turn ring ride the pod itself so they never cover cards.
  """

  use Phoenix.Component
  use Gettext, backend: PokerscarsWeb.Gettext

  import PokerscarsWeb.CardComponents
  import PokerscarsWeb.Money

  alias Pokerscars.Table.View.SeatView

  attr :rest, :global
  slot :inner_block, required: true

  @spec felt(map()) :: Phoenix.LiveView.Rendered.t()
  def felt(assigns) do
    ~H"""
    <div class="pk-felt-wrap" {@rest}>
      <.card_defs />
      <div class="pk-felt">
        <div class="pk-felt-inlay" aria-hidden="true"></div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :seat, SeatView, required: true
  attr :slot, :integer, required: true, doc: "display slot after hero rotation, 0 = bottom"
  attr :turn, :map, default: nil
  attr :currency, :string, default: "BRL"
  attr :can_sit?, :boolean, default: true
  attr :waiting?, :boolean, default: false

  @spec seat(map()) :: Phoenix.LiveView.Rendered.t()
  def seat(%{seat: %SeatView{nickname: nil}, can_sit?: true} = assigns) do
    ~H"""
    <button
      id={"seat-root-#{@seat.position}"}
      class={["pk-seat pk-seat--empty", "pk-slot-#{@slot}"]}
      phx-click="open_sit"
      phx-value-position={@seat.position}
    >
      {gettext("sentar")}
    </button>
    """
  end

  def seat(%{seat: %SeatView{nickname: nil}} = assigns) do
    ~H"""
    <div
      id={"seat-root-#{@seat.position}"}
      class={["pk-seat pk-seat--empty pk-seat--idle", "pk-slot-#{@slot}"]}
      aria-hidden="true"
    >
    </div>
    """
  end

  def seat(assigns) do
    ~H"""
    <div
      id={"seat-root-#{@seat.position}"}
      class={[
        "pk-seat pk-seat--taken",
        "pk-slot-#{@slot}",
        @seat.state == :folded && "pk-seat--folded",
        @seat.to_act? && "pk-seat--to-act",
        @seat.hero? && "pk-seat--hero",
        @seat.winner? && "pk-seat--winner",
        @seat.main_winner? && "pk-seat--winner-main",
        @seat.away? && "pk-seat--away",
        @waiting? && @seat.hero? && "pk-seat--waiting"
      ]}
    >
      <%!-- Always in the DOM, hidden by CSS when idle: inserting/removing
            this sibling made the patcher re-append the card containers and
            recreate their SVGs (the mid-hand card blink). --%>
      <div
        id={"seat-bet-#{@seat.position}"}
        class={[
          "pk-seat-bet",
          @seat.committed == 0 && "pk-seat-bet--none",
          @seat.aggressor? && "pk-seat-bet--aggressor"
        ]}
      >
        <span class="pk-bet-disc" aria-hidden="true"></span>
        <span class="pk-seat-bet-amount">{chips(@seat.committed, @currency)}</span>
        <span :if={@seat.aggressor?} class="pk-bet-tag">{gettext("aumentou")}</span>
      </div>
      <%!-- Structural branches live in :if/:for attributes, never in an EEx
            case: a single dynamic block re-renders (and repaints the SVG
            cards) every time any seat field changes. --%>
      <div id={"seat-cards-#{@seat.position}"} class="pk-seat-cards">
        <.card_back :if={@seat.cards == :hidden} id={"seat-#{@seat.position}-back-0"} size="small" />
        <.card_back :if={@seat.cards == :hidden} id={"seat-#{@seat.position}-back-1"} size="small" />
        <.card
          :for={{card, index} <- Enum.with_index(visible_cards(@seat.cards))}
          :key={index}
          card={card}
          id={"seat-#{@seat.position}-card-#{index}"}
          size={if @seat.hero?, do: "hero", else: "small"}
        />
      </div>
      <div id={"seat-pod-#{@seat.position}"} class="pk-seat-pod">
        <.timer_ring :if={@seat.to_act? and @turn != nil} id={"timer-#{@seat.position}"} turn={@turn} />
        <span
          :if={@seat.dealer?}
          id={"dealer-#{@seat.position}"}
          class="pk-dealer"
          title={gettext("botão")}
        >D</span>
        <span :if={@seat.hand_label} id={"handlabel-#{@seat.position}"} class="pk-seat-hand">{hand_name(
          @seat.hand_label
        )}</span>
        <span id={"name-#{@seat.position}"} class="pk-seat-name">{@seat.nickname}</span>
        <span id={"stack-#{@seat.position}"} class="pk-seat-stack">
          <span class="pk-podstack" aria-hidden="true">
            <i :for={_coin <- 1..stack_tier(@seat.stack || 0)} class="pk-chipstack-coin"></i>
          </span>
          {chips(@seat.stack, @currency)}
        </span>
        <span :if={@seat.won} id={"won-#{@seat.position}"} class="pk-seat-won">
          +{chips(@seat.won, @currency)}
        </span>
        <span
          :if={@seat.state == :all_in}
          id={"allin-#{@seat.position}"}
          class="pk-seat-badge pk-seat-badge--allin"
        >
          {gettext("all-in")}
        </span>
        <span :if={@seat.state == :folded} id={"folded-#{@seat.position}"} class="pk-seat-badge">{gettext(
          "desistiu"
        )}</span>
        <span :if={@seat.away?} id={"away-#{@seat.position}"} class="pk-seat-badge">{gettext("caiu")}</span>
      </div>
    </div>
    """
  end

  attr :board, :list, required: true
  attr :pot, :integer, required: true
  attr :pots, :list, default: [], doc: "main pot first, then side pots, when an all-in split them"
  attr :bet, :integer, default: 0
  attr :currency, :string, default: "BRL"
  attr :victory, :map, default: nil, doc: "%{line, detail} celebration content"

  @spec board(map()) :: Phoenix.LiveView.Rendered.t()
  def board(assigns) do
    ~H"""
    <div id="pk-center" class="pk-center">
      <div class="pk-pot-row" aria-live="polite">
        <div class="pk-pot-block">
          <span class="pk-chipstack" aria-hidden="true">
            <i :for={_coin <- 1..stack_tier(@pot)} class="pk-chipstack-coin"></i>
          </span>
          <span class="pk-pot-figures">
            <strong class="pk-pot-amount">{format(@pot, @currency)}</strong>
            <span class="pk-pot-label">{gettext("pote")}</span>
          </span>
        </div>
        <div :if={@bet > 0 and @victory == nil} class="pk-bet-now">
          <strong>{chips(@bet, @currency)}</strong>
          <span>{gettext("aposta atual")}</span>
        </div>
      </div>
      <div :if={length(@pots) > 1 and @victory == nil} class="pk-pot-split" aria-live="polite">
        {pot_split_line(@pots, @currency)}
      </div>
      <%!-- Five fixed positions that flip between slot and card internally:
            appending cards used to shift the placeholder slots and recreate
            the already-dealt cards' SVGs. --%>
      <div class="pk-board">
        <div :for={index <- 0..4} :key={index} id={"board-pos-#{index}"} class="pk-board-pos">
          <%!-- A real 3D flip: back and face are the two sides of one
                mount-once wrapper, so each street turns its cards over. --%>
          <div :if={Enum.at(@board, index)} id={"board-flip-#{index}"} class="pk-flip">
            <.card_back id={"board-flipback-#{index}"} size="board" />
            <.card card={Enum.at(@board, index)} id={"board-card-#{index}"} size="board" />
          </div>
          <div :if={Enum.at(@board, index) == nil} class="pk-board-slot" />
        </div>
      </div>
    </div>
    """
  end

  attr :turn, :map, required: true
  attr :id, :string, default: nil

  @spec timer_ring(map()) :: Phoenix.LiveView.Rendered.t()
  def timer_ring(assigns) do
    remaining = max(assigns.turn.deadline_ms - System.system_time(:millisecond), 0)
    elapsed = assigns.turn.total_ms - remaining

    assigns =
      assign(
        assigns,
        :style,
        "--pk-turn-ms: #{assigns.turn.total_ms}ms; --pk-elapsed: #{elapsed}ms"
      )

    ~H"""
    <svg id={@id} class="pk-timer" viewBox="0 0 40 40" aria-hidden="true" style={@style}>
      <circle class="pk-timer-track" cx="20" cy="20" r="17" />
      <circle class="pk-timer-arc" cx="20" cy="20" r="17" />
    </svg>
    """
  end

  attr :flights, :list, required: true, doc: "[%{id, slot, delay_ms}] pot-to-winner chips"

  @spec chip_flights(map()) :: Phoenix.LiveView.Rendered.t()
  def chip_flights(assigns) do
    ~H"""
    <div
      :for={flight <- @flights}
      id={flight.id}
      class={["pk-chip-flight", "pk-slot-#{flight.slot}"]}
      style={"--pk-fly-delay: #{flight.delay_ms}ms"}
    >
      <i :for={_coin <- 1..4} class="pk-chipstack-coin"></i>
    </div>
    """
  end

  @doc "The hand category in words."
  @spec hand_name(Pokerscars.Engine.HandRank.category()) :: String.t()
  def hand_name(:high_card), do: gettext("carta alta")
  def hand_name(:pair), do: gettext("par")
  def hand_name(:two_pair), do: gettext("dois pares")
  def hand_name(:three_of_a_kind), do: gettext("trinca")
  def hand_name(:straight), do: gettext("sequência")
  def hand_name(:flush), do: gettext("flush")
  def hand_name(:full_house), do: gettext("full house")
  def hand_name(:four_of_a_kind), do: gettext("quadra")
  def hand_name(:straight_flush), do: gettext("straight flush")

  defp visible_cards(cards) when is_list(cards), do: cards
  defp visible_cards(_hidden_or_none), do: []

  defp pot_split_line([main | sides], currency) do
    [
      gettext("principal %{amount}", amount: chips(main, currency))
      | Enum.map(sides, &gettext("lateral %{amount}", amount: chips(&1, currency)))
    ]
    |> Enum.join(" · ")
  end

  defp stack_tier(pot) do
    cond do
      pot < 500 -> 2
      pot < 2_000 -> 3
      pot < 5_000 -> 4
      true -> 5
    end
  end
end
