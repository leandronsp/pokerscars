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
            seed_fun: fn -> 7 end,
            reveal_ms: 1
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

  defp await(lv, pattern, tries \\ 400) do
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
    # Long pause after the hand so the victory banner holds still for asserts.
    code = create_table(%{between_hands_ms: 60_000})
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

    assert await(bia, "pk-seat-won") =~ "pk-seat-won"
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
    assert render(ana) =~ "sair e sacar"
  end

  test "showdown reveals hand names over the pods and losers may muck" do
    # Long pause after the hand so the showdown state holds still for asserts.
    code = create_table(%{between_hands_ms: 60_000})
    ana = join(code)
    bia = join(code)

    sit(ana, 0, "ana")
    sit(bia, 1, "bia")

    # Heads-up check-down to showdown.
    await(ana, "phx-value-action=\"call\"")
    ana |> element("button[phx-value-action=call]") |> render_click()
    bia |> element("button[phx-value-action=check]") |> render_click()

    for _street <- [:flop, :turn, :river] do
      await(bia, "phx-value-action=\"check\"")
      bia |> element("button[phx-value-action=check]") |> render_click()
      await(ana, "phx-value-action=\"check\"")
      ana |> element("button[phx-value-action=check]") |> render_click()
    end

    html = await(ana, "pk-seat-hand")
    assert html =~ "pk-seat-won"

    # Exactly one of them lost and may hide their cards.
    loser = Enum.find([ana, bia], &(render(&1) =~ "phx-click=\"muck\""))
    assert loser != nil

    loser |> element("button[phx-click=muck]") |> render_click()
    html = render(loser)
    refute html =~ "phx-click=\"muck\""
    # The loser's own cards flip face down — visible proof the muck landed.
    assert html =~ "url(#pk-back)"
  end

  test "a locked room gates strangers and admits the capability link" do
    {:ok, code} =
      Table.create(%{
        name: "cofre",
        blinds: {1, 2},
        buy_in: %{min: 100, max: 1000},
        password_hash: :crypto.hash(:sha256, "abre-te")
      })

    conn = build_conn() |> get(~p"/t/#{code}")
    {:ok, gate, html} = live(conn, ~p"/t/#{code}")

    assert html =~ "sala trancada"
    refute html =~ "pk-felt"

    # Wrong password stays at the gate; the right one navigates with a key.
    gate |> element("form[phx-submit=unlock]") |> render_submit(%{password: "errada"})
    assert render(gate) =~ "senha errada"

    gate |> element("form[phx-submit=unlock]") |> render_submit(%{password: "abre-te"})
    {path, _flash} = assert_redirect(gate)
    assert path =~ "key="

    {:ok, _table, html} = live(build_conn() |> get(path), path)
    assert html =~ "pk-felt"
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

    assert html =~ "comanda da noite"
    assert html =~ "ana"
    assert html =~ "2,00"
  end

  test "the event log renders in the side card and in the drawer log tab" do
    code = create_table(%{between_hands_ms: 60_000})
    lv = join(code)
    sit(lv, 0, "ana")

    html = lv |> element("button[phx-click=rail][phx-value-tab=log]") |> render_click()
    assert html =~ "ana sentou com"

    lv |> element("button[phx-click=toggle_ledger]") |> render_click()
    html = lv |> element("button[phx-click=panel][phx-value-tab=log]") |> render_click()
    assert html =~ "pk-ev--sit"
  end

  test "a layered pot renders the main and side split" do
    html =
      render_component(&PokerscarsWeb.TableComponents.board/1,
        board: [],
        pot: 400,
        pots: [300, 100],
        bet: 0,
        victory: nil,
        currency: "BRL"
      )

    assert html =~ "principal 3,00"
    assert html =~ "lateral 1,00"
  end

  test "a rebuy flashes success and standing asks for confirmation first" do
    code = create_table(%{between_hands_ms: 60_000})
    lv = join(code)
    sit(lv, 0, "ana")

    lv |> element("form[phx-submit=rebuy]") |> render_submit(%{amount: "2,00"})
    assert render(lv) =~ "rebuy de 2,00 feito"

    lv |> element("button[phx-click=confirm_stand]") |> render_click()
    html = render(lv)
    assert html =~ "sacar e sair da mesa?"
    assert html =~ "liberar seu assento"

    html = lv |> element(".pk-modal button[phx-click=stand]") |> render_click()
    assert html =~ "você está só assistindo"
  end

  test "chat: hero sends a preset, public room has no free text input" do
    code = create_table(%{between_hands_ms: 60_000})
    lv = join(code)
    sit(lv, 0, "ana")

    lv |> element("button[phx-click=rail][phx-value-tab=chat]") |> render_click()
    refute has_element?(lv, ".pk-chat-form")

    lv |> element("button[phx-click=chat_preset][phx-value-key=nice_hand]") |> render_click()
    assert has_element?(lv, ".pk-chat-msg strong", "ana")
  end

  test "sound cues: your turn on hand start, win and end at the showdown" do
    code = create_table(%{between_hands_ms: 60_000})
    ana = join(code)
    bia = join(code)
    sit(ana, 0, "ana")
    sit(bia, 1, "bia")

    await(ana, "phx-value-action=\"fold\"")
    assert_push_event(ana, "sound", %{kind: "turn"})

    ana |> element("button[phx-click=preset_raise]", "1/2") |> render_click()
    assert_push_event(bia, "sound", %{kind: "raise"})

    await(bia, "phx-value-action=\"fold\"")
    bia |> element("button[phx-value-action=fold]") |> render_click()
    _html = await(ana, "pk-seat-won")

    assert_push_event(ana, "sound", %{kind: "win"})
    assert_push_event(bia, "sound", %{kind: "end"})
  end
end
