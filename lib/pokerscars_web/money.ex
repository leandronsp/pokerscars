defmodule PokerscarsWeb.Money do
  @moduledoc "Chips are integer cents everywhere; only the screen shows reais."

  @doc "Full money format: `format(750)` -> `\"R$ 7,50\"`."
  @spec format(integer()) :: String.t()
  def format(cents), do: "R$ #{chips(cents)}"

  @doc "Bare amount for stacks and bets: `chips(750)` -> `\"7,50\"`."
  @spec chips(integer()) :: String.t()
  def chips(cents) when cents < 0, do: "-" <> chips(-cents)

  def chips(cents) do
    "#{div(cents, 100)},#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end
end
