defmodule Gallformers.Repo.Migrations.AddFactContests do
  @moduledoc """
  A revalidated name outranks an older synonymy of it (matter `f923`, the
  last "Decided" rule). Facts in different slots may contest one thing for
  different holders: a name Fact (the name as a taxon's accepted name) and
  a synonymy Fact (the name as a synonym of another taxon) contest the name.

    * `facts` gains `contest` (e.g. `"taxon_name:<normalized name>"`) and
      `contest_holder` (e.g. `"taxon:<id>"`), set when the Fact is made and
      never changed, like `slot`; indexed for the recompute's lookups.
    * The existing name and synonymy Facts get theirs from their details.
      Their standings are recomputed by the next write touching them, or
      by `Gallformers.Facts.recompute_for_source/2`.
  """
  use Ecto.Migration

  def up do
    alter table(:facts) do
      add :contest, :text
      add :contest_holder, :text
    end

    create index(:facts, [:contest], where: "contest IS NOT NULL")
    create constraint(:facts, :facts_contest_holder, check: "(contest IS NULL) = (contest_holder IS NULL)")

    flush()

    # The table is audited: the backfill is recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("add_fact_contests",
      meta: meta("add_fact_contests")
    )

    execute """
    UPDATE facts f
    SET contest = 'taxon_name:' || n.normalized_name, contest_holder = 'taxon:' || n.taxon_id
    FROM name_facts n
    WHERE n.fact_id = f.id
    """

    execute """
    UPDATE facts f
    SET contest = 'taxon_name:' || s.normalized_name,
        contest_holder = 'taxon:' || s.accepted_taxon_id
    FROM synonymy_facts s
    WHERE s.fact_id = f.id
    """
  end

  def down do
    Carbonite.Migrations.insert_migration_transaction("drop_fact_contests",
      meta: meta("drop_fact_contests")
    )

    drop constraint(:facts, :facts_contest_holder)
    drop index(:facts, [:contest])

    alter table(:facts) do
      remove :contest_holder
      remove :contest
    end
  end

  defp meta(name),
    do: %{actor: %{type: "system", name: "migration"}, operation: "migration.#{name}"}
end
