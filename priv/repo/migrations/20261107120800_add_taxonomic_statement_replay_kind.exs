defmodule Gallformers.Repo.Migrations.AddTaxonomicStatementReplayKind do
  @moduledoc """
  The taxonomy admin's edits credited to a Source (matter `f923` Task 8): a
  non-plant move, rename, synonym or common name is recorded as the
  Source's taxonomic statement and accepted at once.

    * `replay_log.kind` gains `taxonomic_statement`, so a statement the
      taxonomy admin records on preview is recorded again after the
      cutover data migration (its acceptance is a `taxonomic_decision`
      entry). The kind check is rebuilt from the kinds it allows now plus
      this one.
  """
  use Ecto.Migration

  @kinds ["taxonomic_statement"]

  def up do
    replace_kind_check(Enum.uniq(current_kinds() ++ @kinds))
  end

  def down do
    Carbonite.Migrations.insert_migration_transaction("drop_taxonomic_statement_replay_kind")
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
