defmodule Gallformers.GallHosts.GallHost do
  @moduledoc """
  Ecto schema for the gallhost table.

  Represents the many-to-many relationship between gall species and host plant species.
  A gall (gall_species_id) forms on a host plant (host_species_id).

  Note: Both sides reference Species - galls are Species with taxoncode='gall',
  hosts are Species with taxoncode='plant'.
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
  Creates a changeset for a gall-host relationship.
  """
  def changeset(gall_host, attrs) do
    gall_host
    |> cast(attrs, [:host_species_id, :gall_species_id])
    |> validate_required(@required_fields)
    |> unique_constraint([:host_species_id, :gall_species_id])
  end
end
