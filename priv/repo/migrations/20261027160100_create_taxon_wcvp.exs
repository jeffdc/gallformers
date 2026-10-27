defmodule Gallformers.Repo.Migrations.CreateTaxonWcvp do
  @moduledoc """
  A plant taxon's WCVP link and range review state, keyed by taxon
  (`a856` Task 8): `wcvp_id` and `powo_id`, `wcvp_match_status`
  (`no_match` / `ignored`), `range_confirmed` and `wcvp_synced_at`. Today's
  `host_traits` holds the same by `species_id`, which a plant created after
  the data migration does not have; `host_traits` stays for today's code
  until it is deleted.

  Filled here from `host_traits` for the plants already migrated (a plant
  taxon keeps its species ID), and by the catalog data migration
  (`Gallformers.CatalogMigration.Taxa`) on every run. Audited; the row
  deletes with its taxon.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  def up do
    create table(:taxon_wcvp, primary_key: false) do
      add :taxon_id, references(:taxa, type: :bigint, on_delete: :delete_all), primary_key: true
      add :wcvp_id, :string
      add :powo_id, :string
      add :wcvp_match_status, :string
      add :range_confirmed, :boolean, null: false, default: false
      add :wcvp_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:taxon_wcvp, [:wcvp_id])
    create index(:taxon_wcvp, [:wcvp_match_status])

    create constraint(:taxon_wcvp, :taxon_wcvp_match_status_check,
             check: "wcvp_match_status IN ('no_match', 'ignored')"
           )

    # Before the audit trigger: a migration writes no audit record.
    execute("""
    INSERT INTO taxon_wcvp (taxon_id, wcvp_id, powo_id, wcvp_match_status, range_confirmed,
                            wcvp_synced_at, inserted_at, updated_at)
    SELECT ht.species_id, NULLIF(ht.wcvp_id, ''), NULLIF(ht.powo_id, ''), NULLIF(ht.wcvp_match_status, ''),
           COALESCE(ht.range_confirmed, false), ht.wcvp_synced_at,
           now()::timestamp(0), now()::timestamp(0)
    FROM host_traits ht JOIN taxa t ON t.id = ht.species_id
    """)

    Audit.track_table("taxon_wcvp", primary_key_columns: ["taxon_id"])
  end

  def down do
    Audit.untrack_table("taxon_wcvp")
    drop table(:taxon_wcvp)
  end
end
