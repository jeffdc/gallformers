defmodule Gallformers.Taxonomy.Taxonomy do
  @moduledoc """
  Ecto schema for the taxonomy table.

  Represents a taxonomic classification (family, genus, species, etc.)
  with a hierarchical parent-child relationship.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour Gallformers.SchemaFields

  @required_fields [:name, :type]

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          type: String.t() | nil,
          parent_id: integer() | nil,
          is_placeholder: boolean()
        }

  @taxonomy_types ~w(family genus section)

  schema "taxonomy" do
    field :name, :string
    # Description is optional - stores common names (e.g., "Oaks" for Quercus)
    # or classification type (e.g., "Plant" vs "Wasp" for families)
    field :description, :string
    field :type, :string
    field :is_placeholder, :boolean, default: false

    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id

    many_to_many :species, Gallformers.Species.Species,
      join_through: "species_taxonomy",
      join_keys: [taxonomy_id: :id, species_id: :id]

    many_to_many :aliases, Gallformers.Species.Alias,
      join_through: "taxonomy_alias",
      join_keys: [taxonomy_id: :id, alias_id: :id]

    timestamps(type: :utc_datetime)
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Creates a changeset for a taxonomy.
  """
  def changeset(taxonomy, attrs) do
    taxonomy
    |> cast(attrs, [:name, :description, :type, :parent_id, :is_placeholder])
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @taxonomy_types)
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint([:name, :parent_id],
      name: :idx_taxonomy_name_parent,
      message: "already exists for this parent"
    )
    |> foreign_key_constraint(:parent_id)
  end

  @doc """
  Generates a display name for a placeholder "Unknown" taxonomy entry.

  Examples:
    - Unknown family → "Unknown"
    - Unknown genus in Cynipidae → "Unknown (Cynipidae)"
  """
  def display_name(%__MODULE__{is_placeholder: true, parent: %{name: parent_name}}) do
    "Unknown (#{parent_name})"
  end

  def display_name(%__MODULE__{is_placeholder: true}) do
    "Unknown"
  end

  def display_name(%__MODULE__{name: name}) do
    name
  end

  @doc """
  Returns the list of valid taxonomy types.
  """
  def taxonomy_types, do: @taxonomy_types
end
