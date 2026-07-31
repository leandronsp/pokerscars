defmodule PokerscarsWeb.Router do
  use PokerscarsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PokerscarsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PokerscarsWeb.Plugs.EnsurePlayerId
    plug PokerscarsWeb.Plugs.SetLocale
    plug :put_og_image
  end

  # The share card needs an absolute URL built from how the visitor reached
  # us (ngrok today, a domain tomorrow) — endpoint config knows localhost.
  defp put_og_image(conn, _opts) do
    proto =
      case get_req_header(conn, "x-forwarded-proto") do
        [proto | _rest] -> proto
        [] -> Atom.to_string(conn.scheme)
      end

    port = if conn.port in [80, 443], do: "", else: ":#{conn.port}"
    assign(conn, :og_image_url, "#{proto}://#{conn.host}#{port}/images/og.png")
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PokerscarsWeb do
    pipe_through :browser

    get "/prefs", PrefsController, :update

    live_session :main, on_mount: PokerscarsWeb.RestoreLocale do
      live "/", LobbyLive
      live "/termos", TermsLive
      live "/t/:code", TableLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", PokerscarsWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:pokerscars, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    pipeline :dev_auth do
      plug :dev_basic_auth
    end

    scope "/dev" do
      pipe_through [:browser, :dev_auth]

      live_dashboard "/dashboard", metrics: PokerscarsWeb.Telemetry
      get "/kill-bots/:code", PokerscarsWeb.ChaosController, :kill_bots
    end

    # The dev tools ride the same public tunnel as the app, so they are
    # fenced by DEV_PASSWORD. No password set = no dev routes, fail closed.
    defp dev_basic_auth(conn, _opts) do
      case System.get_env("DEV_PASSWORD") do
        nil -> conn |> Plug.Conn.send_resp(404, "not found") |> Plug.Conn.halt()
        password -> Plug.BasicAuth.basic_auth(conn, username: "dev", password: password)
      end
    end
  end
end
