defmodule PokerscarsWeb.Age do
  @moduledoc """
  Ages and play-time durations for the screen: a table says how long ago it
  opened and how much of that time had hands actually on the felt.
  """

  use Gettext, backend: PokerscarsWeb.Gettext

  @minute 60
  @hour 3_600
  @day 86_400

  @doc "Relative age: `since(~U[2026-07-27 00:00:00Z])` -> `\"há 3 dias\"`."
  @spec since(DateTime.t(), DateTime.t()) :: String.t()
  def since(%DateTime{} = at, now \\ DateTime.utc_now()) do
    seconds = DateTime.diff(now, at)

    cond do
      seconds < @minute -> gettext("agora há pouco")
      seconds < @hour -> gettext("há %{n} min", n: div(seconds, @minute))
      seconds < @day -> gettext("há %{n}h", n: div(seconds, @hour))
      true -> ngettext("há %{count} dia", "há %{count} dias", div(seconds, @day))
    end
  end

  @doc "Play time from milliseconds: `play(8_100_000)` -> `\"2h15\"`."
  @spec play(non_neg_integer()) :: String.t()
  def play(ms) when ms < 60_000, do: gettext("menos de 1 min")

  def play(ms) do
    minutes = div(ms, 60_000)

    case {div(minutes, 60), rem(minutes, 60)} do
      {0, m} -> gettext("%{m} min", m: m)
      {h, 0} -> gettext("%{h}h", h: h)
      {h, m} -> gettext("%{h}h%{m}", h: h, m: String.pad_leading("#{m}", 2, "0"))
    end
  end
end
