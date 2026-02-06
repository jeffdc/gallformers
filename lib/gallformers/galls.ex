defmodule Gallformers.Galls do
  @moduledoc """
  The Galls context.

  Manages gall species (Species with taxoncode='gall') and their traits.
  Galls are abnormal plant growths induced by insects, mites, and other organisms.

  For gall↔host relationships, see `Gallformers.GallHosts`.
  For gall summaries and descriptions, see `Gallformers.Galls.Summary`.
  For gall identification filtering, see `Gallformers.Galls.Identification`.
  """

  import Ecto.Query

  alias Gallformers.FilterFields.{
    Alignment,
    Cells,
    Color,
    Form,
    PlantPart,
    Season,
    Shape,
    Texture,
    Walls
  }

  alias Gallformers.Galls.{GallTraits, Identification}
  alias Gallformers.Images.Image
  alias Gallformers.Repo
  alias Gallformers.Species.{Abundance, Species}
  alias Gallformers.Taxonomy.{Taxonomy, TreeBuilder}

  @topic "galls"

  # ============================================
  # Identification (filter pipeline)
  # ============================================

  defdelegate filter_galls(filters \\ %{}), to: Identification
  defdelegate count_filtered_galls(filters \\ %{}), to: Identification
  defdelegate get_hosts_for_filters(filters \\ %{}), to: Identification
  defdelegate get_filter_options(), to: Identification
  defdelegate get_summary_data(gall_ids), to: Identification
  defdelegate leaf_plant_part_ids(), to: Identification

  # ============================================
  # Explore Tree
  # ============================================

  @doc """
  Returns a hierarchical tree of gall species organized by Family → Genus → Species.

  ## Options
  - `:key_style` - `:short` for `f-123` format (default), `:long` for `family-123` format
  """
  @spec get_galls_tree(keyword()) :: [map()]
  def get_galls_tree(opts \\ []) do
    fetch_gall_tree_data(false)
    |> TreeBuilder.build_tree("/gall/", opts)
  end

  @doc """
  Returns a hierarchical tree of undescribed gall species.

  ## Options
  - `:key_style` - `:short` for `f-123` format (default), `:long` for `family-123` format
  """
  @spec get_undescribed_tree(keyword()) :: [map()]
  def get_undescribed_tree(opts \\ []) do
    fetch_gall_tree_data(true)
    |> TreeBuilder.build_tree("/gall/", opts)
  end

  defp fetch_gall_tree_data(undescribed_only) do
    base_query =
      from f in Taxonomy,
        join: g in Taxonomy,
        on: g.parent_id == f.id and g.type == "genus",
        join: st in "species_taxonomy",
        on: st.taxonomy_id == g.id,
        join: s in Species,
        on: s.id == st.species_id,
        join: gt in GallTraits,
        on: gt.species_id == s.id,
        where: f.type == "family" and f.description != "Plant" and s.taxoncode == "gall",
        order_by: [f.name, g.name, s.name],
        select: %{
          family_id: f.id,
          family_name: f.name,
          family_description: f.description,
          genus_id: g.id,
          genus_name: g.name,
          genus_description: g.description,
          species_id: s.id,
          species_name: s.name,
          undescribed: gt.undescribed
        }

    query =
      if undescribed_only do
        from [f, g, st, s, gt] in base_query,
          where: gt.undescribed == true
      else
        base_query
      end

    Repo.all(query)
  end

  # ============================================
  # Query Functions
  # ============================================

  @doc """
  Returns a random gall with its first image (lowest sort_order).

  Used on the home page to show a featured gall. Returns a map with:
    - id: species ID
    - name: species name
    - undescribed: whether the gall is undescribed
    - image_url: full CloudFront URL
    - image_creator: photographer credit
    - image_license: license name

  Returns `nil` if no galls with images are found.
  """
  @spec random_gall() :: map() | nil
  def random_gall do
    # Subquery to find the minimum sort_order for each species
    min_sort_query =
      from i in Image,
        group_by: i.species_id,
        select: %{species_id: i.species_id, min_sort: min(i.sort_order)}

    query =
      from s in Species,
        join: gt in GallTraits,
        on: gt.species_id == s.id,
        join: ms in subquery(min_sort_query),
        on: ms.species_id == s.id,
        join: i in Image,
        on: i.species_id == s.id and i.sort_order == ms.min_sort,
        where: s.taxoncode == "gall",
        order_by: fragment("RANDOM()"),
        limit: 1,
        select: %{
          id: s.id,
          name: s.name,
          undescribed: gt.undescribed,
          image_path: i.path,
          image_creator: i.creator,
          image_license: i.license,
          image_sourcelink: i.sourcelink,
          image_licenselink: i.licenselink
        }

    case Repo.one(query) do
      nil ->
        nil

      result ->
        Map.put(result, :image_url, Image.base_url() <> "/" <> result.image_path)
    end
  end

  @doc """
  Returns all gall species ordered by name.
  """
  @spec list_galls() :: [map()]
  def list_galls do
    from(s in Species,
      left_join: gt in GallTraits,
      on: gt.species_id == s.id,
      left_join: a in Abundance,
      on: s.abundance_id == a.id,
      where: s.taxoncode == "gall",
      order_by: s.name,
      select: %{
        id: s.id,
        name: s.name,
        taxoncode: s.taxoncode,
        datacomplete: s.datacomplete,
        abundance_id: s.abundance_id,
        abundance_name: a.abundance,
        detachable: gt.detachable,
        undescribed: gt.undescribed
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns paginated gall species.
  """
  @spec list_galls_paginated(integer(), integer()) :: [map()]
  def list_galls_paginated(limit, offset) do
    from(s in Species,
      left_join: gt in GallTraits,
      on: gt.species_id == s.id,
      left_join: a in Abundance,
      on: s.abundance_id == a.id,
      where: s.taxoncode == "gall",
      order_by: s.name,
      limit: ^limit,
      offset: ^offset,
      select: %{
        id: s.id,
        name: s.name,
        taxoncode: s.taxoncode,
        datacomplete: s.datacomplete,
        abundance_id: s.abundance_id,
        abundance_name: a.abundance,
        detachable: gt.detachable,
        undescribed: gt.undescribed
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns the count of all gall species.
  """
  @spec count_galls() :: integer()
  def count_galls do
    from(s in Species,
      where: s.taxoncode == "gall",
      select: count(s.id)
    )
    |> Repo.one()
  end

  @doc """
  Gets the count of galls that are undescribed.
  """
  @spec count_undescribed_galls() :: integer()
  def count_undescribed_galls do
    from(s in Species,
      join: gt in GallTraits,
      on: gt.species_id == s.id,
      where: gt.undescribed == true,
      select: count(s.id)
    )
    |> Repo.one()
  end

  @doc """
  Gets a gall by species ID with all related data.
  """
  @spec get_gall(integer()) :: map() | nil
  def get_gall(id) do
    query =
      from s in Species,
        left_join: gt in GallTraits,
        on: gt.species_id == s.id,
        left_join: a in Abundance,
        on: s.abundance_id == a.id,
        where: s.id == ^id and s.taxoncode == "gall",
        select: %{
          id: s.id,
          name: s.name,
          taxoncode: s.taxoncode,
          gall_id: s.id,
          datacomplete: s.datacomplete,
          abundance_id: s.abundance_id,
          abundance_name: a.abundance,
          detachable: gt.detachable,
          undescribed: gt.undescribed,
          inserted_at: s.inserted_at,
          updated_at: s.updated_at
        }

    Repo.one(query)
  end

  @doc """
  Gets a gall by species name.
  """
  @spec get_gall_by_name(String.t()) :: map() | nil
  def get_gall_by_name(name) do
    query =
      from s in Species,
        left_join: gt in GallTraits,
        on: gt.species_id == s.id,
        left_join: a in Abundance,
        on: s.abundance_id == a.id,
        where: s.name == ^name and s.taxoncode == "gall",
        select: %{
          id: s.id,
          name: s.name,
          taxoncode: s.taxoncode,
          datacomplete: s.datacomplete,
          abundance_id: s.abundance_id,
          abundance_name: a.abundance,
          detachable: gt.detachable,
          undescribed: gt.undescribed
        }

    Repo.one(query)
  end

  @doc """
  Gets default images for all gall species (used by ID tool).

  Returns the first image (by sort_order) for each gall species.
  """
  @spec get_default_gall_images() :: [map()]
  def get_default_gall_images do
    from(i in Image,
      join: s in Species,
      on: i.species_id == s.id,
      where: s.taxoncode == "gall",
      where:
        fragment(
          "? = (SELECT MIN(i2.sort_order) FROM image i2 WHERE i2.species_id = ?)",
          i.sort_order,
          i.species_id
        ),
      select: %{
        species_id: i.species_id,
        path: i.path
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns related galls - other galls that share the same genus and species name prefix.

  For a gall like "Callirhytis seminator leaf gall", this finds other galls starting with
  "Callirhytis seminator " (note the trailing space to ensure it's not a prefix match
  of a different species like "Callirhytis seminatoris").

  Returns a list of maps with :id and :name keys, excluding the passed-in gall.
  """
  @spec get_related_galls(map()) :: [map()]
  def get_related_galls(gall) when is_map(gall) do
    name = gall.name || ""
    name_parts = String.split(name, " ", parts: 3)

    if length(name_parts) >= 2 do
      # Match on "Genus species " with trailing space to avoid false positives
      prefix = "#{Enum.at(name_parts, 0)} #{Enum.at(name_parts, 1)} "

      from(s in Species,
        where: fragment("? LIKE ?", s.name, ^"#{prefix}%"),
        where: s.id != ^gall.id,
        where: s.taxoncode == "gall",
        order_by: s.name,
        select: %{id: s.id, name: s.name}
      )
      |> Repo.all()
    else
      []
    end
  end

  # ============================================
  # Filter / Trait Functions
  # ============================================

  @doc """
  Gets a gall for editing with all filter field values.
  Returns a map with gall data and current filter selections.
  """
  @spec get_gall_for_admin_edit(integer()) :: map() | nil
  def get_gall_for_admin_edit(species_id) do
    gall_data = get_gall(species_id)

    if gall_data do
      filter_values = get_gall_filter_values(species_id)

      Map.merge(gall_data, %{
        filter_values: filter_values
      })
    else
      nil
    end
  end

  @doc """
  Gets all filter field values for a gall as maps with :id and :field keys.
  All traits return lists (may be empty).
  """
  @spec get_gall_filter_values(integer()) :: map()
  def get_gall_filter_values(species_id) do
    %{
      colors:
        get_filter_values_for_gall(
          species_id,
          "gall_color",
          :color_id,
          Color,
          :color
        ),
      walls:
        get_filter_values_for_gall(
          species_id,
          "gall_walls",
          :walls_id,
          Walls,
          :walls
        ),
      cells:
        get_filter_values_for_gall(
          species_id,
          "gall_cells",
          :cells_id,
          Cells,
          :cells
        ),
      shapes:
        get_filter_values_for_gall(
          species_id,
          "gall_shape",
          :shape_id,
          Shape,
          :shape
        ),
      textures:
        get_filter_values_for_gall(
          species_id,
          "gall_texture",
          :texture_id,
          Texture,
          :texture
        ),
      alignments:
        get_filter_values_for_gall(
          species_id,
          "gall_alignment",
          :alignment_id,
          Alignment,
          :alignment
        ),
      plant_parts:
        get_filter_values_for_gall(
          species_id,
          "gall_plant_part",
          :plant_part_id,
          PlantPart,
          :part
        ),
      forms:
        get_filter_values_for_gall(
          species_id,
          "gall_form",
          :form_id,
          Form,
          :form
        ),
      seasons:
        get_filter_values_for_gall(
          species_id,
          "gall_season",
          :season_id,
          Season,
          :season
        )
    }
  end

  defp get_filter_values_for_gall(species_id, join_table, fk_col, schema, field)
       when is_atom(fk_col) do
    from(j in join_table,
      join: s in ^schema,
      on: field(j, ^fk_col) == s.id,
      where: j.species_id == ^species_id,
      select: %{id: s.id, field: field(s, ^field)}
    )
    |> Repo.all()
  end

  @doc """
  Gets filter values for multiple gall species in bulk (batch version).

  Returns a map of species_id => %{colors: [...], shapes: [...], ...}.
  Runs 9 queries total instead of 9 per species.
  """
  @spec get_gall_filter_values_batch([integer()]) :: %{integer() => map()}
  def get_gall_filter_values_batch([]), do: %{}

  def get_gall_filter_values_batch(species_ids) do
    # Fetch all filter values in 9 bulk queries
    colors = get_filter_values_batch(species_ids, "gall_color", :color_id, Color, :color)
    walls = get_filter_values_batch(species_ids, "gall_walls", :walls_id, Walls, :walls)
    cells = get_filter_values_batch(species_ids, "gall_cells", :cells_id, Cells, :cells)
    shapes = get_filter_values_batch(species_ids, "gall_shape", :shape_id, Shape, :shape)

    textures =
      get_filter_values_batch(species_ids, "gall_texture", :texture_id, Texture, :texture)

    alignments =
      get_filter_values_batch(species_ids, "gall_alignment", :alignment_id, Alignment, :alignment)

    plant_parts =
      get_filter_values_batch(species_ids, "gall_plant_part", :plant_part_id, PlantPart, :part)

    forms = get_filter_values_batch(species_ids, "gall_form", :form_id, Form, :form)
    seasons = get_filter_values_batch(species_ids, "gall_season", :season_id, Season, :season)

    # Combine into per-species maps
    species_ids
    |> Enum.map(fn id ->
      {id,
       %{
         colors: Map.get(colors, id, []),
         walls: Map.get(walls, id, []),
         cells: Map.get(cells, id, []),
         shapes: Map.get(shapes, id, []),
         textures: Map.get(textures, id, []),
         alignments: Map.get(alignments, id, []),
         plant_parts: Map.get(plant_parts, id, []),
         forms: Map.get(forms, id, []),
         seasons: Map.get(seasons, id, [])
       }}
    end)
    |> Enum.into(%{})
  end

  defp get_filter_values_batch(species_ids, join_table, fk_col, schema, field) do
    from(j in join_table,
      join: s in ^schema,
      on: field(j, ^fk_col) == s.id,
      where: j.species_id in ^species_ids,
      select: {j.species_id, field(s, ^field)}
    )
    |> Repo.all()
    |> Enum.group_by(fn {species_id, _val} -> species_id end, fn {_id, val} -> val end)
  end

  @doc """
  Updates gall properties (detachable, undescribed).
  """
  @spec update_gall_properties(integer(), map()) ::
          {:ok, GallTraits.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def update_gall_properties(species_id, attrs) do
    case Repo.get(GallTraits, species_id) do
      nil ->
        {:error, :not_found}

      gall_traits ->
        gall_traits
        |> GallTraits.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Adds a filter field to a gall.
  """
  @spec add_filter_field_to_gall(integer(), atom(), integer()) :: {:ok, any()} | {:error, any()}
  def add_filter_field_to_gall(species_id, filter_type, filter_id) do
    {join_table, fk_col} = get_join_table_info(filter_type)
    row = Map.new([{:species_id, species_id}, {fk_col, filter_id}])

    try do
      Repo.insert_all(join_table, [row])
      {:ok, :inserted}
    rescue
      e in Ecto.ConstraintError ->
        {:error, e}
    end
  end

  @doc """
  Removes a filter field from a gall.
  """
  @spec remove_filter_field_from_gall(integer(), atom(), integer()) :: {:ok, integer()}
  def remove_filter_field_from_gall(species_id, filter_type, filter_id) do
    {join_table, fk_col} = get_join_table_info(filter_type)

    {count, _} =
      from(j in join_table,
        where: j.species_id == ^species_id and field(j, ^fk_col) == ^filter_id
      )
      |> Repo.delete_all()

    {:ok, count}
  end

  defp get_join_table_info(:colors), do: {"gall_color", :color_id}
  defp get_join_table_info(:walls), do: {"gall_walls", :walls_id}
  defp get_join_table_info(:cells), do: {"gall_cells", :cells_id}
  defp get_join_table_info(:shapes), do: {"gall_shape", :shape_id}
  defp get_join_table_info(:textures), do: {"gall_texture", :texture_id}
  defp get_join_table_info(:alignments), do: {"gall_alignment", :alignment_id}
  defp get_join_table_info(:plant_parts), do: {"gall_plant_part", :plant_part_id}
  defp get_join_table_info(:forms), do: {"gall_form", :form_id}
  defp get_join_table_info(:seasons), do: {"gall_season", :season_id}

  @doc """
  Returns all filter field options for gall admin.
  """
  @spec get_all_filter_options() :: map()
  def get_all_filter_options do
    %{
      colors:
        Gallformers.FilterFields.list_all(:color) |> Enum.map(&%{id: &1.id, field: &1.color}),
      shapes:
        Gallformers.FilterFields.list_all(:shape) |> Enum.map(&%{id: &1.id, field: &1.shape}),
      textures:
        Gallformers.FilterFields.list_all(:texture) |> Enum.map(&%{id: &1.id, field: &1.texture}),
      alignments:
        Gallformers.FilterFields.list_all(:alignment)
        |> Enum.map(&%{id: &1.id, field: &1.alignment}),
      walls:
        Gallformers.FilterFields.list_all(:walls) |> Enum.map(&%{id: &1.id, field: &1.walls}),
      cells:
        Gallformers.FilterFields.list_all(:cells) |> Enum.map(&%{id: &1.id, field: &1.cells}),
      plant_parts:
        Gallformers.FilterFields.list_all(:plant_part) |> Enum.map(&%{id: &1.id, field: &1.part}),
      forms: Gallformers.FilterFields.list_all(:form) |> Enum.map(&%{id: &1.id, field: &1.form}),
      seasons: get_all_seasons()
    }
  end

  defp get_all_seasons do
    from(s in Season,
      order_by: s.id,
      select: %{id: s.id, field: s.season}
    )
    |> Repo.all()
  end

  # ============================================
  # CRUD Operations
  # ============================================

  @doc """
  Creates a gall_traits record for a species.

  Should be called after creating a species with taxoncode "gall".

  Returns {:ok, gall_traits} on success, {:error, changeset} on failure.
  """
  @spec create_gall_traits(integer()) :: {:ok, GallTraits.t()} | {:error, Ecto.Changeset.t()}
  def create_gall_traits(species_id) do
    %GallTraits{species_id: species_id}
    |> GallTraits.changeset(%{detachable: "unknown", undescribed: false})
    |> Repo.insert()
  end

  @doc """
  Deletes gall_traits record for a species.

  Called during species deletion cascade to clean up filter associations.
  """
  @spec delete_gall_traits(integer()) :: {non_neg_integer(), nil}
  def delete_gall_traits(species_id) do
    from(gt in GallTraits, where: gt.species_id == ^species_id)
    |> Repo.delete_all()
  end

  @doc """
  Deletes a gall species and all associations.

  Performs a complete cleanup in the correct order:
  1. Deletes S3 images (before DB cascade removes image paths)
  2. Deletes gall_traits (cascades to filter associations)
  3. Deletes FTS index entry
  4. Deletes the species (cascades to image rows, host relations, etc.)

  Returns {:ok, species} on success or {:error, reason} on failure.
  """
  @spec delete_gall(integer()) ::
          {:ok, Species.t()} | {:error, :not_found | Ecto.Changeset.t() | term()}
  def delete_gall(gall_id) do
    case Repo.get(Species, gall_id) do
      nil ->
        {:error, :not_found}

      %{taxoncode: "gall"} = gall ->
        Repo.transaction(fn -> do_delete_gall(gall) end)

      _not_a_gall ->
        {:error, :not_a_gall}
    end
  end

  defp do_delete_gall(gall) do
    # 1. Delete S3 images first (before DB records are cascade deleted)
    Gallformers.Images.delete_images_from_s3_for_species(gall.id)

    # 2. Delete gall_traits (cascades to filter associations)
    delete_gall_traits(gall.id)

    # 3. Delete from FTS index
    Gallformers.Species.delete_species_fts(gall.id)

    # 4. Delete the species record (cascades to image rows, host relations, etc.)
    case Repo.delete(gall) do
      {:ok, deleted} -> deleted
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  # ============================================
  # PubSub
  # ============================================

  @doc """
  Subscribes to gall changes.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Gallformers.PubSub, @topic)
  end

  @doc """
  Broadcasts a gall change event.
  """
  @spec broadcast_change(map(), atom()) :: {:ok, map()}
  def broadcast_change(gall, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, @topic, {event, gall})
    {:ok, gall}
  end
end
