defmodule Pokerscars.Table.Chat do
  @moduledoc """
  Chat rules, pure. The preset vocabulary is the moderation system for
  public rooms: abuse is unrepresentable in a closed set of keys. Private
  rooms allow free text because the owner's guest list is the moderator.
  A token bucket throttles everyone either way. See docs/chat-design.md.
  """

  @presets ~w(nice_hand kkkk bluff gg hurry pay_to_see that_hurt respect good_evening wow clap fire handshake)a

  @burst 3
  @refill_ms 2_000
  @max_length 200

  @type payload :: {:preset, atom()} | {:text, String.t()}
  @typedoc "Remaining tokens and the timestamp (ms) of the last refill."
  @type bucket :: {non_neg_integer(), integer()}

  @doc "The one-tap vocabulary, in display order."
  @spec presets() :: [atom()]
  def presets, do: @presets

  @doc "Validates a message for a room. `private?` unlocks free text."
  @spec validate(payload(), boolean()) :: {:ok, payload()} | {:error, atom()}
  def validate({:preset, key}, _private?) when key in @presets, do: {:ok, {:preset, key}}
  def validate({:preset, _key}, _private?), do: {:error, :unknown_preset}
  def validate({:text, _text}, false), do: {:error, :presets_only}

  def validate({:text, text}, true) do
    case text |> String.trim() |> String.slice(0, @max_length) do
      "" -> {:error, :empty}
      trimmed -> {:ok, {:text, trimmed}}
    end
  end

  @doc "Takes one token from the player's bucket: burst of #{@burst}, one back every #{@refill_ms}ms."
  @spec take(bucket() | nil, integer()) :: {:ok, bucket()} | {:error, :throttled}
  def take(nil, now), do: {:ok, {@burst - 1, now}}

  def take({tokens, last}, now) do
    refilled = div(now - last, @refill_ms)
    tokens = min(@burst, tokens + refilled)
    last = if refilled > 0, do: now, else: last

    if tokens > 0, do: {:ok, {tokens - 1, last}}, else: {:error, :throttled}
  end
end
