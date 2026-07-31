defmodule PokerscarsWeb.TermsLiveTest do
  use PokerscarsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "terms render the play-chips and scoreboard clauses", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/termos")

    assert html =~ "termos de uso"
    assert html =~ "sem qualquer valor monetário"
    assert html =~ "a comanda é um placar"
    assert html =~ "github.com/leandronsp/pokerscars"
  end

  test "terms follow the session locale", %{conn: conn} do
    conn = init_test_session(conn, %{locale: "en"})
    {:ok, _view, html} = live(conn, ~p"/termos")

    assert html =~ "terms of use"
  end

  test "the lobby footer links to the terms", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ ~s(href="/termos")
    assert html =~ "github.com/leandronsp"
  end
end
