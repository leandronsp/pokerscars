defmodule Pokerscars.Engine.Seat do
  @moduledoc """
  One seat in a hand. `committed` is this street's chips, `contributed` the
  whole hand's — the only input `Pot.build/1` reads. The two booleans carry
  the entire min-raise rule set (see docs/engine-design.md).
  """

  alias Pokerscars.Engine.Card

  @enforce_keys [:position, :player_id, :stack]
  defstruct [
    :position,
    :player_id,
    :stack,
    status: :active,
    hand_state: :in_hand,
    hole_cards: [],
    committed: 0,
    contributed: 0,
    acted_this_round?: false,
    may_raise?: true
  ]

  @type position :: 0..8
  @type chips :: non_neg_integer()
  @type status :: :active | :sitting_out | :waiting
  @type hand_state :: :in_hand | :folded | :all_in

  @type t :: %__MODULE__{
          position: position(),
          player_id: String.t(),
          stack: chips(),
          status: status(),
          hand_state: hand_state(),
          hole_cards: [Card.t()],
          committed: chips(),
          contributed: chips(),
          acted_this_round?: boolean(),
          may_raise?: boolean()
        }

  @doc "Moves `amount` chips (capped at the stack) into the bet. All-in when the stack empties."
  @spec commit(t(), chips()) :: t()
  def commit(%__MODULE__{} = seat, amount) do
    amount = min(amount, seat.stack)
    stack = seat.stack - amount

    %__MODULE__{
      seat
      | stack: stack,
        committed: seat.committed + amount,
        contributed: seat.contributed + amount,
        hand_state: if(stack == 0, do: :all_in, else: seat.hand_state)
    }
  end
end
