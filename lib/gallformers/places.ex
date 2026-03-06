defmodule Gallformers.Places do
  @moduledoc """
  The Places context.

  Provides functions for working with geographic places (states, provinces, regions).
  """

  import Ecto.Query
  alias Gallformers.Places.Place
  alias Gallformers.Repo
  alias Gallformers.Species.Species

  # Bounding boxes per place code, extracted from PMTiles by extract_bounds.py.
  # Format: %{"US-CA" => [west, south, east, north], ...}
  # Antimeridian-crossing features have west > east (e.g., NZ: [165.88, ..., -171.18, ...]).
  @place_bounds Path.join(:code.priv_dir(:gallformers), "repo/data/place_bounds.json")
                |> File.read!()
                |> Jason.decode!()

  @doc """
  Returns the bounding box for a set of place codes as `[[west, south], [east, north]]`,
  or nil if no bounds data is available for any of the codes.

  Computes the union of individual code bounding boxes. Handles antimeridian-crossing
  features where west > east.
  """
  @spec get_bounds_for_codes([String.t()]) :: [[float()]] | nil
  def get_bounds_for_codes(codes) when is_list(codes) do
    bboxes =
      codes
      |> Enum.map(&Map.get(@place_bounds, &1))
      |> Enum.reject(&is_nil/1)

    case bboxes do
      [] -> nil
      bboxes -> union_bboxes(bboxes)
    end
  end

  # Compute the union of bounding boxes, handling the antimeridian.
  #
  # Individual bboxes may cross the antimeridian (west > east from extract_bounds.py).
  # The union may also need to cross the antimeridian even if no individual bbox does
  # (e.g., NZ mainland at 165-178°E plus Chatham Islands at 176°W).
  #
  # Strategy: try both a normal union and an antimeridian-crossing union,
  # pick whichever produces the smaller longitude span.
  defp union_bboxes(bboxes) do
    south = bboxes |> Enum.map(&Enum.at(&1, 1)) |> Enum.min()
    north = bboxes |> Enum.map(&Enum.at(&1, 3)) |> Enum.max()

    # Collect all longitude edges, normalizing antimeridian-crossing bboxes
    # into pairs of [west, east] where east may be > 180
    lon_ranges =
      Enum.map(bboxes, fn [w, _s, e, _n] ->
        if w > e, do: {w, e + 360}, else: {w, e}
      end)

    # Normal union: simple min/max
    normal_west = lon_ranges |> Enum.map(&elem(&1, 0)) |> Enum.min()
    normal_east = lon_ranges |> Enum.map(&elem(&1, 1)) |> Enum.max()
    normal_span = normal_east - normal_west

    # Antimeridian-crossing union: shift everything to [0, 360] space
    shifted_ranges =
      Enum.map(lon_ranges, fn {w, e} ->
        w360 = if w < 0, do: w + 360, else: w
        e360 = if e < 0, do: e + 360, else: e
        {w360, e360}
      end)

    shifted_west = shifted_ranges |> Enum.map(&elem(&1, 0)) |> Enum.min()
    shifted_east = shifted_ranges |> Enum.map(&elem(&1, 1)) |> Enum.max()
    shifted_span = shifted_east - shifted_west

    # Pick the union with the smaller span
    {west, east} =
      if shifted_span < normal_span do
        # The antimeridian-crossing union is tighter — use it.
        # MapLibre handles coordinates > 180, so pass as-is.
        {shifted_west, shifted_east}
      else
        {normal_west, normal_east}
      end

    [[west, south], [east, north]]
  end

  @doc """
  Returns all continent-type places, ordered by name.
  """
  @spec list_continents() :: [Place.t()]
  def list_continents do
    from(p in Place,
      where: p.type == "continent",
      order_by: p.name
    )
    |> Repo.all()
  end

  @doc """
  Returns all selectable places ordered by name.

  Includes states/provinces and leaf countries (countries with no subdivisions,
  e.g., territories like Puerto Rico, Bahamas, Bermuda).
  """
  @spec list_places() :: [Place.t()]
  def list_places do
    has_children = from(ph in "place_hierarchy", select: ph.parent_id)

    from(p in Place,
      where:
        p.type in ["state", "province"] or
          (p.type == "country" and p.id not in subquery(has_children)),
      order_by: p.name
    )
    |> Repo.all()
  end

  @doc """
  Gets a place by code.
  """
  @spec get_place_by_code(String.t()) :: Place.t() | nil
  def get_place_by_code(code) do
    from(p in Place,
      where: p.code == ^code
    )
    |> Repo.one()
  end

  @doc """
  Gets a place by code, raising if not found.
  """
  @spec get_place_by_code!(String.t()) :: Place.t()
  def get_place_by_code!(code) do
    from(p in Place, where: p.code == ^code)
    |> Repo.one!()
  end

  @doc """
  Gets a place by name (case-insensitive). Used for V1 URL compatibility.
  """
  @spec get_place_by_name(String.t()) :: Place.t() | nil
  def get_place_by_name(name) do
    from(p in Place,
      where: fragment("lower(?) = lower(?)", p.name, ^name),
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets a place by ID.
  """
  @spec get_place(integer()) :: Place.t() | nil
  def get_place(id) do
    Repo.get(Place, id)
  end

  @doc """
  Gets a place by ID, raising if not found.
  """
  @spec get_place!(integer()) :: Place.t()
  def get_place!(id) do
    Repo.get!(Place, id)
  end

  @doc """
  Gets a place's parent by ID.
  """
  def get_parent_place(place_id) do
    from(p in "place",
      join: pp in "place_hierarchy",
      on: pp.parent_id == p.id,
      where: pp.place_id == ^place_id,
      select: %{
        id: p.id,
        name: p.name,
        code: p.code,
        type: p.type
      },
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Searches places by name (case-insensitive).
  """
  @spec search_places(String.t(), integer()) :: [Place.t()]
  def search_places(query, limit \\ 20) do
    search_pattern = "%#{String.downcase(query)}%"

    from(p in Place,
      where: fragment("lower(?) LIKE ?", p.name, ^search_pattern),
      order_by: p.name,
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Searches places for the grouped typeahead. Returns countries and subdivisions
  (not continents or regions) with group labels and parent names for display.

  Results are ordered: countries first, then subdivisions, alphabetical within each.

  When `continent_code` is provided, limits results to descendants of that continent.
  """
  @spec search_places_grouped(String.t(), non_neg_integer(), String.t() | nil) :: [map()]
  def search_places_grouped(query, limit \\ 10, continent_code \\ nil) do
    like_query = "%#{String.downcase(query)}%"

    base_query =
      from(p in Place,
        left_join: ph in "place_hierarchy",
        on: ph.place_id == p.id,
        left_join: parent in Place,
        on: parent.id == ph.parent_id,
        where: p.type in ["country", "state", "province"],
        where: fragment("lower(?) LIKE ?", p.name, ^like_query),
        order_by: [
          fragment("CASE WHEN ? = 'country' THEN 0 ELSE 1 END", p.type),
          p.name
        ],
        limit: ^limit,
        select: %{
          id: p.id,
          name: p.name,
          code: p.code,
          type: p.type,
          parent_name: parent.name,
          group:
            fragment(
              "CASE WHEN ? = 'country' THEN 'Countries' ELSE 'States & Provinces' END",
              p.type
            )
        }
      )

    base_query
    |> maybe_scope_to_continent(continent_code)
    |> Repo.all()
  end

  defp maybe_scope_to_continent(query, nil), do: query

  defp maybe_scope_to_continent(query, continent_code) do
    case get_place_by_code(continent_code) do
      nil -> query
      continent -> where(query, [p], p.id in ^descendant_ids(continent.id))
    end
  end

  @doc """
  Returns all places ordered by type then name.
  """
  @spec list_all_places() :: [Place.t()]
  def list_all_places do
    from(p in Place,
      order_by: [p.type, p.name]
    )
    |> Repo.all()
  end

  # Hierarchy traversal using WITH RECURSIVE CTEs

  @doc """
  Returns IDs for a place and all its descendants (recursive).
  """
  @spec descendant_ids(integer()) :: [integer()]
  def descendant_ids(place_id) do
    {:ok, %{rows: rows}} =
      Repo.query(
        """
        WITH RECURSIVE descendants(id) AS (
          SELECT ?1
          UNION ALL
          SELECT ph.place_id
          FROM place_hierarchy ph
          JOIN descendants d ON ph.parent_id = d.id
        )
        SELECT id FROM descendants
        """,
        [place_id]
      )

    Enum.map(rows, fn [id] -> id end)
  end

  @doc """
  Returns IDs for a place and all its ancestors (recursive).
  """
  @spec ancestor_ids(integer()) :: [integer()]
  def ancestor_ids(place_id) do
    {:ok, %{rows: rows}} =
      Repo.query(
        """
        WITH RECURSIVE ancestors(id) AS (
          SELECT ?1
          UNION ALL
          SELECT ph.parent_id
          FROM place_hierarchy ph
          JOIN ancestors a ON ph.place_id = a.id
        )
        SELECT id FROM ancestors
        """,
        [place_id]
      )

    Enum.map(rows, fn [id] -> id end)
  end

  @doc """
  Returns IDs for leaf descendants only (places with no children).
  For a leaf place, returns just itself.
  """
  @spec leaf_descendant_ids(integer()) :: [integer()]
  def leaf_descendant_ids(place_id) do
    all_ids = descendant_ids(place_id)

    if length(all_ids) == 1 do
      all_ids
    else
      parent_ids =
        from(ph in "place_hierarchy",
          where: ph.parent_id in ^all_ids,
          select: ph.parent_id,
          distinct: true
        )
        |> Repo.all()

      Enum.reject(all_ids, &(&1 in parent_ids))
    end
  end

  @doc """
  Returns the ancestor places for a given place, ordered from root to immediate parent.
  Does not include the place itself.
  """
  @spec get_ancestors(integer()) :: [Place.t()]
  def get_ancestors(place_id) do
    {:ok, %{rows: rows}} =
      Repo.query(
        """
        WITH RECURSIVE ancestors(id, depth) AS (
          SELECT ph.parent_id, 1
          FROM place_hierarchy ph
          WHERE ph.place_id = ?1
          UNION ALL
          SELECT ph.parent_id, a.depth + 1
          FROM place_hierarchy ph
          JOIN ancestors a ON ph.place_id = a.id
        )
        SELECT p.id, p.name, p.code, p.type
        FROM ancestors a
        JOIN place p ON p.id = a.id
        ORDER BY a.depth DESC
        """,
        [place_id]
      )

    Enum.map(rows, fn [id, name, code, type] ->
      %Place{id: id, name: name, code: code, type: type}
    end)
  end

  @doc """
  Returns the direct children of a place, ordered by name.
  """
  @spec get_children(integer()) :: [Place.t()]
  def get_children(place_id) do
    from(p in Place,
      join: ph in "place_hierarchy",
      on: ph.place_id == p.id,
      where: ph.parent_id == ^place_id,
      order_by: p.name
    )
    |> Repo.all()
  end

  @doc """
  Returns codes for a place and all its descendants (recursive).
  Used for map highlighting.
  """
  @spec get_descendant_codes(integer()) :: [String.t()]
  def get_descendant_codes(place_id) do
    ids = descendant_ids(place_id)

    from(p in Place,
      where: p.id in ^ids,
      select: p.code
    )
    |> Repo.all()
  end

  @doc """
  Returns the full place hierarchy as a nested tree for the tree browser.

  The tree has multiple continent roots (no single root node). Each node follows
  the `TreeComponents.tree_browser` contract:
  - Branch nodes have a `:nodes` key with child nodes
  - Leaf nodes have no `:nodes` key
  - All nodes have `:key`, `:label`, `:name`, `:url`
  """
  @spec get_places_tree() :: [map()]
  def get_places_tree do
    places = Repo.all(from(p in Place, order_by: p.name))

    links =
      from(ph in "place_hierarchy", select: {ph.place_id, ph.parent_id})
      |> Repo.all()

    place_map = Map.new(places, &{&1.id, &1})

    children_map =
      Enum.group_by(links, fn {_child, parent} -> parent end, fn {child, _parent} -> child end)

    all_child_ids = MapSet.new(links, fn {child, _parent} -> child end)
    roots = Enum.reject(places, &MapSet.member?(all_child_ids, &1.id))

    Enum.map(roots, &build_tree_node(&1, place_map, children_map))
  end

  defp build_tree_node(place, place_map, children_map) do
    child_ids = Map.get(children_map, place.id, [])

    base = %{
      key: "p-#{place.code}",
      label: place.name,
      name: place.name,
      rank: nil,
      url: "/place/#{place.code}"
    }

    if child_ids == [] do
      base
    else
      children =
        child_ids
        |> Enum.map(&Map.get(place_map, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.name)
        |> Enum.map(&build_tree_node(&1, place_map, children_map))

      Map.put(base, :nodes, children)
    end
  end

  # Range management - semantic wrappers for V2 schema

  @doc """
  Gets host ranges for a species (places where the host plant exists).
  """
  @spec get_host_ranges(integer()) :: [Place.t()]
  def get_host_ranges(species_id) do
    from(p in Place,
      join: hr in "host_range",
      on: hr.place_id == p.id,
      where: hr.species_id == ^species_id,
      order_by: p.name
    )
    |> Repo.all()
  end

  @doc """
  Gets the curated gall range for a species (places where the gall occurs).
  """
  @spec get_gall_ranges(integer()) :: [Place.t()]
  def get_gall_ranges(species_id) do
    from(p in Place,
      join: gr in "gall_range",
      on: gr.place_id == p.id,
      where: gr.species_id == ^species_id,
      order_by: p.name
    )
    |> Repo.all()
  end

  @doc """
  Gets the range for a species based on its taxoncode.
  For plants: returns places where the host exists
  For galls: returns places in the gall's curated range
  """
  @spec get_species_range(Species.t()) :: [Place.t()]
  def get_species_range(%Species{taxoncode: "plant", id: id}) do
    get_host_ranges(id)
  end

  def get_species_range(%Species{taxoncode: "gall", id: id}) do
    get_gall_ranges(id)
  end

  def get_species_range(_), do: []
end
