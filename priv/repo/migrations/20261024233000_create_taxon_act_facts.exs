defmodule Gallformers.Repo.Migrations.CreateTaxonActFacts do
  @moduledoc """
  Creates the taxonomic-act Fact detail tables (`9449` §3, Task 7), owned by
  `Gallformers.Taxa`: `placement_facts`, `name_facts`, `synonymy_facts`,
  `split_facts` (with `split_fact_daughters`) and `common_name_facts`. Each
  is keyed by `fact_id` and unique on its kind's natural key. All audited.

  Also gives `attributions` two per-statement fields the contract's acts
  carry (`priv/import/schema/taxonomy.schema.json`): `status_as_written`
  (any act: "syn. nov.", "comb. nov.") and `authorship_as_written` (a name
  act). They are each Source's own wording, so they live on the attribution,
  not in the Fact's natural key — as `when_as_written` does for occurrences.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  @ranks ~w(kingdom subkingdom phylum subphylum class subclass infraclass
            superorder order suborder infraorder superfamily
            family subfamily tribe subtribe genus subgenus section
            species subspecies variety form)

  @fact_pk ["fact_id"]

  def up do
    alter table(:attributions) do
      add :status_as_written, :text
      add :authorship_as_written, :text
    end

    # Placement: the taxon sits under the parent. Natural key taxon + parent;
    # Facts for one taxon compete in the slot "taxon:<id>:placement".
    create table(:placement_facts, primary_key: false) do
      add :fact_id, references(:facts, on_delete: :restrict), primary_key: true
      add :taxon_id, references(:taxa, type: :bigint, on_delete: :restrict), null: false
      add :parent_id, references(:taxa, type: :bigint, on_delete: :restrict), null: false
    end

    create unique_index(:placement_facts, [:taxon_id, :parent_id])
    create index(:placement_facts, [:parent_id])

    create constraint(:placement_facts, :placement_facts_not_own_parent,
             check: "taxon_id <> parent_id"
           )

    Audit.track_table("placement_facts", primary_key_columns: @fact_pk)

    # Name: the taxon bears this name at this rank. Natural key taxon +
    # normalized name + rank; one taxon's names compete in "taxon:<id>:name".
    create table(:name_facts, primary_key: false) do
      add :fact_id, references(:facts, on_delete: :restrict), primary_key: true
      add :taxon_id, references(:taxa, type: :bigint, on_delete: :restrict), null: false
      # The name as first recorded; `normalized_name` is its key.
      add :name, :text, null: false
      add :normalized_name, :text, null: false
      add :rank, :text, null: false
    end

    create unique_index(:name_facts, [:taxon_id, :normalized_name, :rank])
    create constraint(:name_facts, :name_facts_rank_check, check: "rank IN (#{list(@ranks)})")
    create constraint(:name_facts, :name_facts_name_present, check: "normalized_name <> ''")

    Audit.track_table("name_facts", primary_key_columns: @fact_pk)

    # Synonymy: a name is a synonym of the accepted taxon. In phase 1 a
    # synonym is a name, not a taxon (it may be one of the accepted taxon's
    # own names), so the key is the synonym's normalized name + the accepted
    # taxon. What each Source's name resolved to is on its attribution names.
    create table(:synonymy_facts, primary_key: false) do
      add :fact_id, references(:facts, on_delete: :restrict), primary_key: true
      add :name, :text, null: false
      add :normalized_name, :text, null: false

      add :accepted_taxon_id, references(:taxa, type: :bigint, on_delete: :restrict),
        null: false
    end

    create unique_index(:synonymy_facts, [:normalized_name, :accepted_taxon_id])
    create index(:synonymy_facts, [:accepted_taxon_id])

    create constraint(:synonymy_facts, :synonymy_facts_name_present,
             check: "normalized_name <> ''"
           )

    Audit.track_table("synonymy_facts", primary_key_columns: @fact_pk)

    # Split: the taxon was divided into a set of daughters. The natural key is
    # the taxon + the set, held canonically as a sorted, distinct array (so
    # [b, a] and [a, b] are one key); `split_fact_daughters` holds the same
    # set as rows, giving each daughter a foreign key.
    execute("""
    CREATE FUNCTION taxa_sorted_distinct_ids(ids bigint[]) RETURNS boolean
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    AS $$ SELECT ids = ARRAY(SELECT DISTINCT id FROM unnest(ids) AS id ORDER BY id) $$
    """)

    create table(:split_facts, primary_key: false) do
      add :fact_id, references(:facts, on_delete: :restrict), primary_key: true
      add :taxon_id, references(:taxa, type: :bigint, on_delete: :restrict), null: false
      add :into_taxon_ids, {:array, :bigint}, null: false
    end

    create unique_index(:split_facts, [:taxon_id, :into_taxon_ids])

    create constraint(:split_facts, :split_facts_into_check,
             check: """
             cardinality(into_taxon_ids) >= 2
             AND taxa_sorted_distinct_ids(into_taxon_ids)
             AND NOT (taxon_id = ANY (into_taxon_ids))
             """
           )

    Audit.track_table("split_facts", primary_key_columns: @fact_pk)

    create table(:split_fact_daughters, primary_key: false) do
      add :fact_id, references(:split_facts, column: :fact_id, on_delete: :delete_all),
        primary_key: true

      add :taxon_id, references(:taxa, type: :bigint, on_delete: :restrict), primary_key: true
    end

    create index(:split_fact_daughters, [:taxon_id])

    Audit.track_table("split_fact_daughters", primary_key_columns: ["fact_id", "taxon_id"])

    # Common name: the taxon's organism is called this. Natural key taxon +
    # common name, ignoring case.
    create table(:common_name_facts, primary_key: false) do
      add :fact_id, references(:facts, on_delete: :restrict), primary_key: true
      add :taxon_id, references(:taxa, type: :bigint, on_delete: :restrict), null: false
      add :common_name, :text, null: false
    end

    create unique_index(:common_name_facts, ["taxon_id", "lower(common_name)"],
             name: :common_name_facts_taxon_id_common_name_index
           )

    create constraint(:common_name_facts, :common_name_facts_name_present,
             check: "common_name <> ''"
           )

    Audit.track_table("common_name_facts", primary_key_columns: @fact_pk)
  end

  def down do
    for table <-
          ~w(common_name_facts split_fact_daughters split_facts synonymy_facts name_facts placement_facts) do
      Audit.untrack_table(table)
      drop table(table)
    end

    execute("DROP FUNCTION taxa_sorted_distinct_ids(bigint[])")

    alter table(:attributions) do
      remove :status_as_written
      remove :authorship_as_written
    end
  end

  defp list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
