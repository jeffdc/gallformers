defmodule Gallformers.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GallformersWeb.Telemetry,
      Gallformers.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:gallformers, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:gallformers, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Gallformers.PubSub},
      # Image audit cache for orphan detection
      Gallformers.Images.AuditCache,
      # Start to serve requests, typically the last entry
      GallformersWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Gallformers.Supervisor]

    # Attach request logger telemetry handler (must happen after app starts)
    Gallformers.RequestLogger.attach()

    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GallformersWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations? do
    # Skip migrations by default since we use an existing database managed by Prisma.
    # Set RUN_MIGRATIONS=true to explicitly enable Ecto migrations.
    System.get_env("RUN_MIGRATIONS") != "true"
  end
end
