defmodule Gallformers.Species.Species do
  @moduledoc """
  Ecto schema for the species table.

  Species can be galls, hosts, or other organisms. This is the core entity
  that represents a taxon in the gallformers database.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Galls.GallTraits

  @behaviour Gallformers.SchemaFields

  @required_fields [:name, :taxoncode]

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          taxoncode: String.t() | nil,
          datacomplete: boolean(),
          abundance_id: integer() | nil
        }

  schema "species" do
    field :name, :string
    field :taxoncode, :string
    field :datacomplete, :boolean, default: false

    belongs_to :abundance, Gallformers.Species.Abundance

    has_many :images, Gallformers.Images.Image
    has_one :gall_traits, Gallformers.Galls.GallTraits, foreign_key: :species_id
    has_one :host_traits, Gallformers.Plants.HostTraits, foreign_key: :species_id
    has_many :species_sources, Gallformers.Species.SpeciesSource

    # Host relationships - this species as a gall
    has_many :host_relations, Gallformers.GallHosts.GallHost, foreign_key: :gall_species_id

    # Host relationships - this species as a host plant
    has_many :gall_relations, Gallformers.GallHosts.GallHost, foreign_key: :host_species_id

    many_to_many :aliases, Gallformers.Species.Alias,
      join_through: "alias_species",
      join_keys: [species_id: :id, alias_id: :id]

    many_to_many :taxonomies, Gallformers.Taxonomy.Taxonomy,
      join_through: "species_taxonomy",
      join_keys: [species_id: :id, taxonomy_id: :id]

    # Host range (where host plants exist)
    many_to_many :host_ranges, Gallformers.Places.Place,
      join_through: "host_range",
      join_keys: [species_id: :id, place_id: :id]

    # Gall range exclusions (places excluded from gall's range)
    many_to_many :gall_range_exclusions, Gallformers.Places.Place,
      join_through: "gall_range_exclusion",
      join_keys: [species_id: :id, place_id: :id]

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the appropriate range association based on taxoncode.
  For plants: host_ranges
  For galls: gall_range_exclusions (places to EXCLUDE)
  """
  def range_association(%__MODULE__{taxoncode: "plant"}), do: :host_ranges
  def range_association(%__MODULE__{taxoncode: "gall"}), do: :gall_range_exclusions
  def range_association(_), do: nil

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Creates a changeset for a species.
  """
  def changeset(species, attrs) do
    species
    |> cast(attrs, [:name, :taxoncode, :datacomplete, :abundance_id])
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 500)
    |> validate_inclusion(:taxoncode, taxoncodes())
    |> unique_constraint(:name)
  end

  @doc """
  Creates a changeset for a gall species, including gall_traits.
  """
  def gall_changeset(species, attrs) do
    species
    |> changeset(attrs)
    |> cast_assoc(:gall_traits, with: &GallTraits.changeset/2)
  end

  @doc """
  Returns the list of valid taxon codes.
  """
  def taxoncodes, do: ~w(gall plant undetermined)
end
