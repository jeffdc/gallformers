defmodule Gallformers.Ranges.HostRange do
  @moduledoc """
  Ecto schema for the host_range table: where a plant grows, one row per
  place, with its precision (`exact`, or `country` for a whole country) and
  distribution (`native` or `introduced`). The union of a Gall's Hosts'
  ranges is its potential range.

  A row is keyed by `taxon_id` (the plant taxon,
  `Gallformers.Ranges.update_taxon_places/3`), by `species_id` (the old
  model's key, read by the old ID filter `Gallformers.Galls.Identification`
  until the cutover), or both: the catalog data migration fills `taxon_id`
  beside `species_id` (plant taxa keep their species IDs), and a plant
  created after it has no `species` row. Each key is unique per place where
  set.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Gallformers.ChangesetHelpers, only: [trim_strings: 1]

  @behaviour Gallformers.SchemaFields

  @required_fields [:place_id]
  @optional_fields [:species_id, :taxon_id, :precision, :distribution_type]
  @valid_precisions ~w(exact country)
  @valid_distribution_types ~w(native introduced)

  @primary_key false
  schema "host_range" do
    field :species_id, :integer
    belongs_to :place, Gallformers.Places.Place
    field :precision, :string, default: "exact"
    field :distribution_type, :string, default: "native"
    field :taxon_id, :integer
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Creates a changeset for a host range entry, keyed by `species_id`,
  `taxon_id` or both.
  """
  def changeset(host_range, attrs) do
    host_range
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> trim_strings()
    |> validate_required(@required_fields)
    |> validate_keyed()
    |> validate_inclusion(:precision, @valid_precisions)
    |> validate_inclusion(:distribution_type, @valid_distribution_types)
    |> unique_constraint([:species_id, :place_id], name: :host_range_species_id_place_id_index)
    |> unique_constraint([:taxon_id, :place_id], name: :host_range_taxon_id_place_id_index)
    |> check_constraint(:taxon_id, name: :host_range_keyed, message: "or species_id is required")
  end

  defp validate_keyed(changeset) do
    if get_field(changeset, :species_id) || get_field(changeset, :taxon_id),
      do: changeset,
      else: add_error(changeset, :taxon_id, "or species_id is required", validation: :required)
  end
end
