defmodule Gallformers.Repo.Migrations.AddSplitInducerQuestions do
  @moduledoc """
  Split questions (matter `f923` Task 7, "Splits"): when a split of A comes
  into effect, each Gall on A that the splitting paper doesn't settle asks
  "Which taxon induces this Gall now?" (`Gallformers.Import.SplitQuestions`).

    * `queue_items.kind` gains `split_inducer`. The kind check is rebuilt
      from the kinds it allows now plus this one, so kinds other migrations
      add are kept whatever order they run in. Its package is optional (a
      split question comes from a curator's acceptance, not an import).
      One open question per Gall (`subject->>'gall_id'`).
    * A split may keep the split taxon among its daughters, in its narrow
      sense ("A into A and B"): `split_facts_into_check` no longer refuses
      the taxon itself among `into_taxon_ids` (still two or more, sorted
      and distinct).
    * `relationship_facts.broad_sense_split_id`: an `inducer_of` Fact whose
      Inducer is known only in its old broad sense, before that split Fact
      (a curator answered "not known yet"). Set by the Catalog, never part
      of the Fact's natural key.

  Replay-log entries need no new kind: an answer is a `queue_decision`.
  """
  use Ecto.Migration

  @new "split_inducer"

  def up do
    replace_kind_check(Enum.uniq(current_kinds() ++ [@new]))

    drop constraint(:queue_items, :queue_items_package_check)
    create constraint(:queue_items, :queue_items_package_check, check: package_check(true))

    create unique_index(:queue_items, ["(subject->>'gall_id')"],
             where: "kind = 'split_inducer' AND status = 'open'",
             name: :queue_items_open_split_inducer_index
           )

    drop constraint(:split_facts, :split_facts_into_check)

    create constraint(:split_facts, :split_facts_into_check,
             check: "cardinality(into_taxon_ids) >= 2 AND taxa_sorted_distinct_ids(into_taxon_ids)"
           )

    alter table(:relationship_facts) do
      add :broad_sense_split_id, references(:facts, on_delete: :nilify_all)
    end

    create index(:relationship_facts, [:broad_sense_split_id],
             where: "broad_sense_split_id IS NOT NULL"
           )
  end

  def down do
    # `queue_items` and `split_facts` are audited: the deletions are
    # recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("drop_split_inducer_questions")
    execute "DELETE FROM queue_items WHERE kind = '#{@new}'"

    alter table(:relationship_facts) do
      remove :broad_sense_split_id
    end

    drop constraint(:split_facts, :split_facts_into_check)

    create constraint(:split_facts, :split_facts_into_check,
             check: """
             cardinality(into_taxon_ids) >= 2
             AND taxa_sorted_distinct_ids(into_taxon_ids)
             AND NOT (taxon_id = ANY (into_taxon_ids))
             """
           )

    drop index(:queue_items, [], name: :queue_items_open_split_inducer_index)
    drop constraint(:queue_items, :queue_items_package_check)
    create constraint(:queue_items, :queue_items_package_check, check: package_check(false))

    replace_kind_check(current_kinds() -- [@new])
  end

  defp package_check(with_split?) do
    optional =
      ["same_date_conflict", "taxonomy_acceptance"] ++ if(with_split?, do: [@new], else: [])

    "(kind = 'gall_rename' AND package_id IS NULL) OR " <>
      "(kind <> 'gall_rename' AND (package_id IS NOT NULL OR kind IN (#{list(optional)})))"
  end

  defp current_kinds do
    %{rows: [[definition]]} =
      repo().query!(
        "SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'queue_items_kind_check'"
      )

    Regex.scan(~r/'([a-z_]+)'/, definition, capture: :all_but_first) |> List.flatten()
  end

  defp replace_kind_check(kinds) do
    drop constraint(:queue_items, :queue_items_kind_check)
    create constraint(:queue_items, :queue_items_kind_check, check: "kind IN (#{list(kinds)})")
  end

  defp list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
