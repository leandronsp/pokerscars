defmodule Pokerscars.Table.ChatTest do
  use ExUnit.Case, async: true

  alias Pokerscars.Table.Chat

  test "presets are a closed vocabulary" do
    assert :nice_hand in Chat.presets()
    assert {:ok, {:preset, :nice_hand}} = Chat.validate({:preset, :nice_hand}, false)
    assert {:error, :unknown_preset} = Chat.validate({:preset, :racist_rant}, false)
  end

  test "free text only exists in private rooms" do
    assert {:error, :presets_only} = Chat.validate({:text, "e aí"}, false)
    assert {:ok, {:text, "e aí"}} = Chat.validate({:text, "  e aí  "}, true)
    assert {:error, :empty} = Chat.validate({:text, "   "}, true)
  end

  test "text is capped at 200 characters" do
    {:ok, {:text, text}} = Chat.validate({:text, String.duplicate("a", 500)}, true)
    assert String.length(text) == 200
  end

  test "the bucket allows a burst of three then throttles, refilling one per 2s" do
    {:ok, bucket} = Chat.take(nil, 0)
    {:ok, bucket} = Chat.take(bucket, 100)
    {:ok, bucket} = Chat.take(bucket, 200)
    assert {:error, :throttled} = Chat.take(bucket, 300)
    assert {:ok, _bucket} = Chat.take(bucket, 2_300)
  end
end
