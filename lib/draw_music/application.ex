defmodule DrawMusic.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DrawMusicWeb.Telemetry,
      DrawMusic.Repo,
      {DNSCluster, query: Application.get_env(:draw_music, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DrawMusic.PubSub},
      # Start a worker by calling: DrawMusic.Worker.start_link(arg)
      # {DrawMusic.Worker, arg},
      # Start to serve requests, typically the last entry
      DrawMusicWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DrawMusic.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DrawMusicWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
