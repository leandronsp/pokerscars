defmodule Pokerscars.Engine.Button do
  @moduledoc """
  Button and blind geometry over a set of occupied positions. Heads-up is
  the one exception: the button posts the small blind and acts first
  preflop, last on every later street.
  """

  alias Pokerscars.Engine.Seat

  @doc "The next position clockwise after `from`."
  @spec next([Seat.position()], Seat.position()) :: Seat.position()
  def next(positions, from), do: Enum.min_by(positions, &Integer.mod(&1 - from - 1, 10))

  @doc "Small and big blind positions for a hand."
  @spec blind_positions([Seat.position()], Seat.position()) ::
          {Seat.position(), Seat.position()}
  def blind_positions([_, _] = positions, button), do: {button, next(positions, button)}

  def blind_positions(positions, button) do
    small = next(positions, button)
    {small, next(positions, small)}
  end
end
