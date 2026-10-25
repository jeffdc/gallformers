defmodule Gallformers.Sources.SourceDocument do
  @moduledoc """
  One stored document of a Source, kept in the private bucket (`9449` §2).

    * `:docling` — a Source's `document.json`, a DoclingDocument; its items
      are in `Gallformers.Sources.DocumentItem`.
    * `:note` — one version of a Gall's Gallformers note, with the Gall
      (`gall_id`) and the version's date (nil for a legacy note, which has
      none).

  `sha256` is the hex digest of the stored bytes. The table is audited.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Sources.DocumentItem
  alias Gallformers.Sources.Source

  @type kind :: :docling | :note

  @type t :: %__MODULE__{
          id: integer() | nil,
          source_id: integer() | nil,
          kind: kind() | nil,
          s3_key: String.t() | nil,
          sha256: String.t() | nil,
          gall_id: integer() | nil,
          version_date: Date.t() | nil
        }

  schema "source_documents" do
    field :kind, Ecto.Enum, values: [:docling, :note]
    field :s3_key, :string
    field :sha256, :string
    # A foreign key to `galls`, but no association: `Catalog` owns Galls and
    # depends on Sources, not the other way round.
    field :gall_id, :integer
    field :version_date, :date

    belongs_to :source, Source
    has_many :items, DocumentItem

    timestamps(type: :utc_datetime)
  end

  @doc "Creates a changeset for a stored document."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(document, attrs) do
    document
    |> cast(attrs, [:source_id, :kind, :s3_key, :sha256, :gall_id, :version_date])
    |> validate_required([:source_id, :kind, :s3_key, :sha256])
    |> validate_format(:sha256, ~r/\A[0-9a-f]{64}\z/, message: "must be a lowercase hex sha256")
    |> validate_note_fields()
    |> foreign_key_constraint(:source_id)
    |> foreign_key_constraint(:gall_id)
    |> check_constraint(:kind, name: :source_documents_note_fields)
    |> unique_constraint([:source_id, :sha256], name: :source_documents_docling_unique)
    |> unique_constraint([:source_id, :gall_id, :sha256], name: :source_documents_note_unique)
  end

  defp validate_note_fields(changeset) do
    case get_field(changeset, :kind) do
      :note ->
        validate_required(changeset, [:gall_id])

      :docling ->
        Enum.reduce([:gall_id, :version_date], changeset, &validate_blank/2)

      nil ->
        changeset
    end
  end

  defp validate_blank(field, changeset) do
    if is_nil(get_field(changeset, field)),
      do: changeset,
      else: add_error(changeset, field, "must be blank for a document")
  end
end
