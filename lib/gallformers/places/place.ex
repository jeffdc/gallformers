defmodule Gallformers.Places.Place do
  @moduledoc """
  Ecto schema for the place table.

  Represents a geographic location (state, province, region).
  Used to track where species are found.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour Gallformers.SchemaFields

  @required_fields [:name, :code, :type]

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          code: String.t() | nil,
          type: String.t() | nil
        }

  @place_types ~w(state province country region)

  schema "place" do
    field :name, :string
    field :code, :string
    field :type, :string

    many_to_many :children, __MODULE__,
      join_through: "placeplace",
      join_keys: [parent_id: :id, place_id: :id]

    many_to_many :parents, __MODULE__,
      join_through: "placeplace",
      join_keys: [place_id: :id, parent_id: :id]

    # Host species that grow in this place
    many_to_many :host_species, Gallformers.Species.Species,
      join_through: "host_range",
      join_keys: [place_id: :id, species_id: :id]

    # Gall species that are excluded from this place
    many_to_many :gall_exclusions, Gallformers.Species.Species,
      join_through: "gall_range_exclusion",
      join_keys: [place_id: :id, species_id: :id]
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Creates a changeset for a place.
  """
  def changeset(place, attrs) do
    place
    |> cast(attrs, [:name, :code, :type])
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @place_types)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:code, min: 1, max: 10)
    |> unique_constraint(:name)
    |> unique_constraint(:code)
  end

  @doc """
  Returns the list of valid place types.
  """
  def place_types, do: @place_types
end
