defmodule Gallformers.Repo.Migrations.AddTaxonomyAcceptanceQueueKind do
  @moduledoc """
  The taxonomy queue (matter `f923` Task 6): a Source's taxonomic statement
  that differs from the tree, newer than the latest accepted statement in
  its slot, is one `taxonomy_acceptance` question for a curator to accept
  or decline (`Gallformers.Import.TaxonomyQueue`). One queue across
  Sources; it never holds a Source's approval.

    * `queue_items.kind` gains `taxonomy_acceptance`. The kind check is
      rebuilt from the kinds it allows now plus this one, so kinds other
      migrations add are kept whatever order they run in.
    * Its package is optional: an import raises it on its package, but a
      statement reopened after its package was applied asks again from no
      package.
    * One open question per statement (`subject->>'attribution_id'`).

  Replay-log entries need no new kind: a decision is a
  `taxonomic_decision`, which closes the question when replayed.
  """
  use Ecto.Migration

  @new "taxonomy_acceptance"

  def up do
    replace_kind_check(Enum.uniq(current_kinds() ++ [@new]))

    drop constraint(:queue_items, :queue_items_package_check)

    create constraint(:queue_items, :queue_items_package_check,
             check:
               "(kind = 'gall_rename' AND package_id IS NULL) OR " <>
                 "(kind <> 'gall_rename' AND (package_id IS NOT NULL OR " <>
                 "kind IN ('same_date_conflict', 'taxonomy_acceptance')))"
           )

    create unique_index(:queue_items, ["(subject->>'attribution_id')"],
             where: "kind = 'taxonomy_acceptance' AND status = 'open'",
             name: :queue_items_open_taxonomy_acceptance_index
           )
  end

  def down do
    # `queue_items` is audited: the deletion is recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("drop_taxonomy_acceptance_queue_kind")
    execute "DELETE FROM queue_items WHERE kind = '#{@new}'"

    drop index(:queue_items, [], name: :queue_items_open_taxonomy_acceptance_index)
    drop constraint(:queue_items, :queue_items_package_check)

    create constraint(:queue_items, :queue_items_package_check,
             check:
               "(kind = 'gall_rename' AND package_id IS NULL) OR " <>
                 "(kind <> 'gall_rename' AND (package_id IS NOT NULL OR kind = 'same_date_conflict'))"
           )

    replace_kind_check(current_kinds() -- [@new])
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
