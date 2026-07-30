defmodule Pokerscars.Nicknames do
  @moduledoc """
  The name filter at the boundary: nicknames and table names render for
  everyone, which makes them the one free-text vector in public rooms.
  Normalization folds case, accents, leetspeak and separators before the
  match, so `M4c4co` and `m.a.c.a.c.o` are the same word. The list is short
  and severe on purpose: catching slurs, not policing vocabulary.
  """

  # Severe slurs only (pt-BR and en). Substring-matched on the collapsed
  # form: conservative by design, a rare false positive beats a slur on
  # screen. Moderation wordlist, kept deliberately minimal.
  @banned ~w(
    macaco crioulo viado baitola sapatao traveco mongoloide retardado
    nigger nigga faggot hitler
  )

  @leet %{
    "0" => "o",
    "1" => "i",
    "3" => "e",
    "4" => "a",
    "5" => "s",
    "7" => "t",
    "@" => "a",
    "$" => "s"
  }

  @doc "Validates a player-visible name. Returns `:ok` or `{:error, :name_not_allowed}`."
  @spec check(String.t()) :: :ok | {:error, :name_not_allowed}
  def check(name) do
    collapsed = collapse(name)

    if Enum.any?(@banned, &String.contains?(collapsed, &1)) do
      {:error, :name_not_allowed}
    else
      :ok
    end
  end

  defp collapse(name) do
    name
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.graphemes()
    |> Enum.map_join(&Map.get(@leet, &1, &1))
    |> String.replace(~r/[^a-z]/u, "")
  end
end
