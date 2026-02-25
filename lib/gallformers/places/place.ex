defmodule Gallformers.Places.Place do
  @moduledoc """
  Ecto schema for the place table.

  Represents a geographic location (state, province, region).
  Used to track where species are found.
  """
  use Ecto.Schema

  @behaviour Gallformers.SchemaFields

  @required_fields [:name, :code, :type]

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          code: String.t() | nil,
          type: String.t() | nil
        }

  schema "place" do
    field :name, :string
    field :code, :string
    field :type, :string

    many_to_many :children, __MODULE__,
      join_through: "place_hierarchy",
      join_keys: [parent_id: :id, place_id: :id]

    many_to_many :parents, __MODULE__,
      join_through: "place_hierarchy",
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
end
