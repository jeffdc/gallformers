defmodule Gallformers.Repo.Migrations.CreateTaxa do
  @moduledoc """
  Creates the new taxonomy storage (`9449` §3), owned by `Gallformers.Taxa`:
  `taxa`, `taxon_names`, `taxon_common_names`, `legacy_taxon_ids` and the
  `taxon_ancestry` closure table. All but `taxon_ancestry` (a read model
  rebuilt from `taxa.parent_id`) are audited.

  These sit beside today's `taxonomy` tables, which old code still reads
  until the public pages are re-pointed.

  Also adds the foreign key from `attribution_names.taxon_id` to `taxa`.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  # The contract's rank list (`priv/import/vocab/ranks.schema.json`) as of
  # this migration, highest first. `Gallformers.Taxa.Rank` reads the contract.
  @ranks ~w(kingdom subkingdom phylum subphylum class subclass infraclass
            superorder order suborder infraorder superfamily
            family subfamily tribe subtribe genus subgenus section
            species subspecies variety form)

  def up do
    create table(:taxa, primary_key: false) do
      # One sequence for Galls and taxa (`8567` rule 4). Migrated plants
      # insert their species IDs.
      add :id, :bigint, primary_key: true, default: fragment("nextval('entity_id_seq')")
      add :rank, :text, null: false
      add :parent_id, references(:taxa, type: :bigint, on_delete: :restrict)
      add :origin, :text, null: false
      # "Plantae" for plants; set for others when known.
      add :kingdom, :text

      timestamps(type: :utc_datetime)
    end

    create index(:taxa, [:parent_id])
    create constraint(:taxa, :taxa_rank_check, check: "rank IN (#{list(@ranks)})")
    create constraint(:taxa, :taxa_origin_check, check: "origin IN ('curated', 'powo')")
    create constraint(:taxa, :taxa_kingdom_present, check: "kingdom IS NULL OR kingdom <> ''")
    create constraint(:taxa, :taxa_not_own_parent, check: "parent_id IS NULL OR parent_id <> id")

    Audit.track_table("taxa")

    create table(:taxon_names) do
      add :taxon_id, references(:taxa, type: :bigint, on_delete: :delete_all), null: false
      add :name, :text, null: false
      # `Gallformers.Taxa.NameNormalizer.normalize/1` of `name`, for import
      # resolution. Recomputed by a data migration if the normalizer changes.
      add :normalized_name, :text, null: false
      add :status, :text, null: false
      # For a misapplied name: the usage meant, as written.
      add :sensu, :text
      # Null until phase 2 sources authorship.
      add :authorship, :text

      timestamps(type: :utc_datetime)
    end

    # Names are not globally unique (homonyms across kingdoms).
    create index(:taxon_names, [:normalized_name])

    create unique_index(:taxon_names, [:taxon_id],
             where: "status = 'accepted'",
             name: :taxon_names_one_accepted_index
           )

    create unique_index(:taxon_names, [:taxon_id, :normalized_name, :sensu],
             nulls_distinct: false,
             name: :taxon_names_taxon_id_normalized_name_sensu_index
           )

    create constraint(:taxon_names, :taxon_names_status_check,
             check: "status IN ('accepted', 'synonym')"
           )

    create constraint(:taxon_names, :taxon_names_name_present,
             check: "name <> '' AND normalized_name <> ''"
           )

    Audit.track_table("taxon_names")

    create table(:taxon_common_names) do
      add :taxon_id, references(:taxa, type: :bigint, on_delete: :delete_all), null: false
      add :name, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:taxon_common_names, ["taxon_id", "lower(name)"],
             name: :taxon_common_names_taxon_id_name_index
           )

    create constraint(:taxon_common_names, :taxon_common_names_name_present,
             check: "name <> ''"
           )

    Audit.track_table("taxon_common_names")

    # Crosswalk from the old model's identifiers to taxa, for `/taxonomy/:id`
    # redirects, `fa=` bookmarks, the data migration and the replay log:
    #
    #   * kind 'taxonomy': `legacy_id` is an old `taxonomy.id` (family, genus,
    #     section, intermediate ranks); one row per old row.
    #   * kind 'gall_inducer': `legacy_id` is an old gall `species.id`, mapped
    #     to that row's Inducer taxon. An agamic/sexgen pair maps both rows to
    #     one Inducer.
    #
    # `legacy_name` keeps the old row's name as it was (e.g. "Andricus foo
    # (agamic)") for review and replay.
    create table(:legacy_taxon_ids) do
      add :kind, :text, null: false
      add :legacy_id, :bigint, null: false
      add :legacy_name, :text
      add :taxon_id, references(:taxa, type: :bigint, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:legacy_taxon_ids, [:kind, :legacy_id])
    create index(:legacy_taxon_ids, [:taxon_id])

    create constraint(:legacy_taxon_ids, :legacy_taxon_ids_kind_check,
             check: "kind IN ('taxonomy', 'gall_inducer')"
           )

    Audit.track_table("legacy_taxon_ids")

    # Closure table: one row per (ancestor, descendant) pair, each taxon its
    # own ancestor at depth 0. Rebuilt for a subtree when a parent changes.
    create table(:taxon_ancestry, primary_key: false) do
      add :ancestor_id, references(:taxa, type: :bigint, on_delete: :delete_all),
        primary_key: true

      add :descendant_id, references(:taxa, type: :bigint, on_delete: :delete_all),
        primary_key: true

      add :depth, :integer, null: false
    end

    create index(:taxon_ancestry, [:descendant_id, :depth])

    create constraint(:taxon_ancestry, :taxon_ancestry_depth_check,
             check: "depth >= 0 AND (depth = 0) = (ancestor_id = descendant_id)"
           )

    execute("""
    ALTER TABLE attribution_names
      ADD CONSTRAINT attribution_names_taxon_id_fkey
      FOREIGN KEY (taxon_id) REFERENCES taxa (id) ON DELETE RESTRICT
    """)
  end

  def down do
    execute("ALTER TABLE attribution_names DROP CONSTRAINT attribution_names_taxon_id_fkey")

    drop table(:taxon_ancestry)

    for table <- ~w(legacy_taxon_ids taxon_common_names taxon_names taxa) do
      Audit.untrack_table(table)
      drop table(table)
    end
  end

  defp list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
