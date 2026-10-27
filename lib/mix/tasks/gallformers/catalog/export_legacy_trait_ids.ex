defmodule Mix.Tasks.Gallformers.Catalog.ExportLegacyTraitIds do
  use Boundary, check: [in: false, out: false]

  @moduledoc """
  Writes `priv/catalog_migration/legacy_trait_ids.csv`
  (`table,old_id,trait,value`): every row of today's Trait vocabulary
  tables (`color`, `shape`, `form`, `plant_part`, ...) with the Trait value
  it became, so old ID-tool bookmarks, which hold those row IDs, keep
  working once the old tables are gone (`803b` §3;
  `Gallformers.CatalogMigration.TraitIdExport`). Values the vocabulary
  lacks are listed, not written.

  Run it once against a database with **production's** vocabulary rows
  (their IDs are what bookmarks hold), then commit the file. It only reads
  the database, and starts nothing but the repo (no Oban, no endpoint), so
  an old-schema copy works:

      MIX_ENV=dev PGDATABASE=gallformers_dev mix gallformers.catalog.export_legacy_trait_ids

  ## Options

    * `--output PATH` — write elsewhere (default the shipped file).
  """
  use Mix.Task

  alias Gallformers.CatalogMigration.TraitIdExport

  @shortdoc "Writes legacy_trait_ids.csv from the old vocabulary tables (read-only)"

  @default_output "priv/catalog_migration/legacy_trait_ids.csv"

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [output: :string])
    path = Keyword.get(opts, :output, @default_output)

    start_repo()
    {mapped, unmapped} = TraitIdExport.write(path)

    Mix.shell().info("Wrote #{length(mapped)} rows to #{path}")

    if unmapped != [] do
      left_out = Enum.map_join(unmapped, ", ", &"#{&1.table} #{&1.old_id} #{inspect(&1.value)}")
      Mix.shell().info("Not in the vocabulary (left out): #{left_out}")
    end
  end

  # The repo only: this task reads, and must not start Oban's queues on the
  # database it reads.
  defp start_repo do
    Mix.Task.run("app.config")
    if Logger.compare_levels(Logger.level(), :info) == :lt, do: Logger.configure(level: :info)
    {:ok, _apps} = Application.ensure_all_started(:ecto_sql)

    case Gallformers.Repo.start_link(pool_size: 2) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end
