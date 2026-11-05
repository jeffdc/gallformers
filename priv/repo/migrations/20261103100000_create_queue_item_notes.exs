defmodule Gallformers.Repo.Migrations.CreateQueueItemNotes do
  @moduledoc """
  Notes on queue items (matter `d213`, Task 7): a curator's note for the
  next curator, saved on its own, decided or not
  (`Gallformers.Import.QueueItemNote`). A note is not part of a decision
  and is not replayed. Before this table a note was a `"note"` key in the
  decision; those stay where they are and are shown as notes.

  A note goes with its item (`ON DELETE CASCADE`): an open item that a
  later resolution no longer calls for is deleted with its notes, unless
  an item about the same statement replaces it, which takes them
  (`Gallformers.Import.resolve_package/2`).

  Audited: notes are curated state. Private: not in the public snapshot.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  def up do
    create table(:queue_item_notes) do
      add :queue_item_id, references(:queue_items, on_delete: :delete_all), null: false
      add :text, :text, null: false
      add :author_user_id, references(:users, on_delete: :nilify_all)
      add :author_name, :text, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:queue_item_notes, [:queue_item_id])

    create constraint(:queue_item_notes, :queue_item_notes_text_check, check: "btrim(text) <> ''")

    Audit.track_table("queue_item_notes")
  end

  def down do
    Audit.untrack_table("queue_item_notes")
    drop table(:queue_item_notes)
  end
end
