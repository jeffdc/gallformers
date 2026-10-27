defmodule Gallformers.Repo.Migrations.AddDefaultSourceToGalls do
  @moduledoc """
  Adds `galls.default_source_id` (`9449` §4; `803b` decision 3, Jeff
  2026-10-26): the Source the Gall page leads with — today's
  `species_source.useasdefault` row, a citation or the Gallformers note
  alike. An editorial carry-over, nullable, set by the catalog data
  migration (`Gallformers.CatalogMigration.Galls`).

  `galls` is audited; its Carbonite trigger records every column (no
  filtered columns), so the new column needs nothing more.
  """
  use Ecto.Migration

  def change do
    alter table(:galls) do
      add :default_source_id, references(:source, on_delete: :restrict)
    end

    create index(:galls, [:default_source_id])
  end
end
