defmodule Gallformers.FilterFields do
  @moduledoc """
  The FilterFields context.

  Provides CRUD operations for filter field types used in the ID tool.
  Each filter type has its own table and schema:
  - Alignment: how galls are oriented on the host
  - Cells: internal cell structure
  - Color: visual color of galls
  - Form: overall form/type of gall
  - PlantPart: location on host plant where gall forms
  - Shape: morphological shape
  - Texture: surface texture
  - Walls: wall thickness

  Note: Seasons are fixed and should not be modified through this interface.
  """

  import Ecto.Query

  alias Gallformers.FilterFields.{
    Alignment,
    Cells,
    Color,
    Form,
    PlantPart,
    Shape,
    Texture,
    Walls
  }

  alias Gallformers.Repo

  @filter_types ~w(alignment cells color form plant_part shape texture walls)a

  @doc """
  Returns the list of valid filter types.
  """
  def filter_types, do: @filter_types

  @doc """
  Returns the schema module for the given filter type.
  """
  @spec schema_for(atom()) :: module()
  def schema_for(:alignment), do: Alignment
  def schema_for(:cells), do: Cells
  def schema_for(:color), do: Color
  def schema_for(:form), do: Form
  def schema_for(:plant_part), do: PlantPart
  def schema_for(:shape), do: Shape
  def schema_for(:texture), do: Texture
  def schema_for(:walls), do: Walls

  @doc """
  Returns the field name for the given filter type.
  Each schema uses a different field name (e.g., :color for Color, :shape for Shape).
  """
  @spec field_name_for(atom()) :: atom()
  def field_name_for(:alignment), do: :alignment
  def field_name_for(:cells), do: :cells
  def field_name_for(:color), do: :color
  def field_name_for(:form), do: :form
  def field_name_for(:plant_part), do: :part
  def field_name_for(:shape), do: :shape
  def field_name_for(:texture), do: :texture
  def field_name_for(:walls), do: :walls

  @doc """
  Returns true if the filter type has a description field.
  """
  @spec has_description?(atom()) :: boolean()
  def has_description?(:color), do: false
  def has_description?(_type), do: true

  # ============================================
  # Generic CRUD operations
  # ============================================

  @doc """
  Lists all items for the given filter type, ordered by name.
  """
  def list_all(filter_type) when filter_type in @filter_types do
    schema = schema_for(filter_type)
    field = field_name_for(filter_type)

    from(f in schema, order_by: ^[{:asc, field}])
    |> Repo.all()
  end

  @doc """
  Gets a single item by id for the given filter type.
  Raises if not found.
  """
  def get!(filter_type, id) when filter_type in @filter_types do
    schema = schema_for(filter_type)
    Repo.get!(schema, id)
  end

  @doc """
  Gets a single item by id for the given filter type.
  Returns nil if not found.
  """
  def get(filter_type, id) when filter_type in @filter_types do
    schema = schema_for(filter_type)
    Repo.get(schema, id)
  end

  @doc """
  Creates a new item for the given filter type.
  """
  def create(filter_type, attrs) when filter_type in @filter_types do
    schema = schema_for(filter_type)

    struct(schema)
    |> schema.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing item.
  """
  def update(filter_type, item, attrs) when filter_type in @filter_types do
    schema = schema_for(filter_type)

    item
    |> schema.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an item.
  """
  def delete(filter_type, item) when filter_type in @filter_types do
    Repo.delete(item)
  end

  @doc """
  Returns a changeset for tracking changes.
  """
  def change(filter_type, item, attrs \\ %{}) when filter_type in @filter_types do
    schema = schema_for(filter_type)
    schema.changeset(item, attrs)
  end

  @doc """
  Returns the display label for a filter type.
  """
  @spec type_label(atom()) :: String.t()
  def type_label(:alignment), do: "Alignments"
  def type_label(:cells), do: "Cells"
  def type_label(:color), do: "Colors"
  def type_label(:form), do: "Forms"
  def type_label(:plant_part), do: "Plant Parts"
  def type_label(:shape), do: "Shapes"
  def type_label(:texture), do: "Textures"
  def type_label(:walls), do: "Walls"

  @doc """
  Returns the singular label for a filter type.
  """
  @spec singular_label(atom()) :: String.t()
  def singular_label(:alignment), do: "Alignment"
  def singular_label(:cells), do: "Cells"
  def singular_label(:color), do: "Color"
  def singular_label(:form), do: "Form"
  def singular_label(:plant_part), do: "Plant Part"
  def singular_label(:shape), do: "Shape"
  def singular_label(:texture), do: "Texture"
  def singular_label(:walls), do: "Walls"

  @doc """
  Returns the count of items for the given filter type.
  """
  def count(filter_type) when filter_type in @filter_types do
    schema = schema_for(filter_type)
    Repo.aggregate(schema, :count, :id)
  end

  @doc """
  Returns counts for all filter types.
  """
  def all_counts do
    Enum.map(@filter_types, fn type ->
      {type, count(type)}
    end)
    |> Enum.into(%{})
  end
end
