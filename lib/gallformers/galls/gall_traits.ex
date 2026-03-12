defmodule Gallformers.Galls.GallTraits do
  @moduledoc """
  Ecto schema for the gall_traits table (1:1 extension of species).

  This table stores gall-specific attributes for species with taxoncode='gall'.
  Uses Class Table Inheritance pattern: species_id is both PK and FK.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour Gallformers.SchemaFields

  @required_fields [:species_id]
  @optional_fields [
    :detachable,
    :undescribed,
    :gallformers_code,
    :range_confirmed,
    :range_computed_at
  ]

  @type t :: %__MODULE__{
          species_id: integer(),
          detachable: String.t() | nil,
          undescribed: boolean(),
          gallformers_code: String.t() | nil,
          range_confirmed: boolean(),
          range_computed_at: DateTime.t() | nil
        }

  @primary_key {:species_id, :integer, autogenerate: false}
  @derive {Phoenix.Param, key: :species_id}

  schema "gall_traits" do
    # Gall-specific columns
    field :detachable, :string
    field :undescribed, :boolean, default: false
    field :gallformers_code, :string
    field :range_confirmed, :boolean, default: false
    field :range_computed_at, :utc_datetime, default: nil

    # 1:1 relationship to species
    belongs_to :species, Gallformers.Species.Species,
      foreign_key: :species_id,
      references: :id,
      define_field: false

    # Multi-value traits (junction tables)
    many_to_many :colors, Gallformers.FilterFields.Color,
      join_through: "gall_color",
      join_keys: [species_id: :species_id, color_id: :id]

    many_to_many :walls, Gallformers.FilterFields.Walls,
      join_through: "gall_walls",
      join_keys: [species_id: :species_id, walls_id: :id]

    many_to_many :cells, Gallformers.FilterFields.Cells,
      join_through: "gall_cells",
      join_keys: [species_id: :species_id, cells_id: :id]

    many_to_many :shapes, Gallformers.FilterFields.Shape,
      join_through: "gall_shape",
      join_keys: [species_id: :species_id, shape_id: :id]

    many_to_many :textures, Gallformers.FilterFields.Texture,
      join_through: "gall_texture",
      join_keys: [species_id: :species_id, texture_id: :id]

    many_to_many :alignments, Gallformers.FilterFields.Alignment,
      join_through: "gall_alignment",
      join_keys: [species_id: :species_id, alignment_id: :id]

    many_to_many :plant_parts, Gallformers.FilterFields.PlantPart,
      join_through: "gall_plant_part",
      join_keys: [species_id: :species_id, plant_part_id: :id]

    many_to_many :forms, Gallformers.FilterFields.Form,
      join_through: "gall_form",
      join_keys: [species_id: :species_id, form_id: :id]

    many_to_many :seasons, Gallformers.FilterFields.Season,
      join_through: "gall_season",
      join_keys: [species_id: :species_id, season_id: :id]
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @impl Gallformers.SchemaFields
  def required_associations, do: []

  @doc """
  Creates a changeset for gall traits.

  Valid detachable values: "unknown", "integral", "detachable", "both"
  """
  def changeset(gall_traits, attrs) do
    gall_traits
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:detachable, ~w(unknown integral detachable both),
      message: "must be one of: unknown, integral, detachable, both"
    )
    |> foreign_key_constraint(:species_id)
    |> unique_constraint(:gallformers_code, name: :gall_traits_gallformers_code_unique)
  end
end
