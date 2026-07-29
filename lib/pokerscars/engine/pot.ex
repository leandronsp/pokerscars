defmodule Pokerscars.Engine.Pot do
  @moduledoc """
  Pots are derived, never accumulated: `build/1` recomputes everything from
  `Seat.contributed`, so there is no incremental pot to drift out of sync.
  A contribution layer with a single contributor was never called — it is
  refunded, which covers both the uncalled bet and the excess of the biggest
  stack in a multi-way all-in. See docs/engine-design.md.
  """

  alias Pokerscars.Engine.Seat

  @enforce_keys [:amount, :eligible]
  defstruct [:amount, :eligible]

  @type chips :: non_neg_integer()
  @type t :: %__MODULE__{amount: chips(), eligible: [Seat.position()]}

  @doc "Builds the pot structure and the refunds map from scratch."
  @spec build([Seat.t()]) :: {[t()], %{Seat.position() => chips()}}
  def build(seats) do
    levels =
      seats
      |> Enum.map(& &1.contributed)
      |> Enum.filter(&(&1 > 0))
      |> Enum.uniq()
      |> Enum.sort()

    {pots, refunds, _prev} = Enum.reduce(levels, {[], %{}, 0}, &layer(seats, &1, &2))

    {pots |> Enum.reverse() |> merge(), refunds}
  end

  defp layer(seats, level, {pots, refunds, prev}) do
    slice = level - prev
    contributors = Enum.filter(seats, &(&1.contributed >= level))

    case contributors do
      [only] ->
        {pots, Map.update(refunds, only.position, slice, &(&1 + slice)), level}

      many ->
        eligible =
          many
          |> Enum.reject(&(&1.hand_state == :folded))
          |> Enum.map(& &1.position)
          |> Enum.sort()

        {[%__MODULE__{amount: slice * length(many), eligible: eligible} | pots], refunds, level}
    end
  end

  # Adjacent layers with the same eligible seats are one pot: folded chips
  # join the layer they were paid into without multiplying pots on screen.
  defp merge([%__MODULE__{} = a, %__MODULE__{} = b | rest]) when a.eligible == b.eligible,
    do: merge([%__MODULE__{a | amount: a.amount + b.amount} | rest])

  defp merge([pot | rest]), do: [pot | merge(rest)]
  defp merge([]), do: []
end
