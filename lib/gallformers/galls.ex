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
  alias Gallformers.Taxonomy.{TaxonName, TreeBuilder}

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
    # Use recursive CTE to walk from genus up through any intermediate ranks
    # (subfamily, tribe, etc.) to find the ancestor family. A direct parent_id
    # join only works when genus is an immediate child of family.
    {:ok, %{rows: rows}} =
      Repo.query(
        """
        WITH RECURSIVE genus_to_family AS (
          SELECT g.id AS genus_id, g.name AS genus_name, g.description AS genus_description,
                 g.parent_id AS current_parent_id
          FROM taxonomy g
          WHERE g.type = 'genus'

          UNION ALL

          SELECT gf.genus_id, gf.genus_name, gf.genus_description, t.parent_id
          FROM genus_to_family gf
          JOIN taxonomy t ON t.id = gf.current_parent_id
          WHERE t.type != 'family'
        )
        SELECT f.id, f.name, f.description,
               gf.genus_id, gf.genus_name, gf.genus_description,
               s.id, s.name, gt.undescribed
        FROM genus_to_family gf
        JOIN taxonomy f ON f.id = gf.current_parent_id AND f.type = 'family'
        JOIN species_taxonomy st ON st.taxonomy_id = gf.genus_id
        JOIN species s ON s.id = st.species_id AND s.taxoncode = 'gall'
        JOIN gall_traits gt ON gt.species_id = s.id
        WHERE f.description != 'Plant'
          AND (?1 = 0 OR gt.undescribed = 1)
        ORDER BY f.name, gf.genus_name, s.name
        """,
        [if(undescribed_only, do: 1, else: 0)]
      )

    Enum.map(rows, fn [fid, fname, fdesc, gid, gname, gdesc, sid, sname, undescribed] ->
      %{
        family_id: fid,
        family_name: fname,
        family_description: fdesc,
        genus_id: gid,
        genus_name: gname,
        genus_description: gdesc,
        species_id: sid,
        species_name: sname,
        undescribed: undescribed == 1
      }
    end)
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
          gallformers_code: gt.gallformers_code,
          range_confirmed: gt.range_confirmed,
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
    parsed = TaxonName.parse(gall.name || "")

    if parsed.epithet do
      prefix = "#{parsed.genus} #{parsed.epithet} "

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

  Silently enforces `undescribed: true` when the species is linked to an Unknown genus.
  """
  @spec update_gall_properties(integer(), map()) ::
          {:ok, GallTraits.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def update_gall_properties(species_id, attrs) do
    attrs = enforce_unknown_genus_floor(species_id, attrs)

    case Repo.get(GallTraits, species_id) do
      nil ->
        {:error, :not_found}

      gall_traits ->
        gall_traits
        |> GallTraits.changeset(attrs)
        |> Repo.update()
    end
  end

  # Extracts gall property attrs from params and updates, rolling back on error.
  # Use inside Repo.transaction to flatten nesting.
  defp update_gall_properties!(species_id, params) do
    case update_gall_properties(species_id, %{
           detachable: params.detachable,
           undescribed: params.undescribed,
           gallformers_code: params[:gallformers_code]
         }) do
      {:ok, result} -> result
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc """
  Checks whether a gallformers_code is already in use by another species.
  Returns the species_id of the owner if taken, nil if available.
  """
  @spec gallformers_code_taken?(String.t(), integer() | nil) :: integer() | nil
  def gallformers_code_taken?(code, exclude_species_id \\ nil)
  def gallformers_code_taken?(code, _) when code in [nil, ""], do: nil

  def gallformers_code_taken?(code, exclude_species_id) do
    query =
      from(gt in GallTraits,
        where: gt.gallformers_code == ^code,
        select: gt.species_id
      )

    query =
      if exclude_species_id,
        do: where(query, [gt], gt.species_id != ^exclude_species_id),
        else: query

    Repo.one(query)
  end

  # If the caller is trying to set undescribed=false but the species has an Unknown genus,
  # silently correct to undescribed=true.
  defp enforce_unknown_genus_floor(species_id, attrs) do
    undescribed = Map.get(attrs, :undescribed, Map.get(attrs, "undescribed"))

    if undescribed == false and has_unknown_genus?(species_id) do
      force_undescribed(attrs)
    else
      attrs
    end
  end

  defp has_unknown_genus?(species_id) do
    taxonomy = Gallformers.Taxonomy.get_taxonomy_for_species(species_id)
    taxonomy && Gallformers.Taxonomy.placeholder_genus_name?(taxonomy.genus.name)
  end

  # Preserve the key type (atom or string) used by the caller
  defp force_undescribed(attrs) do
    if Map.has_key?(attrs, :undescribed) do
      Map.put(attrs, :undescribed, true)
    else
      Map.put(attrs, "undescribed", true)
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
  # Undescribed Lock Logic
  # ============================================

  @doc """
  Computes whether the undescribed checkbox should be locked and why.

  A gall's undescribed flag is locked to `true` when:
  - The genus is a placeholder (Unknown) — species with unknown genus are always undescribed

  Returns `{locked?, reason}` where reason is a string explaining the lock, or nil if unlocked.
  Missing sources are handled by `compute_datacomplete_lock/1` instead.
  """
  @spec compute_undescribed_lock(Gallformers.Taxonomy.Lineage.t() | nil, integer() | nil) ::
          {boolean(), String.t() | nil}
  def compute_undescribed_lock(taxonomy, _species_id \\ nil) do
    genus_name = taxonomy && taxonomy.genus && taxonomy.genus.name

    if Gallformers.Taxonomy.placeholder_genus_name?(genus_name) do
      {true, "Undescribed is required for species with unknown genus."}
    else
      {false, nil}
    end
  end

  @doc """
  Returns true if the species has gall_traits with undescribed=true.
  """
  @spec undescribed?(integer()) :: boolean()
  def undescribed?(species_id) do
    case Repo.get(GallTraits, species_id) do
      %GallTraits{undescribed: true} -> true
      _ -> false
    end
  end

  @doc """
  Computes whether the datacomplete checkbox should be locked and why.

  A gall's datacomplete flag is locked to `false` when:
  - The species has no sources linked — a source is required for completeness
  - The gall is marked undescribed — undescribed species are by definition incomplete

  Returns `{locked?, reason}` where reason is a string explaining the lock, or nil if unlocked.
  """
  @spec compute_datacomplete_lock(integer() | nil) :: {boolean(), String.t() | nil}
  def compute_datacomplete_lock(nil), do: {false, nil}

  def compute_datacomplete_lock(species_id) do
    cond do
      not Gallformers.Sources.has_sources?(species_id) ->
        {true, "A source is required to mark a gall as data complete."}

      undescribed?(species_id) ->
        {true, "An undescribed gall cannot be marked as data complete."}

      true ->
        {false, nil}
    end
  end

  @doc """
  Forces undescribed=true if the given genus is a placeholder (Unknown).
  No-op if genus is not a placeholder or species has no gall_traits.
  """
  @spec force_undescribed_if_placeholder(integer(), integer()) :: :ok
  def force_undescribed_if_placeholder(species_id, genus_id) do
    genus = Gallformers.Taxonomy.get_taxonomy(genus_id)

    if genus && genus.is_placeholder do
      case Repo.get(GallTraits, species_id) do
        nil ->
          :ok

        gall_traits ->
          GallTraits.changeset(gall_traits, %{undescribed: true}) |> Repo.update!()
          :ok
      end
    else
      :ok
    end
  end

  # ============================================
  # Gall Traits Queries
  # ============================================

  @doc """
  Gets the gall_traits record for a species.
  """
  @spec get_gall_traits(integer()) :: GallTraits.t() | nil
  def get_gall_traits(species_id) do
    Repo.get(GallTraits, species_id)
  end

  @doc """
  Marks a gall's range as confirmed by an admin.

  Sets `range_confirmed = true` and `range_computed_at` to the current time.
  """
  @spec confirm_gall_range(integer()) :: {non_neg_integer(), nil}
  def confirm_gall_range(species_id) do
    from(gt in GallTraits, where: gt.species_id == ^species_id)
    |> Repo.update_all(
      set: [
        range_confirmed: true,
        range_computed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      ]
    )
  end

  @doc """
  Lists galls with their range confirmation status and counts.
  Used by the bulk range admin page.

  Options:
    - :unconfirmed_only (boolean, default true) - only show galls with range_confirmed = false
  """
  @spec list_galls_for_range_review(keyword()) :: [map()]
  def list_galls_for_range_review(opts \\ []) do
    unconfirmed_only = Keyword.get(opts, :unconfirmed_only, true)

    query =
      from s in Species,
        join: gt in GallTraits,
        on: gt.species_id == s.id,
        where: s.taxoncode == "gall",
        order_by: s.name,
        select: %{
          id: s.id,
          name: s.name,
          range_confirmed: gt.range_confirmed,
          range_computed_at: gt.range_computed_at,
          undescribed: gt.undescribed
        }

    query =
      if unconfirmed_only do
        from [s, gt] in query, where: gt.range_confirmed == false
      else
        query
      end

    results = Repo.all(query)

    # Batch load host counts and range counts
    gall_ids = Enum.map(results, & &1.id)
    host_counts = Gallformers.GallHosts.get_host_counts_for_galls(gall_ids)
    range_counts = get_range_counts_for_galls(gall_ids)

    Enum.map(results, fn gall ->
      gall
      |> Map.put(:host_count, Map.get(host_counts, gall.id, 0))
      |> Map.put(:range_count, Map.get(range_counts, gall.id, 0))
    end)
  end

  defp get_range_counts_for_galls([]), do: %{}

  defp get_range_counts_for_galls(gall_ids) do
    from(gr in "gall_range",
      where: gr.species_id in ^gall_ids,
      group_by: gr.species_id,
      select: {gr.species_id, count()}
    )
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Bulk confirms gall ranges for multiple gall species.
  Sets range_confirmed = true and range_computed_at = now() for all specified galls.
  """
  @spec bulk_confirm_gall_ranges([integer()]) :: {integer(), nil}
  def bulk_confirm_gall_ranges([]), do: {0, nil}

  def bulk_confirm_gall_ranges(species_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(gt in GallTraits,
      where: gt.species_id in ^species_ids
    )
    |> Repo.update_all(set: [range_confirmed: true, range_computed_at: now])
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

  # ============================================
  # Composite Save Operations
  # ============================================

  @doc """
  Creates a new gall species with all associations in a single transaction.

  Handles species creation, gall_traits, taxonomy linking, hosts, aliases,
  filter values, and gall properties (detachable/undescribed).

  ## Params

    * `:species_attrs` - Map of species attributes (name, taxoncode, etc.)
    * `:taxonomy` - Taxonomy map with genus info
    * `:genus_is_new` - Boolean, whether to create a new genus
    * `:parent_id` - Family or section ID for taxonomy linking
    * `:hosts` - List of host maps with `:host_species_id`
    * `:aliases` - List of alias maps with `:name` and `:type`
    * `:filter_values` - Map of filter type => list of filter value maps
    * `:detachable` - Detachable value string
    * `:undescribed` - Boolean undescribed flag

  Returns `{:ok, species}` or `{:error, changeset | reason}`.
  """
  @spec create_gall_with_associations(map()) ::
          {:ok, Species.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_gall_with_associations(params) do
    Repo.transaction(fn ->
      case Gallformers.Species.create_species(params.species_attrs) do
        {:ok, species} ->
          {:ok, _gall} = create_gall_traits(species.id)

          Gallformers.Taxonomy.link_species_taxonomy(
            species.id,
            params.taxonomy,
            params.genus_is_new,
            params.parent_id
          )

          for host <- params.hosts do
            Gallformers.GallHosts.add_host_to_gall(species.id, host.host_species_id)
          end

          for a <- params.aliases do
            Gallformers.Species.create_alias_for_species(species.id, %{
              name: a.name,
              type: a.type
            })
          end

          sync_filter_values(species.id, empty_filter_values(), params.filter_values)

          update_gall_properties!(species.id, params)
          species

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Updates a gall species with all associations in a single transaction.

  Handles species update, alias changes, host changes, filter changes,
  gall properties, and species timestamp touch.

  ## Params

    * `:species_attrs` - Map of species attributes to update
    * `:alias_changes` - Tuple `{to_add, to_remove}` from DeferredChanges
    * `:host_changes` - Tuple `{to_add, to_remove}` from DeferredChanges
    * `:original_filter_values` - Original filter values map for diffing
    * `:filter_values` - Current filter values map
    * `:detachable` - Detachable value string
    * `:undescribed` - Boolean undescribed flag

  Returns `{:ok, species}` or `{:error, changeset | reason}`.
  """
  @spec update_gall_with_associations(Species.t(), map()) ::
          {:ok, Species.t()} | {:error, Ecto.Changeset.t() | term()}
  def update_gall_with_associations(species, params) do
    {aliases_to_add, aliases_to_remove} = params.alias_changes
    {hosts_to_add, hosts_to_remove} = params.host_changes

    Repo.transaction(fn ->
      case Gallformers.Species.update_species(species, params.species_attrs) do
        {:ok, updated_species} ->
          save_alias_changes(species.id, aliases_to_add, aliases_to_remove)
          save_host_changes(species.id, hosts_to_add, hosts_to_remove)

          sync_filter_values(
            species.id,
            params.original_filter_values,
            params.filter_values
          )

          update_gall_properties!(species.id, params)
          Gallformers.Species.touch(species.id)
          updated_species

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Syncs filter values for a gall by computing set differences and issuing
  add/remove calls for each filter type.
  """
  @spec sync_filter_values(integer(), map(), map()) :: :ok
  def sync_filter_values(gall_id, original_values, current_values) do
    filter_types = [
      :colors,
      :shapes,
      :textures,
      :alignments,
      :walls,
      :cells,
      :plant_parts,
      :forms,
      :seasons
    ]

    for filter_type <- filter_types do
      original = Map.get(original_values, filter_type, [])
      current = Map.get(current_values, filter_type, [])

      original_ids = MapSet.new(Enum.map(original, & &1.id))
      current_ids = MapSet.new(Enum.map(current, & &1.id))

      for filter_id <- MapSet.difference(original_ids, current_ids) do
        remove_filter_field_from_gall(gall_id, filter_type, filter_id)
      end

      for filter_id <- MapSet.difference(current_ids, original_ids) do
        add_filter_field_to_gall(gall_id, filter_type, filter_id)
      end
    end

    :ok
  end

  defp empty_filter_values do
    %{
      colors: [],
      shapes: [],
      textures: [],
      alignments: [],
      walls: [],
      cells: [],
      plant_parts: [],
      forms: [],
      seasons: []
    }
  end

  defp save_alias_changes(species_id, to_add, to_remove) do
    for alias_id <- to_remove do
      Gallformers.Species.remove_alias_from_species(species_id, alias_id)
    end

    for a <- to_add do
      Gallformers.Species.create_alias_for_species(species_id, %{name: a.name, type: a.type})
    end
  end

  defp save_host_changes(species_id, to_add, to_remove) do
    for relation_id <- to_remove do
      Gallformers.GallHosts.remove_host_from_gall(relation_id)
    end

    for host <- to_add do
      Gallformers.GallHosts.add_host_to_gall(species_id, host.host_species_id)
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
