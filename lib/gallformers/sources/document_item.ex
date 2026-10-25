defmodule Gallformers.Sources.DocumentItem do
  @moduledoc """
  One text, table or picture item of a stored DoclingDocument, as
  `Gallformers.Sources.Docling` reads it: its reference (`"#/texts/42"`),
  label, text, the PDF page it starts on, and its reading-order position.
  Quotes are checked and located against `text`
  (`Gallformers.Sources.QuoteLocator`).

  Derived from the stored document and re-creatable from it, so it is not
  audited and never goes in the public snapshot.
  """
  use Ecto.Schema

  alias Gallformers.Sources.SourceDocument

  @type t :: %__MODULE__{
          id: integer() | nil,
          source_document_id: integer() | nil,
          ref: String.t() | nil,
          label: String.t() | nil,
          text: String.t() | nil,
          page_no: pos_integer() | nil,
          position: non_neg_integer() | nil
        }

  schema "document_items" do
    field :ref, :string
    field :label, :string
    field :text, :string
    field :page_no, :integer
    field :position, :integer

    belongs_to :source_document, SourceDocument
  end
end
