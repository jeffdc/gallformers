defmodule Gallformers.FilterFields.Alignment do
  @moduledoc """
  Ecto schema for the alignment table.

  Alignment describes how galls are oriented on the host (e.g., "erect", "integral").
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          alignment: String.t() | nil,
          description: String.t() | nil
        }

  schema "alignment" do
    field :alignment, :string
    field :description, :string
  end

  @doc false
  def changeset(alignment, attrs) do
    alignment
    |> cast(attrs, [:alignment, :description])
    |> validate_required([:alignment])
    |> unique_constraint(:alignment)
  end
end
