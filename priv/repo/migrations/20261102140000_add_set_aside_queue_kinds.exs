defmodule Gallformers.Repo.Migrations.AddSetAsideQueueKinds do
  @moduledoc """
  What producers set aside in the admin queue (`6611` Task 2): a batch's
  `unmapped` entries become `set_aside_term` items (a Trait term no value
  fits) and `set_aside_statement` items (a statement set aside as hedged or
  not a Fact), one per term within a package
  (`Gallformers.Import.SetAside`). They never hold approval.

  Replay-log entries need no new kind: a decision on one is a
  `queue_decision` like any other.
  """
  use Ecto.Migration

  @kinds ~w(ambiguous_match unresolved_name unresolved_host undescribed_gall dispute
            same_date_conflict taxonomy_disagreement generation_outside_group gall_rename)

  @new ~w(set_aside_term set_aside_statement)

  def up do
    drop constraint(:queue_items, :queue_items_kind_check)

    create constraint(:queue_items, :queue_items_kind_check,
             check: "kind IN (#{list(@kinds ++ @new)})"
           )
  end

  def down do
    # `queue_items` is audited: the deletion is recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("drop_set_aside_queue_kinds")
    execute "DELETE FROM queue_items WHERE kind IN (#{list(@new)})"

    drop constraint(:queue_items, :queue_items_kind_check)
    create constraint(:queue_items, :queue_items_kind_check, check: "kind IN (#{list(@kinds)})")
  end

  defp list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
