defmodule Gallformers.Repo.Migrations.CreateVocabRequests do
  @moduledoc """
  The vocabulary backlog (matter 6611, Task 4): `vocab_requests` holds a
  curator's request for a new Trait value, made by deciding a set-aside
  term `request_value` (`Gallformers.Import.VocabRequest`). Each keeps its
  origin — the package, batch and queue item (with its statement ref), the
  Galls it covers with their quotes — and how senior admins decided it:
  `requested`, then `added` (a new value), `mapped` (to an existing value)
  or `declined`, with the value it ended as, who and when.

  `replay_log.kind` gains `vocab_requests_decided`
  (`Gallformers.Import.VocabRequests`), so a decision made on preview is
  replayed after the cutover data migration. The kind check is rebuilt
  from the kinds it allows now plus this one, so kinds other migrations
  add are kept whatever order they run in.

  Audited: requests are curated state.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  @statuses ~w(requested added mapped declined)
  @kinds ["vocab_requests_decided"]

  def up do
    create table(:vocab_requests) do
      add :trait, :text, null: false
      # The term as written, and as compared (lowercased, whitespace collapsed).
      add :term, :text, null: false
      add :normalized_term, :text, null: false
      add :package_id, references(:import_packages, on_delete: :restrict), null: false
      add :batch_id, references(:import_batches, on_delete: :restrict), null: false
      add :queue_item_id, references(:queue_items, on_delete: :restrict), null: false
      add :statement_ref, :text, null: false
      # The item's covers: each Gall's ref and name as written, the term,
      # the evidence (quotes), the producer's note and the entry's position.
      add :covers, :jsonb, null: false, default: "[]"
      add :requested_by_name, :text, null: false
      add :status, :text, null: false, default: "requested"
      # The Trait value it ended as (added or mapped).
      add :value, :text
      add :decided_by_user_id, references(:users, on_delete: :nilify_all)
      add :decided_by_name, :text
      add :decided_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:vocab_requests, [:queue_item_id])
    create index(:vocab_requests, [:trait, :normalized_term])

    create constraint(:vocab_requests, :vocab_requests_status_check,
             check: "status IN (#{list(@statuses)})"
           )

    create constraint(:vocab_requests, :vocab_requests_decided_check,
             check: """
             (status = 'requested' AND value IS NULL AND decided_at IS NULL)
             OR (status = 'declined' AND value IS NULL AND decided_at IS NOT NULL
                 AND decided_by_name IS NOT NULL)
             OR (status IN ('added', 'mapped') AND value IS NOT NULL AND decided_at IS NOT NULL
                 AND decided_by_name IS NOT NULL)
             """
           )

    Audit.track_table("vocab_requests")

    replace_kind_check(Enum.uniq(current_kinds() ++ @kinds))
  end

  def down do
    # `replay_log` is audited: the deletion is recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("drop_vocab_requests")
    execute "DELETE FROM replay_log WHERE kind IN (#{list(@kinds)})"
    replace_kind_check(current_kinds() -- @kinds)

    Audit.untrack_table("vocab_requests")
    drop table(:vocab_requests)
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
