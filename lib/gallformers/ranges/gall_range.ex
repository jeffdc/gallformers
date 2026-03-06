defmodule Gallformers.Ranges.GallRange do
  @moduledoc """
  Ecto schema for the gall_range table.

  Represents the curated geographic range for a gall species. This is the
  source of truth for "where does this gall occur" — all consumers read
  from this table instead of computing range on the fly from hosts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour Gallformers.SchemaFields

  @required_fields [:species_id, :place_id]
  @optional_fields [:precision]
  @valid_precisions ~w(exact country)

  @primary_key false
  schema "gall_range" do
    belongs_to :species, Gallformers.Species.Species
    belongs_to :place, Gallformers.Places.Place
    field :precision, :string, default: "exact"
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Creates a changeset for a gall range entry.
  """
  def changeset(gall_range, attrs) do
    gall_range
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:precision, @valid_precisions)
    |> unique_constraint([:species_id, :place_id], name: :gall_range_pkey)
  end
end
