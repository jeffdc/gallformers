defmodule Gallformers.Repo.Migrations.CreateSourceCorrections do
  @moduledoc """
  Curators' corrections to a Source's applied Facts (matter `f14c`, "The
  Source's Facts after approval"; `Gallformers.Import.SourceCorrection`):
  each withdraws the Source's statement of a Fact, or moves it to the Fact
  the Source did state (another Host, Trait value, parent or accepted
  taxon), with a required note of why. The Facts themselves are never
  edited; the record keeps the statement in words, not Fact IDs. A
  correction moves the Source's Updated date (`Gallformers.Import.SourceDates`).

  `replay_log.kind` gains `source_correction`: a correction made on preview
  is made again after the cutover data migration. The kind check is rebuilt
  from the kinds it allows now plus this one, so kinds other migrations add
  are kept whatever order they run in.

  Audited: corrections are curated state. Private: not in the public snapshot.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  @kinds ["source_correction"]

  def up do
    create table(:source_corrections) do
      add :source_id, references(:source, on_delete: :restrict), null: false
      add :kind, :text, null: false
      add :summary, :text, null: false
      add :change, :text
      add :note, :text, null: false
      add :author_user_id, references(:users, on_delete: :nilify_all)
      add :author_name, :text, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:source_corrections, [:source_id])

    create constraint(:source_corrections, :source_corrections_kind_check,
             check: "kind IN ('withdraw', 'host', 'values', 'parent', 'accepted')"
           )

    create constraint(:source_corrections, :source_corrections_note_check,
             check: "btrim(note) <> ''"
           )

    Audit.track_table("source_corrections")

    replace_kind_check(Enum.uniq(current_kinds() ++ @kinds))
  end

  def down do
    # `replay_log` is audited: the deletion is recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("drop_source_corrections")
    execute "DELETE FROM replay_log WHERE kind IN (#{list(@kinds)})"
    replace_kind_check(current_kinds() -- @kinds)

    Audit.untrack_table("source_corrections")
    drop table(:source_corrections)
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
