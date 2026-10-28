defmodule Gallformers.Repo.WCVP do
  @moduledoc """
  Read-only Ecto repo for querying the WCVP Postgres database.

  This is a separate database on the same Postgres cluster containing WCVP
  (World Checklist of Vascular Plants) reference data from Kew Gardens. It is
  NOT managed by Ecto migrations — tables are created by the build task
  (`mix gallformers.wcvp.build_db`) and data is distributed via pg_dump/pg_restore.
  """
  use Ecto.Repo,
    otp_app: :gallformers,
    adapter: Ecto.Adapters.Postgres

  alias Gallformers.Repo.DevShell

  # Development requires the dev shell's Postgres (Gallformers.Repo.DevShell).
  @impl true
  def init(_context, config), do: {:ok, DevShell.check!(config, System.get_env("PGPORT"))}
end
