defmodule Gallformers.Repo.Migrations.CreateCatalogVocab do
  @moduledoc """
  Creates the Catalog's vocabularies (`9449` §4, Task 8), all audited:

    * `trait_values` — each Trait's allowed values with their definitions,
      unique on trait + value (from the contract's `traits.json`).
    * `trait_term_mappings` — common Source terms mapped onto values, or onto
      candidates to choose between by definition (`traits.json` `mappings`).
    * `generation_groups`, `generation_values` — named sets of generation
      values; a value is unique across groups, so it names its group
      (`8567` *Generation groups*).
    * `generation_group_taxa` — the taxa (any rank) each group applies to.

  These are system lists, filled by `Gallformers.Catalog.load_vocab/1`
  (`mix gallformers.catalog.load_vocab`), not by curators. Generation is not
  a Trait Fact (it identifies a Gall), so it has no `trait_values` rows.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  @traits ~w(detachable plant_part form shape color texture alignment walls cells season)

  def up do
    create table(:trait_values) do
      add :trait, :text, null: false
      add :value, :text, null: false
      add :definition, :text
    end

    create unique_index(:trait_values, [:trait, :value])
    create constraint(:trait_values, :trait_values_trait_check, check: "trait IN (#{list(@traits)})")
    create constraint(:trait_values, :trait_values_value_present, check: "value <> ''")

    Audit.track_table("trait_values")

    # A term maps onto values (`maps_to`), or onto candidates the producer
    # chooses between by definition (`candidates`, with the `rule`). Values
    # are held by name, as the contract writes them.
    create table(:trait_term_mappings) do
      add :trait, :text, null: false
      add :term, :text, null: false
      add :maps_to, {:array, :text}, null: false, default: []
      add :candidates, {:array, :text}, null: false, default: []
      add :rule, :text
    end

    create unique_index(:trait_term_mappings, [:trait, :term])

    create constraint(:trait_term_mappings, :trait_term_mappings_trait_check,
             check: "trait IN (#{list(["generation" | @traits])})"
           )

    create constraint(:trait_term_mappings, :trait_term_mappings_target_present,
             check: "cardinality(maps_to) > 0 OR cardinality(candidates) > 0"
           )

    Audit.track_table("trait_term_mappings")

    create table(:generation_groups) do
      add :name, :text, null: false
      add :description, :text
    end

    create unique_index(:generation_groups, [:name])
    Audit.track_table("generation_groups")

    create table(:generation_values) do
      add :group_id, references(:generation_groups, on_delete: :restrict), null: false
      add :value, :text, null: false
      add :definition, :text
      # The qualifier text derived Gall names use (`8567` rule 9), e.g.
      # "sexgen" for the sexual generation, as today's names have it.
      add :name_qualifier, :text, null: false
      # Order within the group.
      add :position, :integer, null: false
    end

    create unique_index(:generation_values, [:value])
    create index(:generation_values, [:group_id])
    create constraint(:generation_values, :generation_values_value_present, check: "value <> ''")

    Audit.track_table("generation_values")

    create table(:generation_group_taxa, primary_key: false) do
      add :group_id, references(:generation_groups, on_delete: :restrict), primary_key: true
      add :taxon_id, references(:taxa, type: :bigint, on_delete: :restrict), primary_key: true
    end

    create index(:generation_group_taxa, [:taxon_id])
    Audit.track_table("generation_group_taxa", primary_key_columns: ["group_id", "taxon_id"])
  end

  def down do
    for table <-
          ~w(generation_group_taxa generation_values generation_groups trait_term_mappings trait_values) do
      Audit.untrack_table(table)
      drop table(table)
    end
  end

  defp list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
