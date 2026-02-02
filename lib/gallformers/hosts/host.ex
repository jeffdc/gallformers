defmodule Gallformers.Hosts.Host do
  @moduledoc """
  Ecto schema for the gallhost table.

  Represents the relationship between a gall species and a host plant species.
  This is the join table that links gall-forming organisms to their host plants.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour Gallformers.SchemaFields

  @required_fields [:host_species_id, :gall_species_id]

  @type t :: %__MODULE__{
          id: integer() | nil,
          host_species_id: integer() | nil,
          gall_species_id: integer() | nil
        }

  schema "gallhost" do
    belongs_to :host_species, Gallformers.Species.Species, foreign_key: :host_species_id
    belongs_to :gall_species, Gallformers.Species.Species, foreign_key: :gall_species_id

    timestamps(type: :utc_datetime)
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Creates a changeset for a host relationship.
  """
  def changeset(host, attrs) do
    host
    |> cast(attrs, [:host_species_id, :gall_species_id])
    |> validate_required(@required_fields)
    |> unique_constraint([:host_species_id, :gall_species_id])
  end
end
