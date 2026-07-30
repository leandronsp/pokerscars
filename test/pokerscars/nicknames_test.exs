defmodule Pokerscars.NicknamesTest do
  use ExUnit.Case, async: true

  alias Pokerscars.Nicknames

  test "ordinary names pass" do
    assert :ok = Nicknames.check("lele")
    assert :ok = Nicknames.check("Mesa dos amigos")
    assert :ok = Nicknames.check("bot-zeca")
    assert :ok = Nicknames.check("Ana Clara 77")
  end

  test "slurs are rejected, including common evasions" do
    assert {:error, :name_not_allowed} = Nicknames.check("macaco")
    assert {:error, :name_not_allowed} = Nicknames.check("M4c4co")
    assert {:error, :name_not_allowed} = Nicknames.check("m.a.c.a.c.o")
    assert {:error, :name_not_allowed} = Nicknames.check("VIADO")
    assert {:error, :name_not_allowed} = Nicknames.check("v1ad0 do poker")
    assert {:error, :name_not_allowed} = Nicknames.check("nigger")
    assert {:error, :name_not_allowed} = Nicknames.check("n1gg3r")
  end

  test "innocent words containing risky substrings survive" do
    assert :ok = Nicknames.check("sniper")
    assert :ok = Nicknames.check("gato")
  end
end
