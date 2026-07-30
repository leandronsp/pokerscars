defmodule PokerscarsWeb.ChaosController do
  @moduledoc """
  Dev-only chaos tooling: kill a table's bot processes on purpose and watch
  supervision resurrect them into their own seats. Mounted under /dev.
  """

  use PokerscarsWeb, :controller

  @doc "Brutally kills up to `n` bots of the given table (default: all)."
  def kill_bots(conn, %{"code" => code} = params) do
    limit = String.to_integer(params["n"] || "9")

    killed =
      Pokerscars.Bots.Supervisor
      |> DynamicSupervisor.which_children()
      |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
      |> Enum.filter(&bot_of?(&1, code))
      |> Enum.take(limit)
      |> Enum.map(fn pid ->
        true = Process.exit(pid, :kill)
        inspect(pid)
      end)

    text(conn, "killed #{length(killed)} bots on #{code}: #{Enum.join(killed, ", ")}\n")
  end

  defp bot_of?(pid, code) do
    Process.alive?(pid) and String.contains?(:sys.get_state(pid).player_id, code)
  catch
    # The bot died between listing and inspection: chaos, indeed.
    :exit, _reason -> false
  end
end
