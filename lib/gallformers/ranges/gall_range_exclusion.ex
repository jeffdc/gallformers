defmodule Gallformers.Ranges.GallRangeExclusion do
  @moduledoc """
  Ecto schema for the gall_range_exclusion table.

  Represents places where a gall does NOT occur, even though suitable host
  plants exist there. Used to compute effective gall range:

      effective_range = (union of all host plant ranges) - (exclusions)

  Only used for galls (Species with taxoncode='gall').
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour Gallformers.SchemaFields

  @required_fields [:species_id, :place_id]

  @primary_key false
  schema "gall_range_exclusion" do
    belongs_to :species, Gallformers.Species.Species
    belongs_to :place, Gallformers.Places.Place
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Creates a changeset for a gall range exclusion entry.
  """
  def changeset(exclusion, attrs) do
    exclusion
    |> cast(attrs, [:species_id, :place_id])
    |> validate_required(@required_fields)
    |> unique_constraint([:species_id, :place_id], name: :gall_range_exclusion_pkey)
  end
end
