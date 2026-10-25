defmodule Gallformers.Catalog.Vocab.TraitValue do
  @moduledoc """
  One allowed value of a Trait, with its definition (`traits.json`). The
  definition decides whether the value fits; the value is shorthand for it.
  Unique on trait + value. Generation is not a Trait Fact and has no rows
  here (see `Gallformers.Catalog.Vocab.GenerationValue`).
  """
  use Ecto.Schema

  @traits ~w(detachable plant_part form shape color texture alignment walls cells season)

  @type t :: %__MODULE__{
          id: integer() | nil,
          trait: String.t() | nil,
          value: String.t() | nil,
          definition: String.t() | nil
        }

  schema "trait_values" do
    field :trait, :string
    field :value, :string
    field :definition, :string
  end

  @doc "The Traits a Gall's Trait Facts may state (`gall.schema.json`)."
  @spec traits() :: [String.t()]
  def traits, do: @traits
end
