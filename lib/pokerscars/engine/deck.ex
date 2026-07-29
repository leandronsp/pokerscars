defmodule Pokerscars.Engine.Deck do
  @moduledoc """
  The 52-card deck.

  Shuffling is deterministic Fisher-Yates over the stateless `:rand` API:
  the engine never reads entropy. The caller supplies the seed (from
  `:crypto.strong_rand_bytes/1` at the boundary), which makes every hand
  replayable and every test deterministic. See docs/engine-design.md.
  """

  alias Pokerscars.Engine.Card

  @enforce_keys [:cards]
  defstruct [:cards]

  @type t :: %__MODULE__{cards: [Card.t()]}
  @type seed :: integer()

  @doc "A fresh deck in canonical order."
  @spec new() :: t()
  def new do
    cards =
      for suit <- [:spades, :hearts, :diamonds, :clubs],
          rank <- 2..14,
          do: %Card{rank: rank, suit: suit}

    %__MODULE__{cards: cards}
  end

  @doc "Deterministic shuffle: the same seed always produces the same order."
  @spec shuffle(t(), seed()) :: t()
  def shuffle(%__MODULE__{cards: cards}, seed) do
    state = :rand.seed_s(:exsss, seed)
    %__MODULE__{cards: fisher_yates(cards, length(cards), state, [])}
  end

  @doc "Deals `count` cards off the top, returning them and the remaining deck."
  @spec deal(t(), non_neg_integer()) :: {[Card.t()], t()}
  def deal(%__MODULE__{cards: cards}, count) when length(cards) >= count do
    {dealt, rest} = Enum.split(cards, count)
    {dealt, %__MODULE__{cards: rest}}
  end

  defp fisher_yates([], 0, _state, acc), do: acc

  defp fisher_yates(cards, count, state, acc) do
    {index, state} = :rand.uniform_s(count, state)
    {card, rest} = List.pop_at(cards, index - 1)
    fisher_yates(rest, count - 1, state, [card | acc])
  end
end
