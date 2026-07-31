defmodule PokerscarsWeb.AgeTest do
  use ExUnit.Case, async: true

  alias PokerscarsWeb.Age

  @now ~U[2026-07-30 12:00:00Z]

  setup do
    Gettext.put_locale(PokerscarsWeb.Gettext, "pt_BR")
    :ok
  end

  test "since renders minutes, hours and days" do
    assert Age.since(~U[2026-07-30 11:59:40Z], @now) == "agora há pouco"
    assert Age.since(~U[2026-07-30 11:18:00Z], @now) == "há 42 min"
    assert Age.since(~U[2026-07-30 07:00:00Z], @now) == "há 5h"
    assert Age.since(~U[2026-07-29 07:00:00Z], @now) == "há 1 dia"
    assert Age.since(~U[2026-07-24 12:00:00Z], @now) == "há 6 dias"
  end

  test "play renders minutes and hour marks" do
    assert Age.play(30_000) == "menos de 1 min"
    assert Age.play(240_000) == "4 min"
    assert Age.play(3_600_000) == "1h"
    assert Age.play(8_100_000) == "2h15"
  end
end
