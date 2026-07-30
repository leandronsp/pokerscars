defmodule Pokerscars.Bots do
  @moduledoc """
  Bot players for solo play: each bot is a process that sits at a table like
  any human would — same `Pokerscars.Table` door, same projection, no special
  access to hidden state. The context picks a free seat and a free name.
  """

  alias Pokerscars.Bots.Bot
  alias Pokerscars.Table

  @supervisor Pokerscars.Bots.Supervisor
  @names ~w(bot-zeca bot-rita bot-juca bot-lola bot-tonho bot-mimi bot-nino bot-dora)

  @doc """
  Seats a bot at a free position with a 100BB buy-in. When the table has a
  creator, only the creator may summon bots (`opts[:requester]`).
  """
  @spec add(Table.code(), keyword()) :: :ok | {:error, atom()}
  def add(code, opts \\ []) do
    with {:ok, view} <- Table.view(code, "bot-scout"),
         :ok <- authorize(code, opts[:requester]) do
      seat_bot(code, view, opts)
    end
  end

  defp authorize(code, requester) do
    case Pokerscars.Table.creator(code) do
      nil -> :ok
      ^requester -> :ok
      _other -> {:error, :not_owner}
    end
  end

  defp seat_bot(code, view, opts) do
    free = for seat <- view.seats, seat.nickname == nil, do: seat.position
    taken = for seat <- view.seats, seat.nickname != nil, do: seat.position

    if free == [] do
      {:error, :table_full}
    else
      start_bot(%{
        code: code,
        position: spread_position(free, taken),
        nickname: pick_name(view),
        buy_in: elem(view.blinds, 1) * 100,
        delay_ms: Keyword.get(opts, :delay_ms, 1_200),
        heartbeat_ms: Keyword.get(opts, :heartbeat_ms, 5_000)
      })
    end
  end

  defp start_bot(config) do
    case DynamicSupervisor.start_child(@supervisor, {Bot, config}) do
      {:ok, _pid} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # The felt reads balanced when bots spread out: take the free seat that
  # maximizes ring distance to everyone already seated.
  defp spread_position(free, []), do: Enum.random(free)

  defp spread_position(free, taken) do
    Enum.max_by(free, fn position ->
      taken
      |> Enum.map(fn other ->
        distance = abs(position - other)
        min(distance, 9 - distance)
      end)
      |> Enum.min()
    end)
  end

  defp pick_name(view) do
    taken = view.seats |> Enum.map(& &1.nickname) |> Enum.reject(&is_nil/1)

    case Enum.reject(@names, &(&1 in taken)) do
      [] -> "bot-#{System.unique_integer([:positive])}"
      pool -> Enum.random(pool)
    end
  end
end
