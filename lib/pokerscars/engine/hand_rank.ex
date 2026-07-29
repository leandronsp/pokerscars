defmodule Pokerscars.Engine.HandRank do
  @moduledoc """
  The value of a five-card hand: a category plus a fixed-length descending
  tiebreak list per category (`:two_pair` -> [high pair, low pair, kicker]).
  Same-length integer lists compare lexicographically under term order, so
  comparison is category index first, then the list.
  """

  alias Pokerscars.Engine.Card

  @enforce_keys [:category, :tiebreak, :cards]
  defstruct [:category, :tiebreak, :cards]

  @type category ::
          :high_card
          | :pair
          | :two_pair
          | :three_of_a_kind
          | :straight
          | :flush
          | :full_house
          | :four_of_a_kind
          | :straight_flush

  @type t :: %__MODULE__{category: category(), tiebreak: [Card.rank()], cards: [Card.t()]}

  @order [
           :high_card,
           :pair,
           :two_pair,
           :three_of_a_kind,
           :straight,
           :flush,
           :full_house,
           :four_of_a_kind,
           :straight_flush
         ]
         |> Enum.with_index()
         |> Map.new()

  @doc "Total order over hand values."
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(%__MODULE__{} = left, %__MODULE__{} = right) do
    cond do
      key(left) < key(right) -> :lt
      key(left) > key(right) -> :gt
      true -> :eq
    end
  end

  defp key(%__MODULE__{category: category, tiebreak: tiebreak}),
    do: {Map.fetch!(@order, category), tiebreak}
end
