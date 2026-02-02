defmodule Gallformers.Species.Alias do
  @moduledoc """
  Ecto schema for the alias table.

  Represents alternative names for species (synonyms, common names, etc.).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour Gallformers.SchemaFields

  @required_fields [:name, :type]

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          type: String.t() | nil,
          description: String.t() | nil
        }

  schema "alias" do
    field :name, :string
    field :type, :string
    field :description, :string, default: ""

    many_to_many :species, Gallformers.Species.Species,
      join_through: "alias_species",
      join_keys: [alias_id: :id, species_id: :id]

    many_to_many :taxonomies, Gallformers.Taxonomy.Taxonomy,
      join_through: "taxonomy_alias",
      join_keys: [alias_id: :id, taxonomy_id: :id]

    timestamps(type: :utc_datetime)
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Creates a changeset for an alias.
  """
  def changeset(alias_record, attrs) do
    alias_record
    |> cast(attrs, [:name, :type, :description])
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 500)
  end
end
