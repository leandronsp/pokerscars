defmodule PokerscarsWeb.TableComponents do
  @moduledoc """
  The felt and everything anchored to it. Geometry follows the design doc:
  every seat is one angle (0° = hero, bottom-center, increasing screen-left)
  projected onto the felt ellipse through `--sx`/`--sy` custom properties.
  Bets and the dealer button reuse the same trick at smaller radii.
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
      <div class="pk-felt">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :seat, SeatView, required: true
  attr :slot, :integer, required: true, doc: "display slot after hero rotation, 0 = bottom"
  attr :turn, :map, default: nil

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
        @seat.hero? && "pk-seat--hero"
      ]}
      style={vector_style(@slot)}
    >
      <.timer_ring :if={@seat.to_act? and @turn != nil} turn={@turn} />
      <div class="pk-seat-cards">
        <%= case @seat.cards do %>
          <% :hidden -> %>
            <.card_back size="small" />
            <.card_back size="small" />
          <% [_ | _] = cards -> %>
            <.card :for={card <- cards} card={card} size={if @seat.hero?, do: "hero", else: "small"} />
          <% _ -> %>
        <% end %>
      </div>
      <div class="pk-seat-pod">
        <span class="pk-seat-name">{@seat.nickname}</span>
        <span class="pk-seat-stack">{chips(@seat.stack)}</span>
        <span :if={@seat.state == :all_in} class="pk-seat-badge">{gettext("all-in")}</span>
        <span :if={@seat.state == :folded} class="pk-seat-badge">{gettext("foldou")}</span>
      </div>
    </div>
    """
  end

  attr :seat, SeatView, required: true
  attr :slot, :integer, required: true

  @spec bet_chips(map()) :: Phoenix.LiveView.Rendered.t()
  def bet_chips(assigns) do
    ~H"""
    <div :if={@seat.committed > 0} class="pk-bet" style={vector_style(@slot)}>
      <span class="pk-bet-disc" aria-hidden="true"></span>
      {chips(@seat.committed)}
    </div>
    """
  end

  attr :slot, :integer, required: true

  @spec dealer_button(map()) :: Phoenix.LiveView.Rendered.t()
  def dealer_button(assigns) do
    ~H"""
    <div class="pk-dealer" style={vector_style(@slot)} title={gettext("botão")}>D</div>
    """
  end

  attr :board, :list, required: true
  attr :pot, :integer, required: true
  attr :result, :map, default: nil
  attr :payline, :string, default: nil

  @spec board(map()) :: Phoenix.LiveView.Rendered.t()
  def board(assigns) do
    ~H"""
    <div class="pk-center">
      <div class="pk-pot" aria-live="polite">
        {gettext("pote")} <strong>{chips(@pot)}</strong>
      </div>
      <div class="pk-board">
        <.card :for={card <- @board} card={card} size="board" />
        <div :for={_slot <- length(@board)..4//1} :if={length(@board) < 5} class="pk-board-slot" />
      </div>
      <div :if={@payline} class="pk-payline" aria-live="polite">{@payline}</div>
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
end
