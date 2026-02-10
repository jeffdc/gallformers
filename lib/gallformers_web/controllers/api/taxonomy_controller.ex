defmodule GallformersWeb.API.TaxonomyController do
  @moduledoc """
  API controller for taxonomy endpoints.
  """

  use GallformersWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gallformers.Species
  alias Gallformers.Taxonomy
  alias GallformersWeb.Schemas

  tags(["Taxonomy"])

  operation(:genera,
    summary: "List genera",
    description: "Lists all genera with optional search and pagination",
    parameters: [
      q: [in: :query, type: :string, description: "Search query (prefix match)"],
      limit: [in: :query, type: :integer, description: "Maximum number of results"],
      offset: [in: :query, type: :integer, description: "Number of results to skip"]
    ],
    responses: [
      ok: {"List of genera", "application/json", Schemas.GeneraListResponse}
    ]
  )

  @doc """
  GET /api/v2/genera
  Lists all genera with optional search and pagination.
  """
  def genera(conn, params) do
    limit = parse_int(params["limit"])
    offset = parse_int(params["offset"]) || 0
    query = params["q"]

    empty_unknown_ids = MapSet.new(Taxonomy.empty_unknown_genus_ids())

    all_genera = fetch_genera(query, limit, empty_unknown_ids)
    total = length(all_genera)
    paginated = paginate(all_genera, offset, limit)

    json(conn, %{
      data: Enum.map(paginated, &taxonomy_to_map/1),
      total: total,
      limit: limit,
      offset: offset
    })
  end

  operation(:families,
    summary: "List families",
    description: "Lists all families with their genera",
    responses: [
      ok:
        {"List of families", "application/json",
         %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :object}}}
    ]
  )

  @doc """
  GET /api/v2/families
  Lists all families with their genera.
  """
  def families(conn, _params) do
    families = get_families_with_genera()
    json(conn, families)
  end

  operation(:family,
    summary: "Get a family",
    description: "Gets a family by ID with its genera",
    parameters: [
      id: [in: :path, type: :integer, description: "Family ID", required: true]
    ],
    responses: [
      ok: {"Family details", "application/json", %OpenApiSpex.Schema{type: :object}},
      not_found: {"Family not found", "application/json", Schemas.Error}
    ]
  )

  @doc """
  GET /api/v2/families/:id
  Gets a family by ID with its genera.
  """
  def family(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, family} <- fetch_taxonomy_by_type(id, "family") do
      empty_unknown_ids = MapSet.new(Taxonomy.empty_unknown_genus_ids())

      genera =
        Taxonomy.get_children(id)
        |> Enum.reject(fn g -> MapSet.member?(empty_unknown_ids, g.id) end)

      json(conn, %{
        id: family.id,
        name: family.name,
        type: family.type,
        description: family.description,
        genera: Enum.map(genera, &taxonomy_to_map/1)
      })
    else
      {:error, :invalid_id} -> bad_request(conn, "Invalid family ID")
      {:error, :not_found} -> not_found(conn, "Family not found")
    end
  end

  operation(:genus,
    summary: "Get a genus",
    description: "Gets a genus by ID with its parent family and species",
    parameters: [
      id: [in: :path, type: :integer, description: "Genus ID", required: true]
    ],
    responses: [
      ok: {"Genus details", "application/json", %OpenApiSpex.Schema{type: :object}},
      not_found: {"Genus not found", "application/json", Schemas.Error}
    ]
  )

  @doc """
  GET /api/v2/genera/:id
  Gets a genus by ID with its parent family and species.
  """
  def genus(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, genus} <- fetch_taxonomy_by_type(id, "genus") do
      parent = Taxonomy.get_parent(id)
      species_ids = Taxonomy.get_species_ids_for_genus(id)
      species = get_species_by_ids(species_ids)

      json(conn, %{
        id: genus.id,
        name: genus.name,
        type: genus.type,
        description: genus.description,
        family: parent_to_map(parent),
        species: species
      })
    else
      {:error, :invalid_id} -> bad_request(conn, "Invalid genus ID")
      {:error, :not_found} -> not_found(conn, "Genus not found")
    end
  end

  operation(:section,
    summary: "Get a section",
    description: "Gets a section by ID with its species",
    parameters: [
      id: [in: :path, type: :integer, description: "Section ID", required: true]
    ],
    responses: [
      ok: {"Section details", "application/json", %OpenApiSpex.Schema{type: :object}},
      not_found: {"Section not found", "application/json", Schemas.Error}
    ]
  )

  @doc """
  GET /api/v2/sections/:id
  Gets a section by ID with its species.
  """
  def section(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, section} <- fetch_taxonomy_by_type(id, "section") do
      species_ids = Taxonomy.get_species_ids_for_genus(id)
      species = get_species_by_ids(species_ids)

      json(conn, %{
        id: section.id,
        name: section.name,
        type: section.type,
        description: section.description,
        species: species
      })
    else
      {:error, :invalid_id} -> bad_request(conn, "Invalid section ID")
      {:error, :not_found} -> not_found(conn, "Section not found")
    end
  end

  # Private functions

  defp fetch_genera(nil, _limit, empty_unknown_ids) do
    Taxonomy.list_taxonomies_by_type("genus")
    |> Enum.reject(fn g -> MapSet.member?(empty_unknown_ids, g.id) end)
  end

  defp fetch_genera(query, limit, empty_unknown_ids) do
    Taxonomy.search_genera_and_sections(query, limit || 100)
    |> Enum.filter(fn g -> g.type == "genus" end)
    |> Enum.reject(fn g -> MapSet.member?(empty_unknown_ids, g.id) end)
  end

  defp paginate(list, offset, nil), do: Enum.drop(list, offset)
  defp paginate(list, offset, limit), do: list |> Enum.drop(offset) |> Enum.take(limit)

  defp parse_id(id) do
    case parse_int(id) do
      nil -> {:error, :invalid_id}
      id -> {:ok, id}
    end
  end

  defp fetch_taxonomy_by_type(id, expected_type) do
    case Taxonomy.get_taxonomy(id) do
      nil -> {:error, :not_found}
      %{type: ^expected_type} = taxonomy -> {:ok, taxonomy}
      _other -> {:error, :not_found}
    end
  end

  defp bad_request(conn, message) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: message})
  end

  defp not_found(conn, message) do
    conn
    |> put_status(:not_found)
    |> json(%{error: message})
  end

  defp taxonomy_to_map(taxonomy) do
    %{
      id: taxonomy.id,
      name: taxonomy.name,
      type: taxonomy.type,
      description: taxonomy.description,
      parent_id: taxonomy.parent_id
    }
  end

  defp parent_to_map(nil), do: nil
  defp parent_to_map(parent), do: %{id: parent.id, name: parent.name}

  defp get_families_with_genera do
    families = Taxonomy.list_taxonomies_by_type("family")
    empty_unknown_ids = MapSet.new(Taxonomy.empty_unknown_genus_ids())
    family_ids = Enum.map(families, & &1.id)
    children_map = Taxonomy.get_children_for_parents(family_ids)

    Enum.map(families, fn family ->
      genera =
        Map.get(children_map, family.id, [])
        |> Enum.reject(fn g -> MapSet.member?(empty_unknown_ids, g.id) end)

      %{
        id: family.id,
        name: family.name,
        type: family.type,
        description: family.description,
        genera: Enum.map(genera, &taxonomy_to_map/1)
      }
    end)
  end

  defp get_species_by_ids([]), do: []
  defp get_species_by_ids(ids), do: Species.list_species_by_ids(ids)

  defp parse_int(nil), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(int) when is_integer(int), do: int
end
