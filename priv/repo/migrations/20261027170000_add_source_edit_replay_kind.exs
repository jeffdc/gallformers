defmodule Gallformers.Repo.Migrations.AddSourceEditReplayKind do
  @moduledoc """
  The Source editor (matter a856, Task 10): `replay_log.kind` gains
  `source_edit` (`Gallformers.Import.SourceEdits`), so a Source's details
  edit, retraction or undone retraction made during the backscan on preview
  is replayed after the cutover data migration.

  The kind check is rebuilt from the kinds it allows now plus
  `source_edit`, so kinds other migrations add are kept whatever order they
  run in.
  """
  use Ecto.Migration

  @kind "source_edit"

  def up do
    replace_kind_check(Enum.uniq(current_kinds() ++ [@kind]))
  end

  def down do
    # `replay_log` is audited: the deletion is recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("drop_source_edit_replay_kind")
    execute "DELETE FROM replay_log WHERE kind = '#{@kind}'"

    replace_kind_check(current_kinds() -- [@kind])
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

    create constraint(:replay_log, :replay_log_kind_check,
             check: "kind IN (#{Enum.map_join(kinds, ", ", &"'#{&1}'")})"
           )
  end
end
