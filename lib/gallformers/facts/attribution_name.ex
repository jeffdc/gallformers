defmodule Gallformers.Facts.AttributionName do
  @moduledoc """
  A taxon an attribution names (`9449` §2): the taxon it resolved to, the
  name as the Source wrote it, the evident printed name where the text is
  damaged (`name_reading`), and the part the taxon plays in the Fact
  (`role`, e.g. `"subject"`, `"object"`, `"inducer"`). Kept so Facts can be
  re-resolved after a taxonomic split.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Facts.Attribution

  @type t :: %__MODULE__{
          id: integer() | nil,
          attribution_id: integer() | nil,
          taxon_id: integer() | nil,
          name_as_written: String.t() | nil,
          name_reading: String.t() | nil,
          role: String.t() | nil
        }

  @content_fields [:taxon_id, :name_as_written, :name_reading, :role]

  schema "attribution_names" do
    # A `taxa` row (foreign key). Facts does not depend on Taxa, so no
    # association.
    field :taxon_id, :integer
    field :name_as_written, :string
    field :name_reading, :string
    field :role, :string

    belongs_to :attribution, Attribution
  end

  @doc "The fields that make two names the same."
  @spec content_fields() :: [atom()]
  def content_fields, do: @content_fields

  @doc "Creates a changeset for a named taxon."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(name, attrs) do
    name
    |> cast(attrs, @content_fields)
    |> validate_required([:taxon_id, :name_as_written, :role])
    |> foreign_key_constraint(:taxon_id)
  end
end
