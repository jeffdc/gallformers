defmodule Gallformers.Repo.Migrations.AddQueueDecisionUndoneReplayKind do
  @moduledoc """
  Undo of a decided review question (matter `f14c`, "Undo rule"):

    * `replay_log.kind` gains `queue_decision_undone`, so a decision undone
      on preview is undone again after the cutover data migration
      (`Gallformers.Import.Undo`). The kind check is rebuilt from the kinds
      it allows now plus this one.
  """
  use Ecto.Migration

  @kinds ["queue_decision_undone"]

  def up do
    replace_kind_check(Enum.uniq(current_kinds() ++ @kinds))
  end

  def down do
    Carbonite.Migrations.insert_migration_transaction("drop_queue_decision_undone_replay_kind")
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
