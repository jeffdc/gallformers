defmodule Gallformers.Repo.Migrations.AddLeafPlantPart do
  @moduledoc """
  `leaf` becomes a plant part value (matter d213, Jeff 2026-11-03): on the
  leaf, with no more precise location stated, or in no consistent location
  on it. The leaf values (upper leaf, lower leaf, leaf edge, leaf midrib,
  on leaf veins, between leaf veins, at leaf vein angles) are more precise
  forms of it (`Gallformers.Catalog.Vocab.TraitValue.leaf_values/0`); the
  petiole is not one.

  The leaf rule goes: the seeded term "on the leaf" (no side, vein or
  midrib stated), placed under upper leaf and lower leaf, is placed under
  `leaf` alone, with no rule. A term moved since it was seeded is left as
  it is. Galls' Facts are not converted.

  Only a database whose vocabulary is loaded changes. A fresh one gets
  `leaf`, last among the plant parts, and the term from `traits.json` when
  the vocabulary is loaded (`Gallformers.Catalog.Vocab.Loader`), so its
  values keep the order the committed file has.
  """
  use Ecto.Migration

  @definition "Galls are located on the leaf, with no more precise location stated, or in " <>
                "no consistent location on it."

  @leaf_rule "On the leaf, with no side, vein or midrib stated: the Gall is on both sides, " <>
               "so the term gives two Facts, upper leaf and lower leaf."

  def up do
    # Both tables are audited: the changes are recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("add_leaf_plant_part",
      meta: meta("add_leaf_plant_part")
    )

    flush()

    repo().query!(
      """
      INSERT INTO trait_values (trait, value, definition)
      SELECT 'plant_part', 'leaf', $1
      WHERE EXISTS (SELECT 1 FROM trait_values WHERE trait = 'plant_part')
      ON CONFLICT (trait, value) DO NOTHING
      """,
      [@definition]
    )

    repo().query!("""
    UPDATE trait_term_mappings
    SET categories = ARRAY['leaf'], rule = NULL,
        placed_at = date_trunc('second', now() AT TIME ZONE 'UTC')
    WHERE trait = 'plant_part' AND normalized_term = 'on the leaf' AND placed_by = 'seed'
      AND categories = ARRAY['upper leaf', 'lower leaf']
    """)
  end

  def down do
    Carbonite.Migrations.insert_migration_transaction("drop_leaf_plant_part",
      meta: meta("drop_leaf_plant_part")
    )

    flush()

    repo().query!(
      """
      UPDATE trait_term_mappings
      SET categories = ARRAY['upper leaf', 'lower leaf'], rule = $1,
          placed_at = date_trunc('second', now() AT TIME ZONE 'UTC')
      WHERE trait = 'plant_part' AND normalized_term = 'on the leaf' AND placed_by = 'seed'
        AND categories = ARRAY['leaf']
      """,
      [@leaf_rule]
    )

    # Refused while a Fact states `leaf` (`trait_facts.trait_value_id`).
    repo().query!("DELETE FROM trait_values WHERE trait = 'plant_part' AND value = 'leaf'")
  end

  # The audit record a data change in a migration needs: an actor and an
  # operation (`transactions_meta_attribution`).
  defp meta(name),
    do: %{actor: %{type: "system", name: "migration"}, operation: "migration.#{name}"}
end
