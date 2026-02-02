defmodule Gallformers.FilterFields.Color do
  @moduledoc """
  Ecto schema for the color table.

  Colors that can be associated with galls for identification.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          color: String.t() | nil
        }

  schema "color" do
    field :color, :string
  end

  @doc false
  def changeset(color, attrs) do
    color
    |> cast(attrs, [:color])
    |> validate_required([:color])
    |> unique_constraint(:color)
  end
end
