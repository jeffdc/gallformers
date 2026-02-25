defmodule Gallformers.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        GallformersWeb.Telemetry,
        Gallformers.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:gallformers, :ecto_repos), skip: skip_migrations?()}
      ] ++
        wcvp_repo_child_spec() ++
        [
          {DNSCluster, query: Application.get_env(:gallformers, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: Gallformers.PubSub},
          # Image audit cache for orphan detection
          Gallformers.Images.AuditCache,
          # Nightly analytics rollup and pruning
          Gallformers.Analytics.Rollup,
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

  defp wcvp_repo_child_spec do
    db_path = Application.get_env(:gallformers, Gallformers.Repo.WCVP)[:database]

    if db_path && File.exists?(db_path) do
      [Gallformers.Repo.WCVP]
    else
      []
    end
  end

  defp skip_migrations? do
    # Skip migrations by default since we use an existing database managed by Prisma.
    # Set RUN_MIGRATIONS=true to explicitly enable Ecto migrations.
    System.get_env("RUN_MIGRATIONS") != "true"
  end
end
