defmodule Gallformers.Repo.Migrations.AddTaxonomicAcceptance do
  @moduledoc """
  Acceptance and decline of taxonomic statements (matter `f923` Task 1): a
  Source's statement of a taxonomic Fact (`taxon_*` kinds) counts only once
  a curator has accepted it, unless the Source is Gallformers' own; a
  curator who does not follow it declines it with a reason.

    * `attributions` gains the mark, on the statement itself so the
      standings' recompute reads it with the stance and date:
      `accepted_at` / `accepted_by_user_id`, `declined_at` /
      `declined_by_user_id` / `decline_reason`. A statement is accepted,
      declined or neither; a decline has a reason. The table is audited
      already, so who changed the mark is recorded too.
    * `replay_log.kind` gains `taxonomic_decision`, so acceptances,
      declines and reopenings made on preview are replayed after the
      cutover data migration. The kind check is rebuilt from the kinds it
      allows now plus this one.
  """
  use Ecto.Migration

  @kinds ["taxonomic_decision"]

  def up do
    alter table(:attributions) do
      add :accepted_at, :utc_datetime
      add :accepted_by_user_id, references(:users, on_delete: :nilify_all)
      add :declined_at, :utc_datetime
      add :declined_by_user_id, references(:users, on_delete: :nilify_all)
      add :decline_reason, :text
    end

    create constraint(:attributions, :attributions_accepted_or_declined,
             check: "accepted_at IS NULL OR declined_at IS NULL"
           )

    create constraint(:attributions, :attributions_decline_reason,
             check:
               "(declined_at IS NULL AND decline_reason IS NULL) OR " <>
                 "(declined_at IS NOT NULL AND btrim(decline_reason) <> '')"
           )

    replace_kind_check(Enum.uniq(current_kinds() ++ @kinds))
  end

  def down do
    Carbonite.Migrations.insert_migration_transaction("drop_taxonomic_acceptance")
    execute "DELETE FROM replay_log WHERE kind IN (#{list(@kinds)})"
    replace_kind_check(current_kinds() -- @kinds)

    drop constraint(:attributions, :attributions_decline_reason)
    drop constraint(:attributions, :attributions_accepted_or_declined)

    alter table(:attributions) do
      remove :decline_reason
      remove :declined_by_user_id
      remove :declined_at
      remove :accepted_by_user_id
      remove :accepted_at
    end
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
