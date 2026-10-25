defmodule Gallformers.Repo.Migrations.RekeyHostRangeToTaxa do
  @moduledoc """
  Re-keys `host_range` to taxa (`9449` §1 "Kept, re-keyed"; Task 15).

  `host_range` is keyed by `species_id` (a foreign key to `species`), which
  today's code still reads and writes. Plant taxa keep their species IDs, but
  a genus taxon that replaces a genus placeholder ("Quercus spp.") has a new
  ID with no `species` row, so its range rows have nowhere to point.

  `taxon_id` is added beside `species_id` and filled by the catalog data
  migration (`Gallformers.CatalogMigration`): a plant's rows get its own ID
  (the same as `species_id`), a placeholder's rows get its genus taxon. The
  new code (`Gallformers.Catalog.potential_range/1`) reads `taxon_id` only.
  Rows written by today's code after the data migration have no `taxon_id`
  until the migration runs again (it always runs from a fresh production
  copy at cutover).

  When today's code goes (`8567` step 9), `species_id` is dropped and
  `taxon_id` becomes `NOT NULL` and part of the primary key.

  `host_range` is not audited: it is kept as it is, re-keyed.
  """
  use Ecto.Migration

  def change do
    alter table(:host_range) do
      add :taxon_id, references(:taxa, type: :bigint, on_delete: :nilify_all)
    end

    create index(:host_range, [:taxon_id], where: "taxon_id IS NOT NULL")
  end
end
