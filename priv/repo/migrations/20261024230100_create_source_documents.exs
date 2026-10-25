defmodule Gallformers.Repo.Migrations.CreateSourceDocuments do
  @moduledoc """
  Creates `source_documents` and `document_items` (`9449` §2).

  A `source_documents` row is one stored document of a Source, kept in the
  private bucket: a Source's `document.json` (a DoclingDocument, kind
  `docling`), or one version of a Gall's Gallformers note (kind `note`, with
  the Gall and the version's date). Re-storing the same bytes for the same
  Source (or, for a note, the same Gall) finds the existing row.

  `document_items` holds each text, table and picture item's text, read from
  the stored document, for checking and locating quotes. It is derived and
  re-creatable from the document, so it is not audited; `source_documents` is.
  Neither table goes in the public snapshot.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  def up do
    create table(:source_documents) do
      add :source_id, references(:source, on_delete: :restrict), null: false
      add :kind, :text, null: false
      add :s3_key, :text, null: false
      add :sha256, :text, null: false
      # The Gall a note belongs to. Task 9 (`9449`) adds the foreign key to
      # `galls` when that table exists.
      add :gall_id, :bigint
      add :version_date, :date

      timestamps(type: :utc_datetime)
    end

    create constraint(:source_documents, :source_documents_kind_check,
             check: "kind IN ('docling', 'note')"
           )

    create constraint(:source_documents, :source_documents_sha256_check,
             check: "sha256 ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:source_documents, :source_documents_note_fields,
             check: """
             (kind = 'note' AND gall_id IS NOT NULL AND version_date IS NOT NULL)
             OR (kind = 'docling' AND gall_id IS NULL AND version_date IS NULL)
             """
           )

    create unique_index(:source_documents, [:source_id, :sha256],
             where: "kind = 'docling'",
             name: :source_documents_docling_unique
           )

    create unique_index(:source_documents, [:source_id, :gall_id, :sha256],
             where: "kind = 'note'",
             name: :source_documents_note_unique
           )

    create index(:source_documents, [:gall_id], where: "gall_id IS NOT NULL")

    Audit.track_table("source_documents")

    create table(:document_items) do
      add :source_document_id, references(:source_documents, on_delete: :delete_all),
        null: false

      # The item's DoclingDocument reference, e.g. "#/texts/42".
      add :ref, :text, null: false
      add :label, :text
      add :text, :text, null: false
      # The PDF page the item starts on (Docling provenance), not the printed page.
      add :page_no, :integer
      # Reading order within the document.
      add :position, :integer, null: false
    end

    create unique_index(:document_items, [:source_document_id, :ref])
    create unique_index(:document_items, [:source_document_id, :position])
  end

  def down do
    drop table(:document_items)
    Audit.untrack_table("source_documents")
    drop table(:source_documents)
  end
end
