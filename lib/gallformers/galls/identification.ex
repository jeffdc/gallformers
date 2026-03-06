defmodule Gallformers.Galls.Identification do
  @moduledoc """
  Composable filter pipeline for gall identification.

  Internal module of the Galls context — provides the filter engine used by
  the ID tool. All public access goes through `Gallformers.Galls`.
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

  alias Gallformers.GallHosts.GallHost
  alias Gallformers.Galls
  alias Gallformers.Galls.GallTraits
  alias Gallformers.Images.Image
  alias Gallformers.Places
  alias Gallformers.Ranges
  alias Gallformers.Repo
  alias Gallformers.Species.Species, as: SpeciesSchema
  alias Gallformers.Taxonomy.Taxonomy

  @doc """
  Returns all filter field options for the ID tool.
  """
  @spec get_filter_options() :: map()
  def get_filter_options do
    %{
      alignments: Repo.all(from(a in Alignment, order_by: a.alignment)),
      cells: Repo.all(from(c in Cells, order_by: c.cells)),
      colors: Repo.all(from(c in Color, order_by: c.color)),
      forms: Repo.all(from(f in Form, order_by: f.form)),
      plant_parts: Repo.all(from(pp in PlantPart, order_by: pp.part)),
      seasons: Repo.all(from(s in Season, order_by: s.season)),
      shapes: Repo.all(from(s in Shape, order_by: s.shape)),
      textures: Repo.all(from(t in Texture, order_by: t.texture)),
      walls: Repo.all(from(w in Walls, order_by: w.walls))
    }
  end

  @doc """
  Filters galls based on the provided criteria.

  Accepts a map with optional keys:
    - :host_ids - list of host species IDs
    - :genus_id - taxonomy ID of a host plant genus/section
    - :family_id - taxonomy ID of a gall family
    - :plant_part_ids - list of plant part IDs
    - :plant_part_logic - :or (default) or :and
    - :color_ids - list of color IDs
    - :shape_ids - list of shape IDs
    - :texture_ids - list of texture IDs
    - :texture_logic - :or (default) or :and
    - :alignment_ids - list of alignment IDs
    - :cells_ids - list of cells IDs
    - :walls_ids - list of walls IDs
    - :form_ids - list of form IDs
    - :season_ids - list of season IDs
    - :detachable - "unknown", "integral", "detachable", or "both"
    - :place_codes - list of place codes (states/provinces)
    - :undescribed - boolean
    - :exclude_non_galls - boolean

  Returns a list of matching gall species maps.
  """
  @spec filter_galls(map()) :: [map()]
  def filter_galls(filters \\ %{}) do
    base_query()
    |> apply_host_filter(filters[:host_ids])
    |> apply_genus_filter(filters[:genus_id])
    |> apply_family_filter(filters[:family_id])
    |> apply_plant_part_filter(filters[:plant_part_ids], filters[:plant_part_logic] || :or)
    |> apply_color_filter(filters[:color_ids])
    |> apply_shape_filter(filters[:shape_ids])
    |> apply_texture_filter(filters[:texture_ids], filters[:texture_logic] || :or)
    |> apply_alignment_filter(filters[:alignment_ids])
    |> apply_cells_filter(filters[:cells_ids])
    |> apply_walls_filter(filters[:walls_ids])
    |> apply_form_filter(filters[:form_ids])
    |> apply_season_filter(filters[:season_ids])
    |> apply_detachable_filter(filters[:detachable])
    |> apply_place_filter(filters[:place_codes], filters[:host_ids], filters[:genus_id])
    |> apply_undescribed_filter(filters[:undescribed])
    |> apply_exclude_non_gall_filter(filters[:exclude_non_galls])
    |> select_gall_fields()
    |> Repo.all()
    |> attach_images()
    |> attach_non_gall_flag()
    |> attach_place_match(filters[:place_codes])
  end

  @doc """
  Returns the count of galls matching the filters.
  """
  @spec count_filtered_galls(map()) :: integer()
  def count_filtered_galls(filters \\ %{}) do
    base_query()
    |> apply_host_filter(filters[:host_ids])
    |> apply_plant_part_filter(filters[:plant_part_ids], filters[:plant_part_logic] || :or)
    |> apply_color_filter(filters[:color_ids])
    |> apply_shape_filter(filters[:shape_ids])
    |> apply_texture_filter(filters[:texture_ids], filters[:texture_logic] || :or)
    |> apply_alignment_filter(filters[:alignment_ids])
    |> apply_cells_filter(filters[:cells_ids])
    |> apply_walls_filter(filters[:walls_ids])
    |> apply_form_filter(filters[:form_ids])
    |> apply_season_filter(filters[:season_ids])
    |> apply_detachable_filter(filters[:detachable])
    |> apply_place_filter(filters[:place_codes], filters[:host_ids], nil)
    |> select([s, gt], count(s.id, :distinct))
    |> Repo.one()
  end

  @doc """
  Gets hosts that have galls matching the filters.

  Used to show which hosts are available based on current filter selections.
  """
  @spec get_hosts_for_filters(map()) :: [map()]
  def get_hosts_for_filters(filters \\ %{}) do
    gall_ids =
      base_query()
      |> apply_plant_part_filter(filters[:plant_part_ids], filters[:plant_part_logic] || :or)
      |> apply_color_filter(filters[:color_ids])
      |> apply_shape_filter(filters[:shape_ids])
      |> apply_texture_filter(filters[:texture_ids], filters[:texture_logic] || :or)
      |> apply_alignment_filter(filters[:alignment_ids])
      |> apply_cells_filter(filters[:cells_ids])
      |> apply_walls_filter(filters[:walls_ids])
      |> apply_form_filter(filters[:form_ids])
      |> apply_season_filter(filters[:season_ids])
      |> apply_detachable_filter(filters[:detachable])
      |> apply_place_filter(filters[:place_codes], nil, nil)
      |> select([s, gt], s.id)
      |> Repo.all()

    if Enum.empty?(gall_ids) do
      []
    else
      from(h in GallHost,
        join: host_species in SpeciesSchema,
        on: h.host_species_id == host_species.id,
        where: h.gall_species_id in ^gall_ids,
        group_by: [host_species.id, host_species.name],
        order_by: host_species.name,
        select: %{
          id: host_species.id,
          name: host_species.name,
          count: count(h.id)
        }
      )
      |> Repo.all()
    end
  end

  @doc """
  Fetches filter data for multiple galls by gall_id, for summary generation.

  Returns a map of gall_id => filter_data.
  """
  @spec get_summary_data([integer()]) :: %{integer() => map()}
  def get_summary_data([]), do: %{}

  def get_summary_data(gall_ids) when is_list(gall_ids) do
    gall_ids
    |> Enum.map(fn gall_id ->
      filters = Galls.get_gall_filter_values(gall_id)
      detachable = get_gall_detachable(gall_id)
      summary_data = Galls.Summary.from_db_filters(filters, detachable)
      {gall_id, summary_data}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Returns location IDs for all locations containing "leaf" in their name.
  Used for the "leaf (anywhere)" virtual filter option.
  """
  @spec leaf_plant_part_ids() :: [integer()]
  def leaf_plant_part_ids do
    from(pp in PlantPart,
      where: like(pp.part, "%leaf%"),
      select: pp.id
    )
    |> Repo.all()
  end

  # Private helpers

  defp get_gall_detachable(species_id) do
    from(gt in GallTraits, where: gt.species_id == ^species_id, select: gt.detachable)
    |> Repo.one()
    |> Kernel.||("unknown")
  end

  defp base_query do
    from s in SpeciesSchema,
      join: gt in GallTraits,
      on: gt.species_id == s.id,
      where: s.taxoncode == "gall",
      distinct: true
  end

  defp select_gall_fields(query) do
    from [s, gt] in query,
      order_by: s.name,
      select: %{
        id: s.id,
        name: s.name,
        gall_id: s.id,
        undescribed: gt.undescribed,
        detachable: gt.detachable
      }
  end

  # Filter pipeline functions

  defp apply_host_filter(query, nil), do: query
  defp apply_host_filter(query, []), do: query

  defp apply_host_filter(query, host_ids) do
    from [s, gt] in query,
      join: h in GallHost,
      on: h.gall_species_id == s.id,
      where: h.host_species_id in ^host_ids
  end

  defp apply_genus_filter(query, nil), do: query

  defp apply_genus_filter(query, genus_id) do
    from [s, gt] in query,
      join: h in GallHost,
      on: h.gall_species_id == s.id,
      join: host_species in SpeciesSchema,
      on: h.host_species_id == host_species.id,
      join: st in "species_taxonomy",
      on: st.species_id == host_species.id,
      where: st.taxonomy_id == ^genus_id
  end

  defp apply_family_filter(query, nil), do: query

  defp apply_family_filter(query, family_id) do
    from [s, gt] in query,
      join: st in "species_taxonomy",
      on: st.species_id == s.id,
      join: t in Taxonomy,
      on: st.taxonomy_id == t.id,
      where: t.parent_id == ^family_id
  end

  defp apply_plant_part_filter(query, nil, _logic), do: query
  defp apply_plant_part_filter(query, [], _logic), do: query

  defp apply_plant_part_filter(query, plant_part_ids, :or) do
    from [s, gt] in query,
      join: gpp in "gall_plant_part",
      on: gpp.species_id == s.id,
      where: gpp.plant_part_id in ^plant_part_ids
  end

  defp apply_plant_part_filter(query, plant_part_ids, :and) do
    required_count = length(plant_part_ids)

    matching_species =
      from(gpp in "gall_plant_part",
        where: gpp.plant_part_id in ^plant_part_ids,
        group_by: gpp.species_id,
        having: count(fragment("DISTINCT ?", gpp.plant_part_id)) == ^required_count,
        select: gpp.species_id
      )

    from [s, gt] in query,
      where: s.id in subquery(matching_species)
  end

  defp apply_color_filter(query, nil), do: query
  defp apply_color_filter(query, []), do: query

  defp apply_color_filter(query, color_ids) do
    from [s, gt] in query,
      join: gc in "gall_color",
      on: gc.species_id == s.id,
      where: gc.color_id in ^color_ids
  end

  defp apply_shape_filter(query, nil), do: query
  defp apply_shape_filter(query, []), do: query

  defp apply_shape_filter(query, shape_ids) do
    from [s, gt] in query,
      join: gsh in "gall_shape",
      on: gsh.species_id == s.id,
      where: gsh.shape_id in ^shape_ids
  end

  defp apply_texture_filter(query, nil, _logic), do: query
  defp apply_texture_filter(query, [], _logic), do: query

  defp apply_texture_filter(query, texture_ids, :or) do
    from [s, gt] in query,
      join: gtex in "gall_texture",
      on: gtex.species_id == s.id,
      where: gtex.texture_id in ^texture_ids
  end

  defp apply_texture_filter(query, texture_ids, :and) do
    required_count = length(texture_ids)

    matching_species =
      from(gtex in "gall_texture",
        where: gtex.texture_id in ^texture_ids,
        group_by: gtex.species_id,
        having: count(fragment("DISTINCT ?", gtex.texture_id)) == ^required_count,
        select: gtex.species_id
      )

    from [s, gt] in query,
      where: s.id in subquery(matching_species)
  end

  defp apply_alignment_filter(query, nil), do: query
  defp apply_alignment_filter(query, []), do: query

  defp apply_alignment_filter(query, alignment_ids) do
    from [s, gt] in query,
      join: ga in "gall_alignment",
      on: ga.species_id == s.id,
      where: ga.alignment_id in ^alignment_ids
  end

  defp apply_cells_filter(query, nil), do: query
  defp apply_cells_filter(query, []), do: query

  defp apply_cells_filter(query, cells_ids) do
    from [s, gt] in query,
      join: gce in "gall_cells",
      on: gce.species_id == s.id,
      where: gce.cells_id in ^cells_ids
  end

  defp apply_walls_filter(query, nil), do: query
  defp apply_walls_filter(query, []), do: query

  defp apply_walls_filter(query, walls_ids) do
    from [s, gt] in query,
      join: gw in "gall_walls",
      on: gw.species_id == s.id,
      where: gw.walls_id in ^walls_ids
  end

  defp apply_form_filter(query, nil), do: query
  defp apply_form_filter(query, []), do: query

  defp apply_form_filter(query, form_ids) do
    from [s, gt] in query,
      join: gf in "gall_form",
      on: gf.species_id == s.id,
      where: gf.form_id in ^form_ids
  end

  defp apply_season_filter(query, nil), do: query
  defp apply_season_filter(query, []), do: query

  defp apply_season_filter(query, season_ids) do
    from [s, gt] in query,
      join: gse in "gall_season",
      on: gse.species_id == s.id,
      where: gse.season_id in ^season_ids
  end

  defp apply_detachable_filter(query, nil), do: query
  defp apply_detachable_filter(query, "unknown"), do: query

  defp apply_detachable_filter(query, "both") do
    from [s, gt] in query,
      where: gt.detachable == "both"
  end

  defp apply_detachable_filter(query, detachable) when detachable in ~w(integral detachable) do
    from [s, gt] in query,
      where: gt.detachable == ^detachable or gt.detachable == "both"
  end

  defp apply_place_filter(query, nil, _host_ids, _genus_id), do: query
  defp apply_place_filter(query, [], _host_ids, _genus_id), do: query

  defp apply_place_filter(query, place_codes, _host_ids, _genus_id) do
    # Resolve place codes to IDs, then expand hierarchy in both directions
    place_ids =
      Enum.map(place_codes, &Ranges.get_place_id_by_code/1)
      |> Enum.reject(&is_nil/1)

    # Descendant IDs: when user selects "US", include all US states
    descendant_ids = Enum.flat_map(place_ids, &Places.descendant_ids/1) |> Enum.uniq()

    # Ancestor IDs: when user selects "US-CA", match country-level US ranges
    ancestor_ids = Enum.flat_map(place_ids, &Places.ancestor_ids/1) |> Enum.uniq()

    # Combined: a gall_range row matches if its place_id is in either set
    all_matching_place_ids = Enum.uniq(descendant_ids ++ ancestor_ids)

    from [s, gt] in query,
      join: gr in "gall_range",
      on: gr.species_id == s.id,
      where: gr.place_id in ^all_matching_place_ids
  end

  defp apply_undescribed_filter(query, nil), do: query
  defp apply_undescribed_filter(query, false), do: query

  defp apply_undescribed_filter(query, true) do
    from [s, gt] in query,
      where: gt.undescribed == true
  end

  defp apply_exclude_non_gall_filter(query, nil), do: query
  defp apply_exclude_non_gall_filter(query, false), do: query

  defp apply_exclude_non_gall_filter(query, true) do
    non_gall_species_ids =
      from(gf in "gall_form",
        join: f in Form,
        on: f.id == gf.form_id,
        where: f.form == "non-gall",
        select: gf.species_id
      )

    from [s, gt] in query,
      where: s.id not in subquery(non_gall_species_ids)
  end

  defp attach_non_gall_flag(galls) do
    gall_ids = Enum.map(galls, & &1.gall_id)

    non_gall_species_ids =
      from(gf in "gall_form",
        join: f in Form,
        on: f.id == gf.form_id,
        where: gf.species_id in ^gall_ids and f.form == "non-gall",
        select: gf.species_id
      )
      |> Repo.all()
      |> MapSet.new()

    Enum.map(galls, fn gall ->
      Map.put(gall, :non_gall, MapSet.member?(non_gall_species_ids, gall.gall_id))
    end)
  end

  defp attach_images(galls) do
    image_map =
      Galls.get_default_gall_images()
      |> Enum.into(%{}, fn %{species_id: id, path: path} -> {id, path} end)

    base_url = Image.base_url()

    Enum.map(galls, fn gall ->
      case Map.get(image_map, gall.id) do
        nil ->
          Map.put(gall, :image_url, nil)

        path ->
          small_path = String.replace(path, "original", "small")
          Map.put(gall, :image_url, "#{base_url}/#{small_path}")
      end
    end)
  end

  defp attach_place_match(galls, nil), do: galls
  defp attach_place_match(galls, []), do: galls

  defp attach_place_match(galls, place_codes) do
    # Resolve place codes to IDs for hierarchy expansion
    place_ids =
      Enum.map(place_codes, &Ranges.get_place_id_by_code/1)
      |> Enum.reject(&is_nil/1)

    # Descendant IDs: exact matches for the selected place and its subdivisions
    descendant_ids = Enum.flat_map(place_ids, &Places.descendant_ids/1) |> Enum.uniq()

    # Get all gall IDs for batch query
    gall_ids = Enum.map(galls, & &1.id)

    # Query: for each gall, check if it has exact gall_range records
    # that match the selected place or its descendants
    exact_match_gall_ids =
      from(gr in "gall_range",
        where: gr.species_id in ^gall_ids,
        where: gr.place_id in ^descendant_ids,
        where: gr.precision == "exact",
        select: gr.species_id,
        distinct: true
      )
      |> Repo.all()
      |> MapSet.new()

    # Tag each gall with its place match type
    Enum.map(galls, fn gall ->
      place_match =
        if MapSet.member?(exact_match_gall_ids, gall.id) do
          :documented
        else
          :country_level
        end

      Map.put(gall, :place_match, place_match)
    end)
  end
end
