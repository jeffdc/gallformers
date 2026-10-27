defmodule Gallformers.Places.Place do
  @moduledoc """
  Ecto schema for the place table.

  Represents a geographic location (state, province, region).
  Used to track where plants and Galls are found.
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
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields
end
