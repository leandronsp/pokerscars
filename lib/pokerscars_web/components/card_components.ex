defmodule PokerscarsWeb.CardComponents do
  @moduledoc """
  Playing cards as hand-drawn inline SVG — no assets, themeable through
  `--pk-*` tokens, four-colour deck by default (see docs/table-design.md).
  """

  use Phoenix.Component

  alias Pokerscars.Engine.Card

  @suit_glyphs %{spades: "♠", hearts: "♥", diamonds: "♦", clubs: "♣"}
  @rank_labels %{10 => "10", 11 => "J", 12 => "Q", 13 => "K", 14 => "A"}

  attr :card, Card, required: true
  attr :size, :string, values: ~w(hero board small), default: "board"

  @spec card(map()) :: Phoenix.LiveView.Rendered.t()
  def card(assigns) do
    assigns =
      assigns
      |> assign(:rank, rank_label(assigns.card.rank))
      |> assign(:glyph, Map.fetch!(@suit_glyphs, assigns.card.suit))

    ~H"""
    <svg
      class={["pk-card", "pk-card--#{@size}", "pk-suit--#{@card.suit}"]}
      viewBox="0 0 64 90"
      role="img"
    >
      <title>{@rank}{@glyph}</title>
      <rect x="1" y="1" width="62" height="88" rx="7" class="pk-card-face" />
      <text x="8" y="24" class="pk-card-rank">{@rank}</text>
      <text x="8" y="42" class="pk-card-corner-suit">{@glyph}</text>
      <text x="38" y="76" class="pk-card-center-suit">{@glyph}</text>
    </svg>
    """
  end

  attr :size, :string, values: ~w(hero board small), default: "small"

  @spec card_back(map()) :: Phoenix.LiveView.Rendered.t()
  def card_back(assigns) do
    ~H"""
    <svg class={["pk-card", "pk-card--#{@size}"]} viewBox="0 0 64 90" aria-hidden="true">
      <rect x="1" y="1" width="62" height="88" rx="7" class="pk-card-back" />
      <rect x="7" y="7" width="50" height="76" rx="4" class="pk-card-back-inner" />
    </svg>
    """
  end

  defp rank_label(rank), do: Map.get(@rank_labels, rank, Integer.to_string(rank))
end
