defmodule Pokerscars.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PokerscarsWeb.Telemetry,
      Pokerscars.Repo,
      {DNSCluster, query: Application.get_env(:pokerscars, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Pokerscars.PubSub},
      {Registry, keys: :unique, name: Pokerscars.Table.Registry},
      {DynamicSupervisor, name: Pokerscars.Table.Supervisor, strategy: :one_for_one},
      # Start to serve requests, typically the last entry
      PokerscarsWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pokerscars.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PokerscarsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
