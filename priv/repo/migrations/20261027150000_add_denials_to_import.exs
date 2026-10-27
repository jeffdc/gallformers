defmodule Gallformers.Repo.Migrations.AddDenialsToImport do
  @moduledoc """
  Denying an import package or batch (matter a856, Task 2:
  `Gallformers.Import.deny_package/3`, `deny_batch/3`).

    * `import_packages.denied_reason` and `import_batches.denied_reason` —
      why an admin denied it; set exactly when the status is `denied` (who
      and when are in the audit trail).
    * `replay_log.kind` gains `package_denied` and `batch_denied`, so a
      denial made during the backscan on preview is replayed after the
      cutover data migration.
  """
  use Ecto.Migration

  @replay_kinds ~w(batch_applied queue_decision synonym_added plant_added taxonomy_edit)
  @denial_kinds ~w(package_denied batch_denied)

  def up do
    for table <- [:import_packages, :import_batches] do
      alter table(table) do
        add :denied_reason, :text
      end

      create constraint(table, :"#{table}_denied_check",
               check: "(status = 'denied') = (denied_reason IS NOT NULL)"
             )
    end

    drop constraint(:replay_log, :replay_log_kind_check)

    create constraint(:replay_log, :replay_log_kind_check,
             check: "kind IN (#{list(@replay_kinds ++ @denial_kinds)})"
           )
  end

  def down do
    # `replay_log` is audited: the deletion is recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("drop_import_denials")
    execute "DELETE FROM replay_log WHERE kind IN (#{list(@denial_kinds)})"

    drop constraint(:replay_log, :replay_log_kind_check)

    create constraint(:replay_log, :replay_log_kind_check,
             check: "kind IN (#{list(@replay_kinds)})"
           )

    for table <- [:import_packages, :import_batches] do
      drop constraint(table, :"#{table}_denied_check")

      alter table(table) do
        remove :denied_reason
      end
    end
  end

  defp list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
