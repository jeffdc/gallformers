defmodule Gallformers.Repo.Migrations.CreateTaxonNotes do
  @moduledoc """
  "Based on" notes on a plant's editorial edits (matter `ec2c`): an edit
  that departs from WCVP (a synonym WCVP lacks, a range from a regional
  flora) may say what it follows ("per Flora of North America"), shown on
  the plant's page so the next curator knows why it differs from WCVP
  (`Gallformers.Taxa.TaxonNote`). `about` is what the edit changed:
  `name`, `synonyms` or `range`. Not evidence in the Fact sense.

  A note goes with its taxon (`ON DELETE CASCADE`). `author_user_id` is
  nilified when the user is deleted; `author_name` stays.

  Audited, and replayed (`replay_log` kind `taxon_note`). Public: shown on
  the public plant page, so in the public snapshot.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  def up do
    create table(:taxon_notes) do
      add :taxon_id, references(:taxa, on_delete: :delete_all), null: false
      add :about, :text, null: false
      add :text, :text, null: false
      add :author_user_id, references(:users, on_delete: :nilify_all)
      add :author_name, :text, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:taxon_notes, [:taxon_id])
    create constraint(:taxon_notes, :taxon_notes_text_check, check: "btrim(text) <> ''")

    create constraint(:taxon_notes, :taxon_notes_about_check,
             check: "about IN ('name', 'synonyms', 'range')"
           )

    Audit.track_table("taxon_notes")
  end

  def down do
    Audit.untrack_table("taxon_notes")
    drop table(:taxon_notes)
  end
end
