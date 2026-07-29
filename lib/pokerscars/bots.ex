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

  @doc "Seats a bot at a free position with a 100BB buy-in."
  @spec add(Table.code(), keyword()) :: :ok | {:error, atom()}
  def add(code, opts \\ []) do
    with {:ok, view} <- Table.view(code, "bot-scout") do
      free = Enum.filter(view.seats, &(&1.nickname == nil))

      case free do
        [] ->
          {:error, :table_full}

        free ->
          config = %{
            code: code,
            position: Enum.random(free).position,
            nickname: pick_name(view),
            buy_in: elem(view.blinds, 1) * 100,
            delay_ms: Keyword.get(opts, :delay_ms, 1_200)
          }

          case DynamicSupervisor.start_child(@supervisor, {Bot, config}) do
            {:ok, _pid} -> :ok
            {:error, reason} -> {:error, reason}
          end
      end
    end
  end

  defp pick_name(view) do
    taken = view.seats |> Enum.map(& &1.nickname) |> Enum.reject(&is_nil/1)

    case Enum.reject(@names, &(&1 in taken)) do
      [] -> "bot-#{System.unique_integer([:positive])}"
      pool -> Enum.random(pool)
    end
  end
end
