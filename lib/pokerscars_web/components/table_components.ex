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

  @nine_ring [0, 48, 92, 132, 166, 194, 228, 268, 312]
  @slot_vectors Enum.map(@nine_ring, fn degrees ->
                  radians = degrees * :math.pi() / 180
                  {Float.round(-:math.sin(radians), 3), Float.round(:math.cos(radians), 3)}
                end)

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

  @spec seat(map()) :: Phoenix.LiveView.Rendered.t()
  def seat(%{seat: %SeatView{nickname: nil}} = assigns) do
    ~H"""
    <button
      class="pk-seat pk-seat--empty"
      style={vector_style(@slot)}
      phx-click="open_sit"
      phx-value-position={@seat.position}
    >
      {gettext("sentar")}
    </button>
    """
  end

  def seat(assigns) do
    ~H"""
    <div
      class={[
        "pk-seat pk-seat--taken",
        @seat.state == :folded && "pk-seat--folded",
        @seat.to_act? && "pk-seat--to-act",
        @seat.hero? && "pk-seat--hero",
        @seat.winner? && "pk-seat--winner"
      ]}
      style={vector_style(@slot)}
    >
      <div
        :if={@seat.committed > 0}
        class={["pk-seat-bet", @seat.aggressor? && "pk-seat-bet--aggressor"]}
      >
        <span class="pk-bet-disc" aria-hidden="true"></span>
        <span class="pk-seat-bet-amount">{chips(@seat.committed, @currency)}</span>
        <span :if={@seat.aggressor?} class="pk-bet-tag">{gettext("aumentou")}</span>
      </div>
      <div class="pk-seat-cards">
        <%= case @seat.cards do %>
          <% :hidden -> %>
            <.card_back id={"seat-#{@seat.position}-back-0"} size="small" />
            <.card_back id={"seat-#{@seat.position}-back-1"} size="small" />
          <% [_ | _] = cards -> %>
            <.card
              :for={{card, index} <- Enum.with_index(cards)}
              card={card}
              id={"seat-#{@seat.position}-card-#{index}"}
              size={if @seat.hero?, do: "hero", else: "small"}
            />
          <% _ -> %>
        <% end %>
      </div>
      <div class="pk-seat-pod">
        <.timer_ring :if={@seat.to_act? and @turn != nil} turn={@turn} />
        <span :if={@seat.dealer?} class="pk-dealer" title={gettext("botão")}>D</span>
        <span :if={@seat.hand_label} class="pk-seat-hand">{hand_name(@seat.hand_label)}</span>
        <span class="pk-seat-name">{@seat.nickname}</span>
        <span class="pk-seat-stack">{chips(@seat.stack, @currency)}</span>
        <span :if={@seat.state == :all_in} class="pk-seat-badge pk-seat-badge--allin">
          {gettext("all-in")}
        </span>
        <span :if={@seat.state == :folded} class="pk-seat-badge">{gettext("desistiu")}</span>
      </div>
    </div>
    """
  end

  attr :board, :list, required: true
  attr :pot, :integer, required: true
  attr :bet, :integer, default: 0
  attr :currency, :string, default: "BRL"
  attr :victory, :map, default: nil, doc: "%{line, detail} celebration content"

  @spec board(map()) :: Phoenix.LiveView.Rendered.t()
  def board(assigns) do
    ~H"""
    <div class="pk-center">
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
      <div class="pk-board">
        <.card
          :for={{card, index} <- Enum.with_index(@board)}
          card={card}
          id={"board-card-#{index}"}
          size="board"
        />
        <div :for={_slot <- length(@board)..4//1} :if={length(@board) < 5} class="pk-board-slot" />
      </div>
      <div :if={@victory} class="pk-victory" aria-live="polite">
        <div class="pk-victory-line">{@victory.line}</div>
        <div :if={@victory.detail} class="pk-victory-detail">{@victory.detail}</div>
      </div>
    </div>
    """
  end

  attr :turn, :map, required: true

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
    <svg class="pk-timer" viewBox="0 0 40 40" aria-hidden="true" style={@style}>
      <circle class="pk-timer-track" cx="20" cy="20" r="17" />
      <circle class="pk-timer-arc" cx="20" cy="20" r="17" />
    </svg>
    """
  end

  @doc "Positions an element on the felt ellipse for a display slot."
  @spec vector_style(non_neg_integer()) :: String.t()
  def vector_style(slot) do
    {sx, sy} = Enum.at(@slot_vectors, slot)
    "--sx: #{sx}; --sy: #{sy}"
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

  defp stack_tier(pot) do
    cond do
      pot < 500 -> 2
      pot < 2_000 -> 3
      pot < 5_000 -> 4
      true -> 5
    end
  end
end
