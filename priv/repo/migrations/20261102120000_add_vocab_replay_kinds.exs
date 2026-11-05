defmodule Gallformers.Repo.Migrations.AddVocabReplayKinds do
  @moduledoc """
  The Trait vocabulary is owned by the database (matter 6611, Task 1):
  `replay_log.kind` gains `trait_value_added` and `term_mapping_added`
  (`Gallformers.Import.VocabEdits`), so a Trait value or term mapping a
  curator adds on preview is replayed after the cutover data migration.

  The kind check is rebuilt from the kinds it allows now plus these, so
  kinds other migrations add are kept whatever order they run in.
  """
  use Ecto.Migration

  @kinds ["trait_value_added", "term_mapping_added"]

  def up do
    replace_kind_check(Enum.uniq(current_kinds() ++ @kinds))
  end

  def down do
    # `replay_log` is audited: the deletion is recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("drop_vocab_replay_kinds")
    execute "DELETE FROM replay_log WHERE kind IN (#{list(@kinds)})"

    replace_kind_check(current_kinds() -- @kinds)
  end

  defp current_kinds do
    %{rows: [[definition]]} =
      repo().query!(
        "SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'replay_log_kind_check'"
      )

    Regex.scan(~r/'([a-z_]+)'/, definition, capture: :all_but_first) |> List.flatten()
  end

  defp replace_kind_check(kinds) do
    drop constraint(:replay_log, :replay_log_kind_check)

    create constraint(:replay_log, :replay_log_kind_check, check: "kind IN (#{list(kinds)})")
  end

  defp list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
