defmodule Pokerscars.Table.Server do
  @moduledoc """
  The aggregate root of one running table. Owns all mutation: seats, the
  current hand, turn timers and the ledger. Commands come in through
  `Pokerscars.Table`, every change broadcasts `{:table_updated, code}` and
  interested LiveViews pull their own projection.
  """

  use GenServer

  alias Pokerscars.Engine.{Button, Hand}
  alias Pokerscars.Table
  alias Pokerscars.Table.{Ledger, View}

  @enforce_keys [:code, :name, :blinds, :buy_in, :turn_ms, :between_hands_ms, :seed_fun]
  defstruct [
    :code,
    :name,
    :blinds,
    :buy_in,
    :turn_ms,
    :between_hands_ms,
    :seed_fun,
    :hand,
    :button,
    seats: %{},
    hand_no: 0,
    ledger: [],
    turn_deadline: nil,
    timer_ref: nil,
    start_scheduled?: false,
    pending_stands: []
  ]

  @type seat_info :: %{player_id: String.t(), nickname: String.t(), stack: non_neg_integer()}
  @type t :: %__MODULE__{}

  @max_seats 9
  @default_turn_ms 30_000
  @default_between_hands_ms 4_000

  @spec start_link(map()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: Table.via(config.code))
  end

  @impl GenServer
  def init(config) do
    {:ok,
     %__MODULE__{
       code: config.code,
       name: config.name,
       blinds: config.blinds,
       buy_in: config.buy_in,
       turn_ms: Map.get(config, :turn_ms, @default_turn_ms),
       between_hands_ms: Map.get(config, :between_hands_ms, @default_between_hands_ms),
       seed_fun: Map.get(config, :seed_fun, &default_seed/0)
     }}
  end

  @impl GenServer
  def handle_call({:sit, player_id, nickname, position, amount}, _from, state) do
    cond do
      position not in 0..(@max_seats - 1) -> reply_error(state, :invalid_position)
      Map.has_key?(state.seats, position) -> reply_error(state, :seat_taken)
      seated?(state, player_id) -> reply_error(state, :already_seated)
      not buy_in_allowed?(state, amount) -> reply_error(state, :invalid_buy_in)
      true -> do_sit(state, player_id, nickname, position, amount)
    end
  end

  def handle_call({:rebuy, player_id, amount}, _from, state) do
    cond do
      not seated?(state, player_id) -> reply_error(state, :not_seated)
      not buy_in_allowed?(state, amount) -> reply_error(state, :invalid_buy_in)
      in_current_hand?(state, player_id) -> reply_error(state, :hand_in_progress)
      true -> do_rebuy(state, player_id, amount)
    end
  end

  def handle_call({:stand, player_id}, _from, state) do
    cond do
      not seated?(state, player_id) ->
        reply_error(state, :not_seated)

      in_current_hand?(state, player_id) ->
        {:reply, :ok, %__MODULE__{state | pending_stands: [player_id | state.pending_stands]}}

      true ->
        {:reply, :ok, state |> do_stand(player_id) |> broadcast()}
    end
  end

  def handle_call({:act, _player_id, _action}, _from, %__MODULE__{hand: nil} = state),
    do: {:reply, {:error, :no_hand}, state}

  def handle_call({:act, player_id, action}, _from, state) do
    case Hand.act(state.hand, player_id, action) do
      {:ok, hand} -> {:reply, :ok, state |> put_hand(hand) |> broadcast()}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:view, player_id}, _from, state) do
    {:reply, {:ok, View.project(state, player_id)}, state}
  end

  @impl GenServer
  def handle_info(:start_hand, state) do
    state = %__MODULE__{state | start_scheduled?: false}
    entrants = entrants(state)

    if map_size(entrants) >= 2 do
      button = next_button(state, entrants)
      hand = Hand.start(entrants, button, state.blinds, state.seed_fun.())

      state =
        %__MODULE__{state | button: button, hand_no: state.hand_no + 1}
        |> put_hand(hand)
        |> broadcast()

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:turn_timeout, hand_no, position}, state) do
    with %Hand{} = hand <- state.hand,
         true <- state.hand_no == hand_no and hand.round.to_act == position do
      seat = Enum.find(hand.round.seats, &(&1.position == position))
      action = if seat.committed == hand.round.bet_to_match, do: :check, else: :fold
      {:ok, hand} = Hand.act(hand, seat.player_id, action)
      {:noreply, state |> put_hand(hand) |> broadcast()}
    else
      _stale -> {:noreply, state}
    end
  end

  defp do_sit(state, player_id, nickname, position, amount) do
    seat = %{player_id: player_id, nickname: nickname, stack: amount}

    state =
      %__MODULE__{state | seats: Map.put(state.seats, position, seat)}
      |> record(player_id, nickname, :buy_in, amount)
      |> maybe_schedule_start()
      |> broadcast()

    {:reply, :ok, state}
  end

  defp do_rebuy(state, player_id, amount) do
    {position, seat} = seat_of(state, player_id)
    seats = Map.put(state.seats, position, %{seat | stack: seat.stack + amount})

    state =
      %__MODULE__{state | seats: seats}
      |> record(player_id, seat.nickname, :buy_in, amount)
      |> maybe_schedule_start()
      |> broadcast()

    {:reply, :ok, state}
  end

  defp do_stand(state, player_id) do
    {position, seat} = seat_of(state, player_id)

    %__MODULE__{state | seats: Map.delete(state.seats, position)}
    |> record(player_id, seat.nickname, :cash_out, seat.stack)
  end

  # While a hand runs the stacks live inside it; when it completes they come
  # home to the seats, pending stands execute, and the next hand is scheduled.
  defp put_hand(state, %Hand{phase: :complete} = hand) do
    seats =
      Map.new(state.seats, fn {position, seat} ->
        case Enum.find(hand.round.seats, &(&1.position == position)) do
          nil -> {position, seat}
          played -> {position, %{seat | stack: played.stack}}
        end
      end)

    %__MODULE__{state | hand: hand, seats: seats, turn_deadline: nil}
    |> cancel_timer()
    |> execute_pending_stands()
    |> maybe_schedule_start()
  end

  defp put_hand(state, %Hand{} = hand) do
    deadline = System.system_time(:millisecond) + state.turn_ms

    ref =
      Process.send_after(self(), {:turn_timeout, state.hand_no, hand.round.to_act}, state.turn_ms)

    %__MODULE__{cancel_timer(state) | hand: hand, turn_deadline: deadline, timer_ref: ref}
  end

  defp execute_pending_stands(state) do
    state.pending_stands
    |> Enum.reduce(%__MODULE__{state | pending_stands: []}, fn player_id, acc ->
      if seated?(acc, player_id), do: do_stand(acc, player_id), else: acc
    end)
  end

  defp maybe_schedule_start(%__MODULE__{start_scheduled?: true} = state), do: state

  defp maybe_schedule_start(state) do
    if hand_running?(state) or map_size(entrants(state)) < 2 do
      state
    else
      _ref = Process.send_after(self(), :start_hand, state.between_hands_ms)
      %__MODULE__{state | start_scheduled?: true}
    end
  end

  defp entrants(state) do
    for {position, seat} <- state.seats, seat.stack > 0, into: %{} do
      {position, {seat.player_id, seat.stack}}
    end
  end

  defp next_button(%__MODULE__{button: nil}, entrants), do: entrants |> Map.keys() |> Enum.min()
  defp next_button(state, entrants), do: Button.next(Map.keys(entrants), state.button)

  defp hand_running?(%__MODULE__{hand: %Hand{phase: phase}}), do: phase != :complete
  defp hand_running?(%__MODULE__{hand: nil}), do: false

  defp in_current_hand?(state, player_id) do
    hand_running?(state) and
      Enum.any?(state.hand.round.seats, &(&1.player_id == player_id))
  end

  defp seated?(state, player_id), do: seat_of(state, player_id) != nil

  defp seat_of(state, player_id) do
    Enum.find(state.seats, fn {_position, seat} -> seat.player_id == player_id end)
  end

  defp buy_in_allowed?(state, amount), do: amount in state.buy_in.min..state.buy_in.max

  defp record(state, player_id, nickname, kind, amount) do
    entry = %Ledger{
      player_id: player_id,
      nickname: nickname,
      kind: kind,
      amount: amount,
      at: DateTime.utc_now()
    }

    %__MODULE__{state | ledger: [entry | state.ledger]}
  end

  defp cancel_timer(%__MODULE__{timer_ref: nil} = state), do: state

  defp cancel_timer(state) do
    _cancelled = Process.cancel_timer(state.timer_ref)
    %__MODULE__{state | timer_ref: nil}
  end

  defp broadcast(state) do
    :ok =
      Phoenix.PubSub.broadcast(
        Pokerscars.PubSub,
        Table.topic(state.code),
        {:table_updated, state.code}
      )

    state
  end

  defp reply_error(state, reason), do: {:reply, {:error, reason}, state}

  defp default_seed, do: :crypto.strong_rand_bytes(8) |> :binary.decode_unsigned()
end
