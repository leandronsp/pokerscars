defmodule PokerscarsWeb.CardComponents do
  @moduledoc """
  Playing cards as hand-drawn inline SVG — no assets, themeable through
  `--pk-*` tokens. Classic two-colour deck: spades and clubs in ink,
  hearts and diamonds in red. Geometry keeps a safe inner margin so no
  glyph ever touches the rounded corners.
  """

  use Phoenix.Component

  alias Pokerscars.Engine.Card

  @suit_glyphs %{spades: "♠", hearts: "♥", diamonds: "♦", clubs: "♣"}
  @rank_labels %{10 => "10", 11 => "J", 12 => "Q", 13 => "K", 14 => "A"}

  attr :card, Card, required: true
  attr :id, :string, default: nil
  attr :size, :string, values: ~w(hero board small), default: "board"

  @spec card(map()) :: Phoenix.LiveView.Rendered.t()
  def card(assigns) do
    assigns =
      assigns
      |> assign(:rank, rank_label(assigns.card.rank))
      |> assign(:glyph, Map.fetch!(@suit_glyphs, assigns.card.suit))

    ~H"""
    <svg
      id={@id}
      class={["pk-card", "pk-card--#{@size}", "pk-suit--#{@card.suit}"]}
      viewBox="0 0 64 90"
      role="img"
    >
      <title>{@rank}{@glyph}</title>
      <rect x="1" y="1" width="62" height="88" rx="4" fill="url(#pk-face)" class="pk-card-edge" />
      <text x="9" y="27" class="pk-card-rank">{@rank}</text>
      <text x="11" y="45" class="pk-card-corner-suit">{@glyph}</text>
      <text x="38" y="74" text-anchor="middle" class="pk-card-center-suit">{@glyph}</text>
    </svg>
    """
  end

  attr :id, :string, default: nil
  attr :size, :string, values: ~w(hero board small), default: "small"

  @spec card_back(map()) :: Phoenix.LiveView.Rendered.t()
  def card_back(assigns) do
    ~H"""
    <svg id={@id} class={["pk-card", "pk-card--#{@size}"]} viewBox="0 0 64 90" aria-hidden="true">
      <rect x="1" y="1" width="62" height="88" rx="4" fill="url(#pk-back)" class="pk-card-edge" />
      <rect
        x="6"
        y="6"
        width="52"
        height="78"
        rx="2"
        fill="url(#pk-weave)"
        stroke="rgba(255,255,255,0.28)"
        stroke-width="1.2"
      />
    </svg>
    """
  end

  @doc """
  Shared SVG gradients/patterns for every card on the page. Render exactly
  once (the felt does it) — per-card defs would duplicate DOM ids.
  """
  @spec card_defs(map()) :: Phoenix.LiveView.Rendered.t()
  def card_defs(assigns) do
    ~H"""
    <svg width="0" height="0" style="position:absolute" aria-hidden="true">
      <defs>
        <linearGradient id="pk-face" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#fbf7ea" />
          <stop offset="1" stop-color="#ece1c6" />
        </linearGradient>
        <linearGradient id="pk-back" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stop-color="#8c3838" />
          <stop offset="1" stop-color="#5e2020" />
        </linearGradient>
        <pattern id="pk-weave" width="8" height="8" patternUnits="userSpaceOnUse">
          <path d="M0 8 L8 0" stroke="rgba(255,255,255,0.14)" stroke-width="1.4" />
          <path d="M-2 2 L2 -2" stroke="rgba(255,255,255,0.14)" stroke-width="1.4" />
          <path d="M6 10 L10 6" stroke="rgba(255,255,255,0.14)" stroke-width="1.4" />
        </pattern>
      </defs>
    </svg>
    """
  end

  defp rank_label(rank), do: Map.get(@rank_labels, rank, Integer.to_string(rank))
end
