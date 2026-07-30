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
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PokerscarsWeb do
    pipe_through :browser

    get "/prefs", PrefsController, :update

    live_session :main, on_mount: PokerscarsWeb.RestoreLocale do
      live "/", LobbyLive
      live "/t/:code", TableLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", PokerscarsWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:pokerscars, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PokerscarsWeb.Telemetry
      get "/kill-bots/:code", PokerscarsWeb.ChaosController, :kill_bots
    end
  end
end
