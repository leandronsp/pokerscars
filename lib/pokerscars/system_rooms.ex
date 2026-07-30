defmodule Pokerscars.SystemRooms do
  @moduledoc """
  The house's three public rooms, opened at boot with fixed codes so their
  links survive restarts. Owned by the system creator: nobody closes them,
  nobody summons bots into them. A periodic sweep replants any room that
  died (a crashed supervisor, a code purge in dev) — opening is idempotent,
  a room that already exists is left alone.
  """

  use GenServer

  alias Pokerscars.{Bots, Table}

  @sweep_ms 60_000

  @rooms [
    %{
      code: "CASA01",
      name: "funciona na minha máquina",
      description:
        "mesa da casa, só humanos. sem bots, sem desculpa: senta e espera aparecer gente.",
      bots: 0
    },
    %{
      code: "CASA02",
      name: "pair programming",
      description: "mesa da casa com 2 bots de plantão. sempre tem jogo.",
      bots: 2
    },
    %{
      code: "CASA03",
      name: "daily standup",
      description: "mesa da casa lotada: 5 bots esperando você. ação na hora.",
      bots: 5
    }
  ]

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_arg), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl GenServer
  def init(:ok) do
    :ok = boot()
    _timer = Process.send_after(self(), :sweep, @sweep_ms)
    {:ok, :ok}
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    :ok = boot()
    _timer = Process.send_after(self(), :sweep, @sweep_ms)
    {:noreply, state}
  end

  @doc "Opens every missing house room and seats its bots. Safe to call again."
  @spec boot() :: :ok
  def boot, do: Enum.each(@rooms, &ensure_room/1)

  defp ensure_room(room) do
    _created =
      unless Table.exists?(room.code) do
        {:ok, _code} =
          Table.create(%{
            code: room.code,
            name: room.name,
            description: room.description,
            blinds: {25, 50},
            buy_in: %{min: 1_000, max: 10_000},
            creator: Table.system_creator(),
            sleep_when_unwatched: true
          })
      end

    top_up_bots(room)
  end

  # The room's bot count is a TARGET, not a creation side effect: however
  # the table came to exist (fresh, restored from Postgres, reborn after a
  # crash), every sweep seats whoever is missing.
  defp top_up_bots(room) do
    case Table.view(room.code, "system-sweep") do
      {:ok, view} ->
        bots_seated =
          Enum.count(
            view.seats,
            &(&1.nickname != nil and String.starts_with?(&1.nickname, "bot-"))
          )

        _seated =
          for _bot <- 1..(room.bots - bots_seated)//1 do
            Bots.add(room.code, requester: Table.system_creator())
          end

        :ok

      {:error, _reason} ->
        :ok
    end
  end
end
