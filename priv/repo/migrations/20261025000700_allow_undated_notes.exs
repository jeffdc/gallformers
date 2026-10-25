defmodule Gallformers.Repo.Migrations.AllowUndatedNotes do
  @moduledoc """
  Lets a Gallformers note version have no date (`9449` Task 16; `20e5`).

  Each note version carries its edit date, so statements extracted from it
  are dated — except the legacy notes, migrated verbatim from
  `species_source`, which have none (`species_source` keeps no timestamps).
  Giving them the migration's date would make them outrank the literature
  under the recency rule (`8567` Sources–Facts point 7), so a legacy note's
  `version_date` stays null. A note still needs its Gall.
  """
  use Ecto.Migration

  def up do
    drop constraint(:source_documents, :source_documents_note_fields)

    create constraint(:source_documents, :source_documents_note_fields,
             check: """
             (kind = 'note' AND gall_id IS NOT NULL)
             OR (kind = 'docling' AND gall_id IS NULL AND version_date IS NULL)
             """
           )
  end

  def down do
    drop constraint(:source_documents, :source_documents_note_fields)

    create constraint(:source_documents, :source_documents_note_fields,
             check: """
             (kind = 'note' AND gall_id IS NOT NULL AND version_date IS NOT NULL)
             OR (kind = 'docling' AND gall_id IS NULL AND version_date IS NULL)
             """
           )
  end
end
