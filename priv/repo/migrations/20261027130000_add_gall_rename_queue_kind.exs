defmodule Gallformers.Repo.Migrations.AddGallRenameQueueKind do
  @moduledoc """
  Rename proposals in the admin queue (`86e7` §3, Task 4): a taxonomy
  change that would change a Gall's derived name queues a `gall_rename`
  item (`Gallformers.Import.GallRenames`) instead of renaming the Gall.

    * `queue_items.kind` gains `gall_rename`.
    * A rename proposal comes from no import package: `package_id` is null
      for `gall_rename` items and only for them.
    * One open proposal per Gall (`subject->>'gall_id'`): a later taxonomy
      change updates it.

  Replay-log entries need no new kind: a decision on a proposal is a
  `queue_decision` like any other.
  """
  use Ecto.Migration

  @kinds ~w(ambiguous_match unresolved_name unresolved_host undescribed_gall dispute
            same_date_conflict taxonomy_disagreement generation_outside_group)

  def up do
    drop constraint(:queue_items, :queue_items_kind_check)

    create constraint(:queue_items, :queue_items_kind_check,
             check: "kind IN (#{list(@kinds ++ ["gall_rename"])})"
           )

    execute "ALTER TABLE queue_items ALTER COLUMN package_id DROP NOT NULL"

    create constraint(:queue_items, :queue_items_package_check,
             check: "(package_id IS NULL) = (kind = 'gall_rename')"
           )

    create unique_index(:queue_items, ["(subject->>'gall_id')"],
             where: "kind = 'gall_rename' AND status = 'open'",
             name: :queue_items_open_gall_rename_index
           )
  end

  def down do
    # `queue_items` is audited: the deletion is recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("drop_gall_rename_queue_kind")
    execute "DELETE FROM queue_items WHERE kind = 'gall_rename'"

    drop index(:queue_items, [], name: :queue_items_open_gall_rename_index)
    drop constraint(:queue_items, :queue_items_package_check)
    execute "ALTER TABLE queue_items ALTER COLUMN package_id SET NOT NULL"
    drop constraint(:queue_items, :queue_items_kind_check)

    create constraint(:queue_items, :queue_items_kind_check, check: "kind IN (#{list(@kinds)})")
  end

  defp list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
