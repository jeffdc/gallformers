defmodule Gallformers.Phenology.Blacklist do
  @moduledoc """
  Ecto schema for the phenology_blacklist table.

  Records iNaturalist observation IDs that have been rejected from import.
  The automated fetcher checks this table before inserting new observations to
  avoid re-importing previously rejected records.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Gallformers.ChangesetHelpers, only: [trim_strings: 1]

  alias Gallformers.Species.Species

  @behaviour Gallformers.SchemaFields

  @required_fields [:inat_id]
  @optional_fields [:species_id, :reason]

  @type t :: %__MODULE__{
          id: integer() | nil,
          inat_id: integer() | nil,
          species_id: integer() | nil,
          reason: String.t() | nil
        }

  schema "phenology_blacklist" do
    field :inat_id, :integer
    field :reason, :string

    belongs_to :species, Species

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Creates a changeset for a blacklist entry.
  """
  def changeset(blacklist, attrs) do
    blacklist
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> trim_strings()
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:species_id)
    |> unique_constraint(:inat_id, name: :idx_phenology_blacklist_inat_id_unique)
  end
end
