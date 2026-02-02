defmodule Gallformers.FilterFields.PlantPart do
  @moduledoc """
  Ecto schema for the plant_part table.

  Represents where on the plant a gall forms (leaf, stem, bud, etc.).
  Previously called "location" but renamed to avoid confusion with geographic places.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          part: String.t() | nil,
          description: String.t() | nil
        }

  schema "plant_part" do
    field :part, :string
    field :description, :string
  end

  @doc """
  Creates a changeset for a plant part.
  """
  def changeset(plant_part, attrs) do
    plant_part
    |> cast(attrs, [:part, :description])
    |> validate_required([:part])
    |> unique_constraint(:part)
  end
end
