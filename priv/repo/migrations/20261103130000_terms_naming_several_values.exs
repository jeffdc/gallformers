defmodule Gallformers.Repo.Migrations.TermsNamingSeveralValues do
  @moduledoc """
  Terms that name several values (matter d213, Jeff 2026-11-03): a term
  is placed under one category, or under each value its words name
  ("green-yellow" → green and yellow; "protruding from both sides" →
  upper leaf and lower leaf), however it was placed. There is no list of
  exceptions.

    * `trait_term_mappings`: the check `trait_term_mappings_one_category`
      (a second category only on a seeded row with a rule) goes. A placed
      term still has at least one category and no candidates
      (`trait_term_mappings_status_check`); that each is a value of the
      term's Trait, and that none repeats, is the changeset's
      (`Gallformers.Catalog.Vocab.TraitTermMapping`).
    * `pending_trait_terms`: a waiting use is settled under the categories
      its question placed the term under, so `settled_category` (one
      value) becomes `settled_categories` (a list, empty when settled as
      text or still waiting). Rows settled under a category keep it as
      their one category.

  Down puts the one-category check back, refused while a term holds
  several categories, and keeps a waiting use's first category.
  """
  use Ecto.Migration

  def up do
    drop constraint(:trait_term_mappings, :trait_term_mappings_one_category)

    # The pending table is audited: the data change is recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("terms_naming_several_values",
      meta: meta("terms_naming_several_values")
    )

    drop constraint(:pending_trait_terms, :pending_trait_terms_settled_as_check)
    drop constraint(:pending_trait_terms, :pending_trait_terms_settled_check)

    alter table(:pending_trait_terms) do
      add :settled_categories, {:array, :text}, null: false, default: []
    end

    flush()

    execute """
    UPDATE pending_trait_terms SET settled_categories = ARRAY[settled_category]
    WHERE settled_category IS NOT NULL
    """

    alter table(:pending_trait_terms) do
      remove :settled_category
    end

    create constraint(:pending_trait_terms, :pending_trait_terms_settled_as_check,
             check: """
             (settled_at IS NULL AND settled_as IS NULL AND cardinality(settled_categories) = 0)
             OR (settled_at IS NOT NULL AND cardinality(settled_categories) > 0
                 AND settled_as = 'category')
             OR (settled_at IS NOT NULL AND cardinality(settled_categories) = 0
                 AND settled_as IN ('no_fit', 'kept'))
             """
           )
  end

  def down do
    Carbonite.Migrations.insert_migration_transaction("terms_naming_one_value",
      meta: meta("terms_naming_one_value")
    )

    drop constraint(:pending_trait_terms, :pending_trait_terms_settled_as_check)

    alter table(:pending_trait_terms) do
      add :settled_category, :text
    end

    flush()

    execute "UPDATE pending_trait_terms SET settled_category = settled_categories[1]"

    alter table(:pending_trait_terms) do
      remove :settled_categories
    end

    create constraint(:pending_trait_terms, :pending_trait_terms_settled_check,
             check: "settled_category IS NULL OR settled_at IS NOT NULL"
           )

    create constraint(:pending_trait_terms, :pending_trait_terms_settled_as_check,
             check: """
             (settled_at IS NULL AND settled_as IS NULL)
             OR (settled_at IS NOT NULL AND settled_category IS NOT NULL AND settled_as = 'category')
             OR (settled_at IS NOT NULL AND settled_category IS NULL AND settled_as IN ('no_fit', 'kept'))
             """
           )

    create constraint(:trait_term_mappings, :trait_term_mappings_one_category,
             check: "cardinality(categories) <= 1 OR (placed_by = 'seed' AND rule IS NOT NULL)"
           )
  end

  # The audit record a data change in a migration needs: an actor and an
  # operation (`transactions_meta_attribution`).
  defp meta(name),
    do: %{actor: %{type: "system", name: "migration"}, operation: "migration.#{name}"}
end
