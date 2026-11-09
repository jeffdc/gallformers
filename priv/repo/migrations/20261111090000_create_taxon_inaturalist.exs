defmodule Gallformers.Repo.Migrations.CreateTaxonInaturalist do
  @moduledoc """
  A taxon brought in from iNaturalist (matter `cb28`):

    * `taxon_inaturalist` — a taxon's iNaturalist taxon ID (`e1d2`'s
      mapping), one row per taxon, beside `taxon_wcvp`. Audited; the row
      deletes with its taxon. An iNaturalist taxon is linked to one of
      ours at most.
    * `taxa.origin` gains `inaturalist`: a plant added from iNaturalist.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  def up do
    create table(:taxon_inaturalist, primary_key: false) do
      add :taxon_id, references(:taxa, type: :bigint, on_delete: :delete_all), primary_key: true
      add :inat_id, :bigint, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:taxon_inaturalist, [:inat_id])

    Audit.track_table("taxon_inaturalist", primary_key_columns: ["taxon_id"])

    drop constraint(:taxa, :taxa_origin_check)

    create constraint(:taxa, :taxa_origin_check,
             check: "origin IN ('curated', 'powo', 'inaturalist')"
           )
  end

  def down do
    Carbonite.Migrations.insert_migration_transaction("drop_taxon_inaturalist")
    execute "UPDATE taxa SET origin = 'powo' WHERE origin = 'inaturalist'"
    drop constraint(:taxa, :taxa_origin_check)
    create constraint(:taxa, :taxa_origin_check, check: "origin IN ('curated', 'powo')")

    Audit.untrack_table("taxon_inaturalist")
    drop table(:taxon_inaturalist)
  end
end
