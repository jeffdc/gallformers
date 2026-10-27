defmodule Mix.Tasks.Gallformers.Catalog.Migrate do
  use Boundary, check: [in: false, out: false]

  @moduledoc """
  Runs the catalog data migration (`Gallformers.CatalogMigration`): rebuilds
  the new back-end's tables from today's and prints the report (counts
  reconciled, duplicate taxon keys, gall names needing review or not read,
  curated decisions pending).

  Run it only against a **copy** of production (`make experiment-db`) or the
  test database (`make test-db` converts the test seeds with it), with
  `MIX_ENV` set explicitly; the task refuses to run without it. It rebuilds
  the new tables in one transaction and never touches `replay_log` or the
  old tables (except rewriting the keys' couplets as `keys.csv` decides),
  but it does empty the new tables it fills (and the import tables) each
  time.

  ## Usage

      MIX_ENV=dev mix gallformers.catalog.migrate
      MIX_ENV=dev mix gallformers.catalog.migrate --skip-pending --reports docs/plans/catalog --no-s3
      MIX_ENV=dev mix gallformers.catalog.migrate --name-suffixes path/to/name_suffixes.csv
      MIX_ENV=test mix gallformers.catalog.migrate --curated test/support/fixtures/catalog_migration --no-s3

  ## Options

    * `--reports DIR` — write the curation worksheets
      (`non_galls_report.csv`, `ranges_report.csv`, `aliases_report.csv`,
      `keys_report.csv`) to `DIR`, also when the run stops. Fill in a
      worksheet's `decision` column and save it as the decision file in
      `priv/catalog_migration/`. (`taxon_merges.csv` and `kingdoms.csv`
      there have no worksheet; their rows are written by hand.)
    * `--skip-pending` — lenient: rows of the curated inputs awaiting a
      decision (and duplicate taxon keys) are skipped and reported instead
      of stopping the run. For runs before curation is done; the production
      run (`Gallformers.Release.migrate_catalog/0`) is always strict.
    * `--name-suffixes PATH` — another name-suffix mapping file.
    * `--curated DIR` — read the curated inputs (`non_galls.csv`,
      `range_decisions.csv`, `aliases.csv`, `keys.csv`, `taxon_merges.csv`,
      `kingdoms.csv`) and `name_suffixes.csv` from `DIR` instead; a file
      missing there is read from `priv/catalog_migration/` as usual
      (`--name-suffixes` wins over `DIR/name_suffixes.csv`). `make test-db`
      uses it to convert the test seeds with their own decisions
      (`test/support/fixtures/catalog_migration/`): the shipped files hold
      production IDs.
    * `--no-s3` — store nothing in S3 (rehearsals on a local copy): the
      Gallformers notes are not uploaded to the real private bucket.

  The writes are audited as the system actor `"catalog_migration"`. In
  production use `Gallformers.Release.migrate_catalog/0` instead.
  """
  use Mix.Task

  alias Gallformers.CatalogMigration
  alias Gallformers.CatalogMigration.Curated
  alias Gallformers.CatalogMigration.NameSuffixes
  alias Gallformers.CatalogMigration.Report

  @shortdoc "Rebuilds the new catalog tables from today's (run against a copy)"

  @impl Mix.Task
  def run(args) do
    {opts, _rest} =
      OptionParser.parse!(args,
        strict: [
          name_suffixes: :string,
          curated: :string,
          reports: :string,
          skip_pending: :boolean,
          no_s3: :boolean
        ]
      )

    if System.get_env("MIX_ENV") in [nil, ""] do
      Mix.raise(
        "Set MIX_ENV explicitly (e.g. MIX_ENV=dev) and point it at a copy of production: " <>
          "this rebuilds the new catalog tables."
      )
    end

    :ok = configure_storage(opts)
    Mix.Task.run("app.start")

    curated = if dir = opts[:curated], do: curated_paths(dir), else: []

    run_opts =
      [pending: if(opts[:skip_pending], do: :skip, else: :fail)] ++
        Keyword.merge(curated, Keyword.take(opts, [:name_suffixes]))

    case CatalogMigration.run(run_opts) do
      {:ok, report} ->
        print(report, opts[:reports])

      {:error, {:pending_decisions, report}} ->
        print(report, opts[:reports])

        Mix.raise(
          "Catalog migration stopped, nothing written: #{length(report.pending)} curated " <>
            "decisions pending, #{length(report.duplicates)} duplicate taxon keys (see above)."
        )

      {:error, reason} ->
        Mix.raise("Catalog migration not run: #{inspect(reason)}")
    end
  end

  @doc """
  With `no_s3: true`, turns S3 off for this run (`s3_enabled: false`), so a
  rehearsal stores nothing in the real private bucket; Gallformers notes
  are still written to the database (their text is the note document's
  item). The private bucket goes through its S3 adapter, which S3 turned
  off makes a no-op, whatever adapter is configured: `MIX_ENV=test`
  configures the in-memory stub, which exists only in a test run.
  """
  @spec configure_storage(keyword()) :: :ok
  def configure_storage(opts) do
    if opts[:no_s3] do
      Application.put_env(:gallformers, :s3_enabled, false)

      private = Application.get_env(:gallformers, :private_storage, [])

      Application.put_env(
        :gallformers,
        :private_storage,
        Keyword.put(private, :adapter, Gallformers.Storage.Private.S3Adapter)
      )
    end

    :ok
  end

  @doc """
  The input files `--curated DIR` names, as `CatalogMigration.run/1`
  options: each curated input and `:name_suffixes` read from
  `DIR/<input>.csv` when that file exists, else the shipped file.
  """
  @spec curated_paths(String.t()) :: keyword(String.t())
  def curated_paths(dir) do
    shipped =
      [name_suffixes: NameSuffixes.default_path()] ++
        for input <- Curated.inputs(), do: {input, Curated.default_path(input)}

    for {input, default} <- shipped do
      path = Path.join(dir, "#{input}.csv")
      {input, if(File.exists?(path), do: path, else: default)}
    end
  end

  defp print(report, dir) do
    Mix.shell().info(Report.format(report))

    if dir do
      for path <- Report.write_curation(report, dir), do: Mix.shell().info("Wrote #{path}")
    end
  end
end
