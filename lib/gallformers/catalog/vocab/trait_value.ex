defmodule Gallformers.Catalog.Vocab.TraitValue do
  @moduledoc """
  One allowed value of a Trait, with its definition (`traits.json`). The
  definition decides whether the value fits; the value is shorthand for it.
  Unique on trait + value. Generation is not a Trait Fact and has no rows
  here (see `Gallformers.Catalog.Vocab.GenerationValue`).

  ## Leaf

  The plant part `leaf` (on the leaf, with no more precise location
  stated) contains the leaf values (`leaf_values/0`), its more precise
  forms; the petiole is not one (matter `d213`, Jeff 2026-11-03). A Gall
  with a leaf value is on the leaf too, and one only on the leaf may be on
  any of them, so each matches the other (`matching_values/2`). The
  containment is built in, for `leaf` only. `leaf` is never stored beside
  a more precise leaf value: it is stored when a Source supports nothing
  more precise.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @traits ~w(detachable plant_part form shape color texture alignment walls cells season)

  @leaf "leaf"
  @leaf_values [
    "upper leaf",
    "lower leaf",
    "leaf edge",
    "leaf midrib",
    "on leaf veins",
    "between leaf veins",
    "at leaf vein angles"
  ]

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

  @doc "The plant parts `leaf` contains: its more precise forms (see *Leaf*)."
  @spec leaf_values() :: [String.t()]
  def leaf_values, do: @leaf_values

  @doc """
  The values of `trait` a Gall may have for a filter on `value` to match
  it: `value`, and for `leaf` its leaf values, for a leaf value `leaf`
  (see *Leaf*).
  """
  @spec matching_values(String.t(), String.t()) :: [String.t()]
  def matching_values("plant_part", @leaf), do: [@leaf | @leaf_values]
  def matching_values("plant_part", value) when value in @leaf_values, do: [value, @leaf]
  def matching_values(_trait, value), do: [value]

  @doc """
  A changeset for a new value: `:trait` (one of `traits/0`), `:value` and
  `:definition`, all required. The value must be new to its Trait.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(value, attrs) do
    value
    |> cast(attrs, [:trait, :value, :definition])
    |> validate_required([:trait, :value, :definition])
    |> validate_inclusion(:trait, @traits)
    |> unique_constraint([:trait, :value], error_key: :value)
  end
end
