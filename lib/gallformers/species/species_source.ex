defmodule Gallformers.Species.SpeciesSource do
  @moduledoc """
  Ecto schema for the species_source table.

  Links species to sources with additional metadata about the reference.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour Gallformers.SchemaFields

  @required_fields [:species_id, :source_id]

  @type t :: %__MODULE__{
          id: integer() | nil,
          species_id: integer() | nil,
          source_id: integer() | nil,
          description: String.t() | nil,
          useasdefault: integer(),
          externallink: String.t() | nil,
          alias_id: integer() | nil
        }

  schema "species_source" do
    field :description, :string, default: ""
    field :useasdefault, :integer, default: 0
    field :externallink, :string, default: ""

    belongs_to :species, Gallformers.Species.Species
    belongs_to :source, Gallformers.Sources.Source
    belongs_to :alias, Gallformers.Species.Alias
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Creates a changeset for a species-source mapping.
  """
  def changeset(species_source, attrs) do
    species_source
    |> cast(attrs, [
      :species_id,
      :source_id,
      :description,
      :useasdefault,
      :externallink,
      :alias_id
    ])
    |> validate_required(@required_fields)
    |> unique_constraint([:species_id, :source_id],
      name: :species_source_species_id_source_id,
      message: "this species is already linked to this source"
    )
    |> foreign_key_constraint(:species_id)
    |> foreign_key_constraint(:source_id)
  end
end
