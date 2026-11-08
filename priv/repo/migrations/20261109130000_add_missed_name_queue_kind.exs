defmodule Gallformers.Repo.Migrations.AddMissedNameQueueKind do
  @moduledoc """
  Names the producer missed (matter `c8c3` item 12,
  `Gallformers.Import.MissedNames`): `queue_items.kind` gains
  `missed_name`. The kind check is rebuilt from the kinds it allows now
  plus this one, so kinds other migrations add are kept whatever order
  they run in. Replay-log entries need no new kind: a decision is a
  `queue_decision`.
  """
  use Ecto.Migration

  @new "missed_name"

  def up, do: replace_kind_check(Enum.uniq(current_kinds() ++ [@new]))

  def down do
    # `queue_items` is audited: the deletions are recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("drop_missed_name_questions")
    execute "DELETE FROM queue_items WHERE kind = '#{@new}'"
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
