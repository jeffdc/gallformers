defmodule Gallformers.Ranges.HostRange do
  @moduledoc """
  Ecto schema for the host_range table.

  Represents where a host plant species exists geographically. Only used for
  plants (Species with taxoncode='plant'). The union of all host ranges for
  a gall's hosts determines the gall's potential range.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour Gallformers.SchemaFields

  @required_fields [:species_id, :place_id]
  @optional_fields [:precision]
  @valid_precisions ~w(exact country)

  @primary_key false
  schema "host_range" do
    belongs_to :species, Gallformers.Species.Species
    belongs_to :place, Gallformers.Places.Place
    field :precision, :string, default: "exact"
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Creates a changeset for a host range entry.
  """
  def changeset(host_range, attrs) do
    host_range
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:precision, @valid_precisions)
    |> unique_constraint([:species_id, :place_id], name: :host_range_pkey)
  end
end
