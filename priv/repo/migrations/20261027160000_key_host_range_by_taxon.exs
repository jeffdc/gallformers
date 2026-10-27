defmodule Gallformers.Repo.Migrations.KeyHostRangeByTaxon do
  @moduledoc """
  Keys `host_range` by `(taxon_id, place_id)` (`a856` Task 8): the taxonomy
  admin writes Host ranges by taxon, and a plant created after the data
  migration has no `species` row, so `species_id` becomes nullable.

  The primary key `(species_id, place_id)` goes; each key is unique where it
  is set (NULLs are distinct): `(species_id, place_id)` for today's code,
  which still writes by species until it is deleted, and `(taxon_id,
  place_id)` for the new back-end. A row needs one of the two.

  Rows the data migration moved from two genus placeholders to the same
  genus can give that genus a place twice; one row per place keeps the
  genus key (the plant's own row first, then native, then exact, then the
  lower species ID) and the others lose it, keeping their species key.

  When today's code goes, `species_id` is dropped and `(taxon_id,
  place_id)` becomes the primary key.
  """
  use Ecto.Migration

  def up do
    execute("ALTER TABLE host_range DROP CONSTRAINT host_range_pkey")
    execute("ALTER TABLE host_range ALTER COLUMN species_id DROP NOT NULL")

    create unique_index(:host_range, [:species_id, :place_id])

    execute("""
    UPDATE host_range hr SET taxon_id = NULL
    FROM (
      SELECT species_id, place_id FROM (
        SELECT species_id, place_id,
               row_number() OVER (
                 PARTITION BY taxon_id, place_id
                 ORDER BY (species_id = taxon_id) DESC, (distribution_type = 'native') DESC,
                          (precision = 'exact') DESC, species_id
               ) AS n
        FROM host_range WHERE taxon_id IS NOT NULL
      ) ranked
      WHERE n > 1
    ) dup
    WHERE hr.species_id = dup.species_id AND hr.place_id = dup.place_id
    """)

    drop index(:host_range, [:taxon_id], where: "taxon_id IS NOT NULL")
    create unique_index(:host_range, [:taxon_id, :place_id])

    create constraint(:host_range, :host_range_keyed,
             check: "species_id IS NOT NULL OR taxon_id IS NOT NULL"
           )
  end

  def down do
    drop constraint(:host_range, :host_range_keyed)
    drop index(:host_range, [:taxon_id, :place_id])
    create index(:host_range, [:taxon_id], where: "taxon_id IS NOT NULL")

    execute("DELETE FROM host_range WHERE species_id IS NULL")
    drop index(:host_range, [:species_id, :place_id])
    execute("ALTER TABLE host_range ALTER COLUMN species_id SET NOT NULL")
    execute("ALTER TABLE host_range ADD PRIMARY KEY (species_id, place_id)")
  end
end
