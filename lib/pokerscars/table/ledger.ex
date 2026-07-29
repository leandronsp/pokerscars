defmodule Pokerscars.Table.Ledger do
  @moduledoc """
  The money record of a table: buy-ins and cash-outs in integer cents.
  Settlement is pure math over the entries plus the stacks still on the
  table — the app never moves real money, it tells who owes whom after.
  """

  alias Pokerscars.Engine.Seat

  @enforce_keys [:player_id, :nickname, :kind, :amount, :at]
  defstruct [:player_id, :nickname, :kind, :amount, :at]

  @type kind :: :buy_in | :cash_out
  @type t :: %__MODULE__{
          player_id: String.t(),
          nickname: String.t(),
          kind: kind(),
          amount: Seat.chips(),
          at: DateTime.t()
        }

  @type balance :: %{
          nickname: String.t(),
          buy_in: Seat.chips(),
          result: integer()
        }

  @doc """
  Net result per player: cashed out plus chips still on the table, minus
  bought in. Negative means the player owes the pot, positive collects.
  """
  @spec settlement([t()], %{String.t() => Seat.chips()}) :: [balance()]
  def settlement(entries, live_stacks) do
    entries
    |> Enum.group_by(& &1.player_id)
    |> Enum.map(fn {player_id, player_entries} ->
      buy_in = total(player_entries, :buy_in)
      cash_out = total(player_entries, :cash_out)
      live = Map.get(live_stacks, player_id, 0)

      %{
        nickname: List.last(player_entries).nickname,
        buy_in: buy_in,
        result: cash_out + live - buy_in
      }
    end)
    |> Enum.sort_by(& &1.result, :desc)
  end

  defp total(entries, kind) do
    entries |> Enum.filter(&(&1.kind == kind)) |> Enum.map(& &1.amount) |> Enum.sum()
  end
end
