defmodule Gallformers.Repo.Migrations.AddTermToAttributions do
  @moduledoc """
  Trait attributions carry the Source's term (matter d213, Task A):
  `attributions.term` is the term the Source used for a Trait, verbatim
  ("ovoid", "oval"), so several Sources' terms support one Fact on their
  category (globular). `value_as_written` stays as it was.

  Backfill: each existing Trait attribution (`facts.kind = 'gall_trait'`)
  takes its `value_as_written` as its term, where it has one.
  """
  use Ecto.Migration

  def up do
    alter table(:attributions) do
      add :term, :text
    end

    # `attributions` is audited: the backfill is recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("add_term_to_attributions",
      meta: meta("add_term_to_attributions")
    )

    execute backfill_sql()
  end

  def down do
    alter table(:attributions) do
      remove :term
    end
  end

  @doc "The backfill: Trait attributions' terms from their values as written."
  def backfill_sql do
    """
    UPDATE attributions a
    SET term = a.value_as_written
    FROM facts f
    WHERE f.id = a.fact_id
      AND f.kind = 'gall_trait'
      AND a.term IS NULL
      AND a.value_as_written IS NOT NULL
    """
  end

  # The audit record a data change in a migration needs: an actor and an
  # operation (`transactions_meta_attribution`).
  defp meta(name),
    do: %{actor: %{type: "system", name: "migration"}, operation: "migration.#{name}"}
end
