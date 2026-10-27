defmodule Gallformers.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  use Boundary,
    top_level?: true,
    deps: [Gallformers, GallformersWeb],
    exports: :all

  use Application

  alias Gallformers.Repo

  @impl true
  def start(_type, _args) do
    children = [
      GallformersWeb.Telemetry,
      Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:gallformers, :ecto_repos), skip: skip_migrations?()},
      {Oban, Application.fetch_env!(:gallformers, Oban)},
      Repo.WCVP,
      {DNSCluster, query: Application.get_env(:gallformers, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Gallformers.PubSub},
      # Stop VM if app becomes unresponsive so Fly restarts it
      Gallformers.HealthWatchdog,
      # Site-wide settings with persistent_term cache
      Gallformers.SiteSettings,
      # Start to serve requests, typically the last entry
      GallformersWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Gallformers.Supervisor]

    # Add file log handler if configured (production only, not preview deploys)
    Logger.add_handlers(:gallformers)

    # Attach structured request logging via LoggerJSON (replaces custom RequestLogger)
    LoggerJSON.Plug.attach("phoenix-request-logger", [:phoenix, :endpoint, :stop], :info)

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
    # Migrations are opt-in via RUN_MIGRATIONS=true (set in docker-entrypoint.sh).
    # Default off so `mix phx.server` doesn't auto-migrate the dev database.
    System.get_env("RUN_MIGRATIONS") != "true"
  end
end
