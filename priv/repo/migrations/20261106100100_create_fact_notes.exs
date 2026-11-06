defmodule Gallformers.Repo.Migrations.CreateFactNotes do
  @moduledoc """
  Notes on Facts (matter `ec2c`, curation): a curator's note on one Fact
  ("only on young trees"), shown with the Fact on its Gall's page
  (`Gallformers.Catalog.FactNote`). A note is a record of its own, not a
  Gallformers statement: a confirmation dated today would change the Fact's
  standing.

  A note goes with its Fact (`ON DELETE CASCADE`). `author_user_id` is
  nilified when the user is deleted; `author_name` stays.

  Audited, and replayed (`replay_log` kind `fact_note`). Public: shown on
  the public Gall page, so in the public snapshot.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  def up do
    create table(:fact_notes) do
      add :fact_id, references(:facts, on_delete: :delete_all), null: false
      add :text, :text, null: false
      add :author_user_id, references(:users, on_delete: :nilify_all)
      add :author_name, :text, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:fact_notes, [:fact_id])
    create constraint(:fact_notes, :fact_notes_text_check, check: "btrim(text) <> ''")

    Audit.track_table("fact_notes")
  end

  def down do
    Audit.untrack_table("fact_notes")
    drop table(:fact_notes)
  end
end
