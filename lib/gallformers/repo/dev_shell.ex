defmodule Gallformers.Repo.DevShell do
  @moduledoc """
  Development's guard against the wrong Postgres. Development runs on the
  dev shell's Postgres (`scripts/dev-db`, `127.0.0.1:54317`), which the Nix
  dev shell selects through `PGHOST` and `PGPORT`. Outside the dev shell
  those are unset and the repos would fall back to whatever listens on
  `localhost:5432` (Postgres.app, say): a different server, often with
  databases of the same names and other contents.

  A repo configured with `require_dev_shell: true` (`config/dev.exs`)
  refuses to start without `PGPORT`. Only starting a repo checks, so `mix
  compile`, `credo` and `format` run anywhere.
  """

  @doc """
  Returns `config` without `:require_dev_shell`; raises when it requires the
  dev shell and `pgport` (the `PGPORT` environment variable) is unset.
  """
  @spec check!(keyword(), String.t() | nil) :: keyword()
  def check!(config, pgport) do
    {required?, config} = Keyword.pop(config, :require_dev_shell, false)

    if required? and pgport in [nil, ""] do
      raise """
      PGPORT is not set, so #{config[:database]} would be read from whatever \
      Postgres listens on localhost:5432, not the dev Postgres.

      Run inside the dev shell: `direnv allow` in the repo (or `nix develop`), \
      then `make db-start`. Or point at a server on purpose with PGHOST and PGPORT, \
      e.g. PGHOST=127.0.0.1 PGPORT=54317.
      """
    end

    config
  end
end
