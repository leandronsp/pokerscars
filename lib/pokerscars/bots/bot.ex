defmodule Pokerscars.Bots.Bot do
  @moduledoc """
  One bot player. Subscribes to the table like a LiveView does, waits a
  human-feeling delay on its turn, then acts on a simple hand-strength rule
  using the engine's own evaluator. Rebuys when busted. Stops when the table
  is gone. Deliberately beatable: it exists for solo play, not to win.
  """

  use GenServer, restart: :transient

  alias Pokerscars.Engine.{Evaluator, HandRank}
  alias Pokerscars.Table

  @enforce_keys [:code, :player_id, :delay_ms, :buy_in]
  defstruct [:code, :player_id, :delay_ms, :buy_in, thinking?: false]

  @type t :: %__MODULE__{}

  @categories_strength %{
    high_card: 0.15,
    pair: 0.45,
    two_pair: 0.65,
    three_of_a_kind: 0.8,
    straight: 0.9,
    flush: 0.92,
    full_house: 0.95,
    four_of_a_kind: 1.0,
    straight_flush: 1.0
  }

  @spec start_link(map()) :: GenServer.on_start()
  def start_link(config), do: GenServer.start_link(__MODULE__, config)

  @impl GenServer
  def init(config) do
    player_id = "bot-" <> Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)
    :ok = Table.subscribe(config.code)

    case Table.sit(config.code, player_id, config.nickname, config.position, config.buy_in) do
      :ok ->
        {:ok,
         %__MODULE__{
           code: config.code,
           player_id: player_id,
           delay_ms: config.delay_ms,
           buy_in: config.buy_in
         }}

      {:error, reason} ->
        {:stop, {:shutdown, reason}}
    end
  end

  @impl GenServer
  def handle_info({:table_updated, _code}, %__MODULE__{thinking?: true} = state),
    do: {:noreply, state}

  def handle_info({:table_updated, _code}, %__MODULE__{} = state) do
    _ref = Process.send_after(self(), :act, state.delay_ms)
    {:noreply, %__MODULE__{state | thinking?: true}}
  end

  def handle_info(:act, %__MODULE__{} = state) do
    case Table.view(state.code, state.player_id) do
      {:ok, view} ->
        act_on(view, state)
        {:noreply, %__MODULE__{state | thinking?: false}}

      {:error, :table_not_found} ->
        {:stop, :normal, state}
    end
  end

  defp act_on(view, state) do
    hero = Enum.find(view.seats, & &1.hero?)

    cond do
      hero == nil ->
        :ok

      view.hero_actions != [] ->
        # Stale-turn errors are fine: someone acted while we "thought".
        _result = Table.act(state.code, state.player_id, decide(view, hero))
        :ok

      hero.stack == 0 and view.phase in [nil, :complete] ->
        _result = Table.rebuy(state.code, state.player_id, state.buy_in)
        :ok

      true ->
        :ok
    end
  end

  defp decide(view, hero) do
    actions = view.hero_actions
    raise_bounds = Enum.find(actions, &match?({:raise_to, _min, _max}, &1))
    call = Enum.find(actions, &match?({:call, _amount}, &1))
    check? = :check in actions
    strength = strength(hero.cards, view.board) + jitter()

    cond do
      strength >= 0.75 and raise_bounds != nil -> pot_raise(view, raise_bounds)
      strength >= 0.4 and call != nil -> :call
      check? -> :check
      call != nil and cheap_call?(call, hero, strength) -> :call
      true -> :fold
    end
  end

  # Preflop: pairs are strong, big cards are decent. Postflop: the made-hand
  # category through the engine's evaluator.
  defp strength([first, second], []) do
    cond do
      first.rank == second.rank -> 0.55 + first.rank / 31
      true -> (first.rank + second.rank) / 54 + if(first.suit == second.suit, do: 0.05, else: 0)
    end
  end

  defp strength(cards, board) when length(board) >= 3 do
    %HandRank{category: category} = Evaluator.evaluate(cards ++ board)
    Map.fetch!(@categories_strength, category)
  end

  defp strength(_cards, _board), do: 0.3

  defp pot_raise(view, {:raise_to, min, max}) do
    {:raise_to, (view.bet_to_match + view.pot) |> max(min) |> min(max)}
  end

  defp cheap_call?({:call, amount}, hero, strength),
    do: strength >= 0.3 and amount <= div(hero.stack, 8)

  defp jitter, do: (:rand.uniform() - 0.5) * 0.15
end
