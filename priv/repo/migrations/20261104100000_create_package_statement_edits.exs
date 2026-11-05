defmodule Gallformers.Repo.Migrations.CreatePackageStatementEdits do
  @moduledoc """
  A curator's edits on a package's Facts before approval (matter `f14c`,
  item 4; `Gallformers.Import.StatementEdit`): per batch and statement ref,
  drop the Fact, choose another plant for a Host Fact, give a Trait Fact
  other values, or leave a note. Applying the batch honours them, so the
  Facts preview (`Gallformers.Import.preview_package/2`) shows them.

  One edit of a kind per statement (a second replaces the first). An edit
  goes with its batch (`ON DELETE CASCADE`; batches are replaced only
  before a package is resolved, when no edit can exist yet).

  `replay_log.kind` gains `fact_edit` and `fact_edit_removed`: the edits
  replay after the cutover data migration, before the batch they bear on
  is applied again. The kind check is rebuilt from the kinds it allows now
  plus these, so kinds other migrations add are kept whatever order they
  run in.

  Audited: edits are curated state. Private: not in the public snapshot.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  @kinds ["fact_edit", "fact_edit_removed"]

  def up do
    create table(:package_statement_edits) do
      add :package_id, references(:import_packages, on_delete: :restrict), null: false
      add :batch_id, references(:import_batches, on_delete: :delete_all), null: false
      add :statement_ref, :text, null: false
      add :kind, :text, null: false
      add :value, :map, null: false, default: %{}
      add :note, :text
      add :author_user_id, references(:users, on_delete: :nilify_all)
      add :author_name, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:package_statement_edits, [:batch_id, :statement_ref, :kind])
    create index(:package_statement_edits, [:package_id])

    create constraint(:package_statement_edits, :package_statement_edits_kind_check,
             check: "kind IN ('drop', 'host', 'trait_value', 'note')"
           )

    create constraint(:package_statement_edits, :package_statement_edits_note_check,
             check: "kind <> 'note' OR (note IS NOT NULL AND btrim(note) <> '')"
           )

    Audit.track_table("package_statement_edits")

    replace_kind_check(Enum.uniq(current_kinds() ++ @kinds))
  end

  def down do
    # `replay_log` is audited: the deletion is recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("drop_package_statement_edits")
    execute "DELETE FROM replay_log WHERE kind IN (#{list(@kinds)})"
    replace_kind_check(current_kinds() -- @kinds)

    Audit.untrack_table("package_statement_edits")
    drop table(:package_statement_edits)
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
