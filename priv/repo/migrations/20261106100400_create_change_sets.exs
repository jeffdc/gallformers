defmodule Gallformers.Repo.Migrations.CreateChangeSets do
  @moduledoc """
  The curation tray (matter `ec2c`, `Gallformers.Curation`): a curator's
  change set — Gallformers' own statements and editorial edits, drafted on
  the pages and applied together or one by one.

    * `change_sets` — one per curator (`user_id` unique), with the evidence
      given once for the set (`evidence`: text, Observations, a Source).
    * `change_set_items` — one per Fact key or field and subject: its
      `kind` (`fact`, `note`, `editorial`), its subject (`subject_type`
      `gall` or `plant`, `subject_id`), its `key` (the Gall page's key, or
      the field, encoded), the edit (`spec`), its own `evidence` (null: the
      set's), what it saw when added (`seen`, `seen_at`), its `status`
      (`draft`; `submitted` in a package, `package_id`, waiting for the
      import job; `in_review`, the package waiting for an admin), the Fact
      refs it became in that package (`package_refs`) and the last outcome
      that held it back (`outcome`).

  Drafts, not data: neither table is audited or replayed (an applied item
  is, as the package or editorial edit it becomes), and both are private:
  not in the public snapshot.
  """
  use Ecto.Migration

  def change do
    create table(:change_sets) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :user_name, :text, null: false
      add :evidence, :map

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:change_sets, [:user_id])

    create table(:change_set_items) do
      add :change_set_id, references(:change_sets, on_delete: :delete_all), null: false
      add :kind, :text, null: false
      add :subject_type, :text, null: false
      add :subject_id, :bigint, null: false
      add :key, :text, null: false
      add :spec, :map, null: false
      add :evidence, :map
      add :seen, :map, null: false, default: %{}
      add :seen_at, :utc_datetime_usec, null: false
      add :status, :text, null: false, default: "draft"
      add :package_id, references(:import_packages, on_delete: :nilify_all)
      add :package_refs, {:array, :text}, null: false, default: []
      add :outcome, :map

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:change_set_items, [:change_set_id, :kind, :subject_type, :subject_id, :key])
    create index(:change_set_items, [:subject_type, :subject_id])
    create index(:change_set_items, [:package_id], where: "package_id IS NOT NULL")

    create constraint(:change_set_items, :change_set_items_kind_check,
             check: "kind IN ('fact', 'note', 'editorial')"
           )

    create constraint(:change_set_items, :change_set_items_subject_type_check,
             check: "subject_type IN ('gall', 'plant')"
           )

    create constraint(:change_set_items, :change_set_items_status_check,
             check: "status IN ('draft', 'submitted', 'in_review')"
           )
  end
end
