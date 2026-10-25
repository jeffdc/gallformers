defmodule Gallformers.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  use Boundary,
    deps: [Gallformers.Audit, Gallformers.CatalogMigration, Gallformers.Import, Gallformers.Repo],
    exports: :all

  alias Gallformers.Audit.Actor
  alias Gallformers.CatalogMigration
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.Import

  @app :gallformers

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Runs the catalog data migration (`Gallformers.CatalogMigration`) and
  prints its report: the production entry point, run as its own step in
  the maintenance window after the release's schema migrations — never at
  boot (`b5bd` M0, M6):

      bin/gallformers eval "Gallformers.Release.migrate_catalog()"

  Only the repo and the S3 client are started (not the endpoint, Oban or
  the health watchdog). Returns the report, or raises.
  """
  @spec migrate_catalog() :: Report.t()
  def migrate_catalog do
    # Strict: a curated row awaiting a decision, or a duplicate taxon key,
    # stops the run with nothing written. There is no lenient mode here.
    case with_storage(fn -> CatalogMigration.run(pending: :fail) end) do
      {:ok, report} ->
        IO.puts(Report.format(report))
        report

      {:error, {:pending_decisions, report}} ->
        IO.puts(Report.format(report))
        raise "Catalog migration stopped, nothing written: curated decisions pending (see above)"

      {:error, reason} ->
        raise "Catalog migration not run: #{inspect(reason)}"
    end
  end

  @doc """
  On **preview**, at cutover (`b5bd` M6): exports the whole replay log —
  the backscan's batches, queue decisions and taxonomy edits — to a file
  in the private bucket, and prints its key:

      bin/gallformers eval "Gallformers.Release.export_replay_log()"

  Returns the key. Run it after the edit freeze, once preview's last
  decision is made.
  """
  @spec export_replay_log() :: String.t()
  def export_replay_log do
    case with_storage(&Import.export_replay_log/0) do
      {:ok, %{key: key, count: count}} ->
        IO.puts("Exported #{count} replay-log entries to #{key} (private bucket)")
        key

      {:error, reason} ->
        raise "Replay log not exported: #{inspect(reason)}"
    end
  end

  @doc """
  On **production**, at cutover (`b5bd` M6), after `migrate_catalog/0`:
  replays the replay log exported from preview (`export_replay_log/0`)
  as the system actor `"replay"`:

      bin/gallformers eval 'Gallformers.Release.replay_log("replay/replay_log-....json")'

  Prints and returns how many entries were replayed; raises naming the
  first entry that could not be. Entries already done are skipped, so a
  stopped replay can be fixed and run again.
  """
  @spec replay_log(String.t()) :: non_neg_integer()
  def replay_log(key) when is_binary(key) do
    case with_storage(fn -> Import.replay_exported(Actor.system("replay"), key) end) do
      {:ok, count} ->
        IO.puts("Replayed #{count} entries from #{key}")
        count

      {:error, reason} ->
        raise "Replay stopped: #{inspect(reason)}"
    end
  end

  # Runs `fun` with the repo and the S3 client started (not the endpoint,
  # Oban or the health watchdog): notes, packages and replay files live in
  # the private bucket.
  defp with_storage(fun) do
    load_app()
    for app <- [:hackney, :ex_aws], do: {:ok, _} = Application.ensure_all_started(app)

    {:ok, result, _apps} =
      Ecto.Migrator.with_repo(Gallformers.Repo, fn _repo -> fun.() end, pool_size: 2)

    result
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
