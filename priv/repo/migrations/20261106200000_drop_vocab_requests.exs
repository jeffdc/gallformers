defmodule Gallformers.Repo.Migrations.DropVocabRequests do
  @moduledoc """
  Drops `vocab_requests` (matter `f14c`, Housekeeping): 6611's vocabulary
  backlog, replaced by the superadmin vocabulary page (`d213`); nothing
  reads or writes it. Its audit trigger goes with it. The
  `vocab_requests_decided` replay kind stays allowed: old entries are kept
  and skipped (`Gallformers.Import.Replay`).

  `down` recreates the empty table as `20261102180000_create_vocab_requests`
  made it.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  @statuses ~w(requested added mapped declined)

  def up do
    Audit.untrack_table("vocab_requests")
    drop table(:vocab_requests)
  end

  def down do
    create table(:vocab_requests) do
      add :trait, :text, null: false
      add :term, :text, null: false
      add :normalized_term, :text, null: false
      add :package_id, references(:import_packages, on_delete: :restrict), null: false
      add :batch_id, references(:import_batches, on_delete: :restrict), null: false
      add :queue_item_id, references(:queue_items, on_delete: :restrict), null: false
      add :statement_ref, :text, null: false
      add :covers, :jsonb, null: false, default: "[]"
      add :requested_by_name, :text, null: false
      add :status, :text, null: false, default: "requested"
      add :value, :text
      add :decided_by_user_id, references(:users, on_delete: :nilify_all)
      add :decided_by_name, :text
      add :decided_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:vocab_requests, [:queue_item_id])
    create index(:vocab_requests, [:trait, :normalized_term])

    create constraint(:vocab_requests, :vocab_requests_status_check,
             check: "status IN (#{Enum.map_join(@statuses, ", ", &"'#{&1}'")})"
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
  end
end
