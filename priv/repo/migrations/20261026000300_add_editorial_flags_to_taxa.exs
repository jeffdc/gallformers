defmodule Gallformers.Repo.Migrations.AddEditorialFlagsToTaxa do
  @moduledoc """
  Adds the plant editorial flags to `taxa` (`803b` decision 6, Jeff
  2026-10-26): `datacomplete` (every gall known on the plant is in the
  database) and `abundance_id`, carried over from today's plant `species`
  rows by the catalog data migration (`Gallformers.CatalogMigration.Taxa`)
  and shown on the Host page. Editorial carry-overs like the Gall's own,
  set on plant taxa only.

  `taxa` is audited; its Carbonite trigger records every column (no
  filtered columns), so the new columns need nothing more.
  """
  use Ecto.Migration

  def change do
    alter table(:taxa) do
      add :datacomplete, :boolean, null: false, default: false
      add :abundance_id, references(:abundance, on_delete: :restrict)
    end

    create index(:taxa, [:abundance_id])
  end
end
