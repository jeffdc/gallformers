defmodule Gallformers.Repo.Migrations.CreateGallRangeAndConfirmation do
  use Gallformers.Migration

  def up do
    # 1. Create gall_range table
    create table(:gall_range, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :place_id, references(:place, on_delete: :delete_all), null: false
      add :precision, :string, null: false, default: "exact"
    end

    create unique_index(:gall_range, [:species_id, :place_id], name: :gall_range_pkey)
    create index(:gall_range, [:species_id], name: :idx_gall_range_species_id)
    create index(:gall_range, [:place_id], name: :idx_gall_range_place_id)

    # 2. Add confirmation fields to gall_traits
    alter table(:gall_traits) do
      add :range_confirmed, :boolean, default: false, null: false
      add :range_computed_at, :utc_datetime
    end

    # 3. Populate gall_range: for each gall, insert (union of host ranges) minus (exclusions)
    # This preserves all existing admin curation work
    execute """
    INSERT INTO gall_range (species_id, place_id, precision)
    SELECT DISTINCT gh.gall_species_id, hr.place_id, hr.precision
    FROM gallhost gh
    JOIN host_range hr ON hr.species_id = gh.host_species_id
    WHERE NOT EXISTS (
      SELECT 1 FROM gall_range_exclusion gre
      WHERE gre.species_id = gh.gall_species_id
      AND gre.place_id = hr.place_id
    )
    """

    # 4. Drop gall_range_exclusion table (data migrated to gall_range)
    drop table(:gall_range_exclusion)
  end

  def down do
    # Recreate gall_range_exclusion
    create table(:gall_range_exclusion, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :place_id, references(:place, on_delete: :delete_all), null: false
      add :precision, :string, null: false, default: "exact"
    end

    create unique_index(:gall_range_exclusion, [:species_id, :place_id],
      name: :gall_range_exclusion_pkey
    )

    create index(:gall_range_exclusion, [:species_id], name: :idx_gall_range_exclusion_species_id)
    create index(:gall_range_exclusion, [:place_id], name: :idx_gall_range_exclusion_place_id)

    # Remove confirmation fields
    alter table(:gall_traits) do
      remove :range_confirmed
      remove :range_computed_at
    end

    # Drop gall_range
    drop table(:gall_range)
  end
end
