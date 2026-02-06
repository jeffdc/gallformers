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

  @primary_key false
  schema "host_range" do
    belongs_to :species, Gallformers.Species.Species
    belongs_to :place, Gallformers.Places.Place
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Creates a changeset for a host range entry.
  """
  def changeset(host_range, attrs) do
    host_range
    |> cast(attrs, [:species_id, :place_id])
    |> validate_required(@required_fields)
    |> unique_constraint([:species_id, :place_id], name: :host_range_pkey)
  end
end
