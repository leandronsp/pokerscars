defmodule PokerscarsWeb.Money do
  @moduledoc """
  Chips are integer cents everywhere; only the screen shows money. The
  currency is a display symbol, not an exchange rate — the night is played
  in whatever the table agreed on.
  """

  @symbols %{"BRL" => "R$", "USD" => "$", "EUR" => "€"}

  @doc "Full money format: `format(750)` -> `\"R$ 7,50\"`."
  @spec format(integer(), String.t()) :: String.t()
  def format(cents, currency \\ "BRL"), do: "#{symbol(currency)} #{chips(cents)}"

  @doc "The display symbol for a currency code."
  @spec symbol(String.t()) :: String.t()
  def symbol(currency), do: Map.get(@symbols, currency, "R$")

  @doc "Bare amount for stacks and bets: `chips(750)` -> `\"7,50\"`."
  @spec chips(integer()) :: String.t()
  def chips(cents) when cents < 0, do: "-" <> chips(-cents)

  def chips(cents) do
    "#{div(cents, 100)},#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end
end
