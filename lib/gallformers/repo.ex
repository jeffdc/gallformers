defmodule Gallformers.Repo do
  use Boundary, deps: [], exports: :all

  use Ecto.Repo,
    otp_app: :gallformers,
    adapter: Ecto.Adapters.Postgres

  alias Gallformers.Repo.DevShell

  # Development requires the dev shell's Postgres (Gallformers.Repo.DevShell).
  @impl true
  def init(_context, config), do: {:ok, DevShell.check!(config, System.get_env("PGPORT"))}
end
