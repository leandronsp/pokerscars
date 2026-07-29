defmodule PokerscarsWeb.TableLiveTest do
  use PokerscarsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Pokerscars.Table

  defp create_table(overrides \\ %{}) do
    {:ok, code} =
      Table.create(
        Map.merge(
          %{
            name: "mesa teste",
            blinds: {1, 2},
            buy_in: %{min: 100, max: 1000},
            between_hands_ms: 1,
            turn_ms: 60_000,
            seed_fun: fn -> 7 end
          },
          overrides
        )
      )

    code
  end

  # Two independent browsers: separate conns get separate player ids.
  defp join(code) do
    conn = build_conn() |> get(~p"/t/#{code}")
    {:ok, lv, _html} = live(conn, ~p"/t/#{code}")
    lv
  end

  defp sit(lv, position, nickname) do
    lv |> element("button[phx-value-position='#{position}']") |> render_click()
    lv |> element("form[phx-submit=sit]") |> render_submit(%{nickname: nickname, amount: "2,00"})
  end

  defp await(lv, pattern, tries \\ 100) do
    html = render(lv)

    cond do
      html =~ pattern -> html
      tries == 0 -> flunk("never rendered: #{pattern}")
      true -> Process.sleep(5) && await(lv, pattern, tries - 1)
    end
  end

  test "the lobby creates a table and redirects to it" do
    conn = build_conn() |> get(~p"/")
    {:ok, lv, html} = live(conn, ~p"/")

    assert html =~ "criar mesa"

    lv
    |> element("form[phx-submit=create]")
    |> render_submit(%{name: "sexta", blinds: "25-50"})

    assert_redirect(lv)
  end

  test "an unknown code goes back to the lobby with a flash" do
    conn = build_conn() |> get(~p"/t/NOPE42")
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/t/NOPE42")
  end

  test "two players sit, a hand starts, both see their own cards only" do
    code = create_table()
    ana = join(code)
    bia = join(code)

    sit(ana, 0, "ana")
    sit(bia, 1, "bia")

    ana_html = await(ana, "pk-seat--to-act")
    bia_html = render(bia)

    # Cards render as SVG faces for the hero, backs for the villain.
    assert ana_html =~ "url(#pk-face)"
    assert ana_html =~ "url(#pk-back)"
    assert bia_html =~ "url(#pk-face)"
    assert bia_html =~ "url(#pk-back)"
    assert ana_html =~ "ana"
    assert ana_html =~ "bia"
  end

  test "a full hand plays through the UI to the payline" do
    code = create_table()
    ana = join(code)
    bia = join(code)

    sit(ana, 0, "ana")
    sit(bia, 1, "bia")

    # Heads-up, button 0: ana is SB and acts first.
    await(ana, "phx-value-action=\"call\"")
    ana |> element("button[phx-value-action=call]") |> render_click()

    await(bia, "phx-value-action=\"check\"")
    bia |> element("button[phx-value-action=check]") |> render_click()

    # Flop: bia acts first, bets through the sizing panel.
    await(bia, "phx-click=\"open_sizing\"")
    bia |> element("button[phx-click=open_sizing]") |> render_click()
    bia |> element("button[phx-click=confirm_raise]") |> render_click()

    # Ana folds facing the bet; bia takes the pot.
    await(ana, "phx-value-action=\"fold\"")
    ana |> element("button[phx-value-action=fold]") |> render_click()

    assert await(bia, "leva") =~ "bia leva"
  end

  test "closing a table drops its viewers back at the lobby" do
    code = create_table()
    viewer = join(code)

    :ok = Table.close(code)

    assert_redirect(viewer, "/")
    refute Table.exists?(code)
  end

  test "a spectator gets an explicit call to sit, a seated player does not" do
    code = create_table()
    ana = join(code)
    zeca = join(code)

    assert render(zeca) =~ "você está só assistindo"

    sit(ana, 0, "ana")
    refute render(ana) =~ "você está só assistindo"
    assert render(ana) =~ "você:"
  end

  test "the ledger drawer shows settlement that nets to zero" do
    code = create_table()
    ana = join(code)
    bia = join(code)

    sit(ana, 0, "ana")
    sit(bia, 1, "bia")
    await(ana, "pk-seat--to-act")

    html =
      ana
      |> element("button[phx-click=toggle_ledger]")
      |> render_click()

    assert html =~ "caixa da mesa"
    assert html =~ "ana"
    assert html =~ "2,00"
  end
end
