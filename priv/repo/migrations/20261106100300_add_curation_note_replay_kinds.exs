defmodule Gallformers.Repo.Migrations.AddCurationNoteReplayKinds do
  @moduledoc """
  Curation (matter `ec2c`): `replay_log.kind` gains `fact_note` (a
  curator's note on a Fact, `Gallformers.Import.record_fact_note/5`) and
  `taxon_note` (a "based on" note on a plant's edit,
  `Gallformers.Import.record_taxon_note/5`), so notes written during the
  backscan on preview are replayed after the cutover data migration.

  The kind check is rebuilt from the kinds it allows now plus these, so
  kinds other migrations add are kept whatever order they run in.
  """
  use Ecto.Migration

  @kinds ["fact_note", "taxon_note"]

  def up do
    replace_kind_check(Enum.uniq(current_kinds() ++ @kinds))
  end

  def down do
    # `replay_log` is audited: the deletion is recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("drop_curation_note_replay_kinds")
    execute "DELETE FROM replay_log WHERE kind IN ('fact_note', 'taxon_note')"

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

    create constraint(:replay_log, :replay_log_kind_check,
             check: "kind IN (#{Enum.map_join(kinds, ", ", &"'#{&1}'")})"
           )
  end
end
