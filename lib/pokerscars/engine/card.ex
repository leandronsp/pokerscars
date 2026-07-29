defmodule Pokerscars.Engine.Card do
  @moduledoc """
  A playing card. Ace is high (14); the wheel is the evaluator's concern.

  Fixture notation is `"As"`, `"Td"`, `"9c"`: rank in `23456789TJQKA`,
  suit in `shdc`.
  """

  @enforce_keys [:rank, :suit]
  defstruct [:rank, :suit]

  @type rank :: 2..14
  @type suit :: :spades | :hearts | :diamonds | :clubs
  @type t :: %__MODULE__{rank: rank(), suit: suit()}

  @ranks ~w(2 3 4 5 6 7 8 9 T J Q K A) |> Enum.with_index(2) |> Map.new()
  @suits %{"s" => :spades, "h" => :hearts, "d" => :diamonds, "c" => :clubs}

  @doc "Parses one card from fixture notation. Raises on bad input: fixtures are internal."
  @spec parse(String.t()) :: t()
  def parse(<<rank::binary-size(1), suit::binary-size(1)>>) do
    %__MODULE__{rank: Map.fetch!(@ranks, rank), suit: Map.fetch!(@suits, suit)}
  end

  @doc "Parses a space-separated list of cards: `parse_many(\"As Kd 7c\")`."
  @spec parse_many(String.t()) :: [t()]
  def parse_many(notation), do: notation |> String.split() |> Enum.map(&parse/1)
end
