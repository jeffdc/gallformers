defmodule Gallformers.Repo.Migrations.CreateImport do
  @moduledoc """
  Creates the `Import` tables (`9449` §5, Task 11) and gives
  `attributions.batch_id` its foreign key to `import_batches`.

    * `import_packages` — one per delivered package (`import/<key>/` in the
      private bucket): its status, the validation problems, the resolved
      Source (Task 13), the format and vocabulary versions, the submitter.
    * `import_batches` — one per batch file of a package, with the
      producer's `batch_id` (unique: re-delivering a batch is a no-op) and
      the validated batch content.
    * `batch_statements` — each taxon, Gall, act and Fact of a batch with
      its resolution (Task 12) and, when applied, its delta class (Task 13).
    * `batch_unmapped` — the batch's `unmapped` entries (they stay in
      `Import`, never become Facts).
    * `queue_items` — the admin queue: ambiguous and unresolved names,
      unresolved Hosts (`d585`), undescribed-Gall candidates, disputes,
      same-date conflicts, taxonomy disagreements, generations outside
      their group; each with its proposal and decision (who, when).
    * `replay_log` — the ordered record, by stable keys, of everything that
      changes data during the backscan (Task 14).

  Audited (curated state, decided or delivered by someone):
  `import_packages`, `import_batches`, `queue_items`, `replay_log`. Not
  audited: `batch_statements` and `batch_unmapped`, which are derived from a
  batch's content and rebuilt whenever it is resolved again (as
  `document_items` is derived from a stored document); every decision about
  a statement is a queue item, which is audited.

  None of these tables go in the public snapshot (Task 17).
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  @package_statuses ~w(received invalid validated resolving awaiting_review approved denied)
  @batch_statuses ~w(pending blocked ready applied denied)
  @statement_kinds ~w(taxon gall act fact)
  @resolutions ~w(resolved ambiguous unresolved new)
  @deltas ~w(confirms_existing new denies_or_replaces)
  @queue_kinds ~w(ambiguous_match unresolved_name unresolved_host undescribed_gall dispute
                  same_date_conflict taxonomy_disagreement generation_outside_group)
  @queue_statuses ~w(open decided)
  @replay_kinds ~w(batch_applied queue_decision synonym_added plant_added taxonomy_edit)

  def up do
    create table(:import_packages) do
      # The package's folder in the private bucket: import/<key>/.
      add :key, :text, null: false
      add :s3_prefix, :text, null: false
      add :status, :text, null: false, default: "received"
      # The Source the package is about, once matched or created (Task 13).
      add :source_id, references(:source, on_delete: :restrict)
      add :format_version, :integer
      add :vocabulary_version, :text
      add :submitter_user_id, references(:users, on_delete: :nilify_all)
      add :submitter_name, :text, null: false
      # The last validation's problems: [{level, file, message}].
      add :problems, {:array, :map}, null: false, default: []
      add :validated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:import_packages, [:key])
    create index(:import_packages, [:source_id])

    create constraint(:import_packages, :import_packages_status_check,
             check: "status IN (#{list(@package_statuses)})"
           )

    create constraint(:import_packages, :import_packages_key_check,
             check: "key ~ '^[A-Za-z0-9][A-Za-z0-9._-]*$'"
           )

    Audit.track_table("import_packages")

    create table(:import_batches) do
      add :package_id, references(:import_packages, on_delete: :restrict), null: false
      # taxonomy.json or gall.json
      add :file, :text, null: false
      add :batch_type, :text, null: false
      add :mode, :text, null: false
      # The producer's batch_id: unique, so a batch is imported once.
      add :producer_batch_id, :text, null: false
      add :sha256, :text, null: false
      # The batch as validated (decoded JSON).
      add :content, :jsonb, null: false
      add :status, :text, null: false, default: "pending"
      add :applied_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:import_batches, [:producer_batch_id])
    create unique_index(:import_batches, [:package_id, :file])

    create constraint(:import_batches, :import_batches_type_check,
             check: "batch_type IN ('taxonomy', 'gall')"
           )

    create constraint(:import_batches, :import_batches_file_check,
             check: "file = batch_type || '.json'"
           )

    create constraint(:import_batches, :import_batches_mode_check,
             check: "mode IN ('replace', 'add')"
           )

    create constraint(:import_batches, :import_batches_status_check,
             check: "status IN (#{list(@batch_statuses)})"
           )

    create constraint(:import_batches, :import_batches_applied_check,
             check: "(status = 'applied') = (applied_at IS NOT NULL)"
           )

    Audit.track_table("import_batches")

    create table(:batch_statements) do
      add :batch_id, references(:import_batches, on_delete: :delete_all), null: false
      add :kind, :text, null: false
      # The statement's ref or id in the batch: t1, g1, a1, f1.
      add :ref, :text, null: false
      add :resolution, :text, null: false
      # How it resolved (e.g. "exact", "synonym", "abbreviation",
      # "name_reading", "fused_epithet", "identified_by", "undescribed").
      add :method, :text
      add :taxon_id, references(:taxa, type: :bigint, on_delete: :restrict)
      add :gall_id, references(:galls, type: :bigint, on_delete: :restrict)
      add :fact_id, references(:facts, on_delete: :restrict)
      # Taxa (kind taxon) or Galls (kind gall) to choose between.
      add :candidate_ids, {:array, :bigint}, null: false, default: []
      # Problems for a curator, e.g. "synonym_held_valid".
      add :flags, {:array, :text}, null: false, default: []
      # What was resolved and why: names as written, the name tried, reasons.
      add :detail, :jsonb, null: false, default: "{}"
      # Set when applied (Task 13).
      add :delta, :text
    end

    create unique_index(:batch_statements, [:batch_id, :kind, :ref])
    create index(:batch_statements, [:taxon_id], where: "taxon_id IS NOT NULL")
    create index(:batch_statements, [:gall_id], where: "gall_id IS NOT NULL")

    create constraint(:batch_statements, :batch_statements_kind_check,
             check: "kind IN (#{list(@statement_kinds)})"
           )

    create constraint(:batch_statements, :batch_statements_resolution_check,
             check: "resolution IN (#{list(@resolutions)})"
           )

    create constraint(:batch_statements, :batch_statements_delta_check,
             check: "delta IS NULL OR delta IN (#{list(@deltas)})"
           )

    create table(:batch_unmapped) do
      add :batch_id, references(:import_batches, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :term, :text, null: false
      add :slot, :text, null: false
      # The batch's Gall ref, if the entry describes one.
      add :gall_ref, :text
      add :note, :text
      add :evidence, {:array, :map}, null: false, default: []
    end

    create unique_index(:batch_unmapped, [:batch_id, :position])

    create table(:queue_items) do
      add :package_id, references(:import_packages, on_delete: :restrict), null: false
      add :batch_id, references(:import_batches, on_delete: :restrict)
      add :kind, :text, null: false
      # The statement the item is about (t1, g1, f3), when it is about one.
      add :statement_ref, :text
      # What the item is about, e.g. the name as written and its rank.
      add :subject, :jsonb, null: false, default: "{}"
      # The proposed match and the candidates, with the reason.
      add :proposal, :jsonb, null: false, default: "{}"
      add :reason, :text
      add :status, :text, null: false, default: "open"
      add :decision, :jsonb
      add :decided_by_user_id, references(:users, on_delete: :nilify_all)
      add :decided_by_name, :text
      add :decided_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:queue_items, [:package_id])
    create index(:queue_items, [:status, :kind])

    create unique_index(:queue_items, [:batch_id, :kind, :statement_ref],
             where: "batch_id IS NOT NULL AND statement_ref IS NOT NULL",
             name: :queue_items_statement_unique
           )

    create constraint(:queue_items, :queue_items_kind_check,
             check: "kind IN (#{list(@queue_kinds)})"
           )

    create constraint(:queue_items, :queue_items_status_check,
             check: "status IN (#{list(@queue_statuses)})"
           )

    create constraint(:queue_items, :queue_items_decided_check,
             check: """
             (status = 'open' AND decision IS NULL AND decided_at IS NULL)
             OR (status = 'decided' AND decision IS NOT NULL AND decided_at IS NOT NULL
                 AND decided_by_name IS NOT NULL)
             """
           )

    Audit.track_table("queue_items")

    create table(:replay_log) do
      add :kind, :text, null: false
      # Stable references only (batch_id and statement refs, taxon names,
      # legacy IDs), never database IDs.
      add :key, :jsonb, null: false
      add :payload, :jsonb, null: false, default: "{}"

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create constraint(:replay_log, :replay_log_kind_check,
             check: "kind IN (#{list(@replay_kinds)})"
           )

    Audit.track_table("replay_log")

    alter table(:attributions) do
      modify :batch_id, references(:import_batches, on_delete: :restrict), from: :bigint
    end
  end

  def down do
    alter table(:attributions) do
      modify :batch_id, :bigint, from: references(:import_batches, on_delete: :restrict)
    end

    for table <- ~w(replay_log queue_items) do
      Audit.untrack_table(table)
      drop table(table)
    end

    drop table(:batch_unmapped)
    drop table(:batch_statements)

    for table <- ~w(import_batches import_packages) do
      Audit.untrack_table(table)
      drop table(table)
    end
  end

  defp list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
