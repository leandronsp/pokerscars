defmodule Pokerscars.Engine.BettingRound do
  @moduledoc """
  One street of betting. Four actions only — all-in is a `:call` or
  `{:raise_to, n}` that consumes the stack, never its own action.

  The round closes when every `:in_hand` seat has acted and matches the bet.
  That single invariant gives the big-blind option for free. Reopening after
  a raise is per-seat, carried by `acted_this_round?` and `may_raise?`.
  See docs/engine-design.md for the worked examples.
  """

  alias Pokerscars.Engine.Seat

  @enforce_keys [:street, :seats, :to_act, :bet_to_match, :last_full_raise, :big_blind]
  defstruct [
    :street,
    :seats,
    :to_act,
    :bet_to_match,
    :last_full_raise,
    :big_blind,
    last_aggressor: nil
  ]

  @type street :: :preflop | :flop | :turn | :river
  @type chips :: non_neg_integer()
  @type action :: :fold | :check | :call | {:raise_to, chips()}
  @type action_error ::
          :not_your_turn
          | :cannot_check
          | :raise_too_small
          | :action_not_reopened
          | :insufficient_chips

  @type t :: %__MODULE__{
          street: street(),
          seats: [Seat.t()],
          to_act: Seat.position() | nil,
          bet_to_match: chips(),
          last_full_raise: chips(),
          big_blind: chips(),
          last_aggressor: Seat.position() | nil
        }

  @doc """
  Opens a street with no bets yet. `min_raise_to` starts at the big blind,
  which is exactly the minimum bet.
  """
  @spec open([Seat.t()], street(), chips(), Seat.position()) :: t()
  def open(seats, street, big_blind, first_to_act) do
    %__MODULE__{
      street: street,
      seats: seats,
      to_act: first_to_act,
      bet_to_match: 0,
      last_full_raise: big_blind,
      big_blind: big_blind
    }
  end

  @doc """
  Opens the preflop round over seats with blinds already committed. The bet
  to match is the full big blind even when the big blind posted short
  (all-in), and the minimum open is twice it.
  """
  @spec preflop([Seat.t()], chips(), Seat.position()) :: t()
  def preflop(seats, big_blind, bb_position) do
    %__MODULE__{
      street: :preflop,
      seats: seats,
      to_act: first_in_hand_after(seats, bb_position),
      bet_to_match: big_blind,
      last_full_raise: big_blind,
      big_blind: big_blind
    }
  end

  @doc "The allowed actions for the seat to act; raise carries its legal bounds."
  @spec legal_actions(t()) ::
          [action() | {:call, chips()} | {:raise_to, chips(), chips()}]
  def legal_actions(%__MODULE__{to_act: nil}), do: []

  def legal_actions(%__MODULE__{} = round) do
    seat = actor(round)
    owed = round.bet_to_match - seat.committed

    check_or_call = if owed == 0, do: [:check], else: [{:call, min(owed, seat.stack)}]

    [:fold] ++ check_or_call ++ List.wrap(raise_bounds(round, seat))
  end

  @doc "Applies the acting seat's action. Player identity is the caller's concern."
  @spec apply_action(t(), action()) :: {:ok, t()} | {:error, action_error()}
  def apply_action(%__MODULE__{to_act: nil}, _action), do: {:error, :not_your_turn}

  def apply_action(%__MODULE__{} = round, :fold) do
    {:ok,
     round
     |> update_actor(fn %Seat{} = seat ->
       %Seat{seat | hand_state: :folded, acted_this_round?: true}
     end)
     |> advance()}
  end

  def apply_action(%__MODULE__{} = round, :check) do
    if actor(round).committed == round.bet_to_match do
      {:ok,
       round
       |> update_actor(fn %Seat{} = seat -> %Seat{seat | acted_this_round?: true} end)
       |> advance()}
    else
      {:error, :cannot_check}
    end
  end

  def apply_action(%__MODULE__{} = round, :call) do
    owed = round.bet_to_match - actor(round).committed

    {:ok,
     round
     |> update_actor(fn %Seat{} = seat ->
       %Seat{Seat.commit(seat, owed) | acted_this_round?: true}
     end)
     |> advance()}
  end

  def apply_action(%__MODULE__{} = round, {:raise_to, amount}) do
    seat = actor(round)
    all_in_raise? = amount == seat.committed + seat.stack

    cond do
      not seat.may_raise? ->
        {:error, :action_not_reopened}

      amount > seat.committed + seat.stack ->
        {:error, :insufficient_chips}

      amount < min_raise_to(round) and not all_in_raise? ->
        {:error, :raise_too_small}

      raise_bounds(round, seat) == nil ->
        {:error, :action_not_reopened}

      true ->
        {:ok, apply_raise(round, seat, amount)}
    end
  end

  @doc "True once every `:in_hand` seat has acted and matches the bet."
  @spec closed?(t()) :: boolean()
  def closed?(%__MODULE__{} = round) do
    round.seats
    |> in_hand()
    |> Enum.all?(&(&1.acted_this_round? and &1.committed == round.bet_to_match))
  end

  defp apply_raise(round, seat, amount) do
    increment = amount - round.bet_to_match
    full? = increment >= round.last_full_raise

    round
    |> update_actor(fn %Seat{} = actor ->
      %Seat{
        Seat.commit(actor, amount - seat.committed)
        | acted_this_round?: true,
          may_raise?: true
      }
    end)
    |> reopen(full?, increment)
    |> Map.put(:bet_to_match, amount)
    |> Map.put(:last_aggressor, seat.position)
    |> advance()
  end

  # A full raise reopens everyone; an incomplete all-in makes the others
  # respond (acted? reset) without restoring the raise right of those who
  # already acted, and never grows the increment.
  defp reopen(%__MODULE__{} = round, full?, increment) do
    seats =
      Enum.map(round.seats, fn %Seat{} = other ->
        cond do
          other.position == round.to_act ->
            other

          full? ->
            %Seat{other | acted_this_round?: false, may_raise?: true}

          true ->
            %Seat{
              other
              | may_raise?: other.may_raise? and not other.acted_this_round?,
                acted_this_round?: false
            }
        end
      end)

    %__MODULE__{
      round
      | seats: seats,
        last_full_raise: if(full?, do: increment, else: round.last_full_raise)
    }
  end

  defp raise_bounds(round, seat) do
    max_to = seat.committed + seat.stack
    others_in_hand? = Enum.any?(in_hand(round.seats), &(&1.position != seat.position))

    if seat.may_raise? and others_in_hand? and max_to > round.bet_to_match do
      {:raise_to, min(min_raise_to(round), max_to), max_to}
    end
  end

  defp min_raise_to(round), do: round.bet_to_match + round.last_full_raise

  defp actor(round), do: Enum.find(round.seats, &(&1.position == round.to_act))

  defp update_actor(%__MODULE__{} = round, fun) do
    seats =
      Enum.map(round.seats, fn %Seat{} = seat ->
        if seat.position == round.to_act, do: fun.(seat), else: seat
      end)

    %__MODULE__{round | seats: seats}
  end

  defp advance(%__MODULE__{} = round) do
    if closed?(round) do
      %__MODULE__{round | to_act: nil}
    else
      %__MODULE__{round | to_act: next_to_act(round)}
    end
  end

  defp next_to_act(round) do
    round.seats
    |> in_hand()
    |> Enum.reject(&(&1.acted_this_round? and &1.committed == round.bet_to_match))
    |> Enum.map(& &1.position)
    |> Enum.min_by(&Integer.mod(&1 - round.to_act - 1, length(round.seats)))
  end

  defp first_in_hand_after(seats, position) do
    case in_hand(seats) do
      [] ->
        nil

      candidates ->
        candidates
        |> Enum.map(& &1.position)
        |> Enum.min_by(&Integer.mod(&1 - position - 1, length(seats)))
    end
  end

  defp in_hand(seats), do: Enum.filter(seats, &(&1.hand_state == :in_hand))
end
