defmodule GallformersWeb.API.GallController do
  @moduledoc """
  API controller for gall endpoints.
  """

  use GallformersWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gallformers.{GallHosts, Galls, Ranges, Search, Sources, Species}
  alias Gallformers.Images.Image
  alias GallformersWeb.Schemas

  tags(["Galls"])

  operation(:index,
    summary: "List galls",
    description: "Lists all galls with optional search and pagination",
    parameters: [
      q: [in: :query, type: :string, description: "Search query"],
      limit: [in: :query, type: :integer, description: "Maximum number of results"],
      offset: [in: :query, type: :integer, description: "Number of results to skip"]
    ],
    responses: [
      ok: {"List of galls", "application/json", Schemas.GallListResponse}
    ]
  )

  @doc """
  GET /api/v2/galls
  Lists all galls with optional search and pagination.
  """
  def index(conn, params) do
    limit = parse_int(params["limit"])
    offset = parse_int(params["offset"]) || 0
    query = params["q"]

    {galls, total} =
      case {query, limit} do
        {nil, nil} ->
          all = Galls.list_galls()
          {galls_with_aliases(all), length(all)}

        {nil, limit} ->
          total = Galls.count_galls()
          paginated = Galls.list_galls_paginated(limit, offset)
          {galls_with_aliases(paginated), total}

        {query, nil} ->
          results = Search.search_galls(query)
          {galls_with_aliases(results), length(results)}

        {query, limit} ->
          total = Search.count_search_galls(query)
          results = Search.search_galls_paginated(query, limit, offset)
          {galls_with_aliases(results), total}
      end

    json(conn, %{
      data: galls,
      total: total,
      limit: limit,
      offset: offset
    })
  end

  operation(:show,
    summary: "Get a gall",
    description: "Gets a single gall by ID with full details",
    parameters: [
      id: [in: :path, type: :integer, description: "Gall ID", required: true]
    ],
    responses: [
      ok: {"Gall details", "application/json", Schemas.Gall},
      not_found: {"Gall not found", "application/json", Schemas.Error}
    ]
  )

  @doc """
  GET /api/v2/galls/:id
  Gets a single gall by ID with full details.
  """
  def show(conn, %{"id" => id}) do
    case parse_int(id) do
      nil ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid gall ID"})

      id ->
        case Galls.get_gall(id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Gall not found"})

          gall ->
            json(conn, gall_to_full_response(gall))
        end
    end
  end

  operation(:images,
    summary: "Get gall images",
    description: "Returns all images for a gall species",
    parameters: [
      id: [in: :path, type: :integer, description: "Gall species ID", required: true]
    ],
    responses: [
      ok:
        {"List of images", "application/json",
         %OpenApiSpex.Schema{type: :array, items: Schemas.Image}}
    ]
  )

  @doc """
  GET /api/v2/galls/:id/images
  Returns all images for a gall species.
  """
  def images(conn, %{"id" => id}) do
    case parse_int(id) do
      nil ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid species ID"})

      id ->
        images = Species.get_images_for_species(id)
        base_url = Image.base_url()

        response =
          Enum.map(images, fn img ->
            %{
              id: img.id,
              path: img.path,
              url: "#{base_url}/#{img.path}",
              default: Image.default?(img),
              creator: img.creator,
              attribution: img.attribution,
              sourcelink: img.sourcelink,
              license: img.license,
              licenselink: img.licenselink,
              caption: img.caption
            }
          end)

        json(conn, response)
    end
  end

  operation(:sources,
    summary: "Get gall sources",
    description: "Returns all scientific sources/references for a gall species",
    parameters: [
      id: [in: :path, type: :integer, description: "Gall species ID", required: true]
    ],
    responses: [
      ok:
        {"List of sources", "application/json",
         %OpenApiSpex.Schema{type: :array, items: Schemas.SourceDetail}},
      bad_request: {"Invalid ID", "application/json", Schemas.Error},
      not_found: {"Gall not found", "application/json", Schemas.Error}
    ]
  )

  @doc """
  GET /api/v2/galls/:id/sources
  Returns all scientific sources for a gall species.
  """
  def sources(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, _gall} <- fetch_gall(id) do
      sources = Sources.get_sources_for_species(id)

      response =
        Enum.map(sources, fn s ->
          %{
            id: s.id,
            title: s.title,
            author: s.author,
            pubyear: s.pubyear,
            link: s.link,
            citation: s.citation,
            description: s.description,
            externallink: s.externallink
          }
        end)

      json(conn, response)
    else
      {:error, :invalid_id} ->
        conn |> put_status(:bad_request) |> json(%{error: "Invalid gall ID"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Gall not found"})
    end
  end

  # Private functions

  defp galls_with_aliases(galls) do
    ids = Enum.map(galls, & &1.id)
    alias_map = Species.get_aliases_for_species_batch(ids)

    Enum.map(galls, fn gall ->
      aliases = Map.get(alias_map, gall.id, [])

      %{
        id: gall.id,
        name: gall.name,
        datacomplete: gall.datacomplete,
        abundance_id: gall.abundance_id,
        abundance: gall.abundance_name,
        detachable: gall.detachable,
        undescribed: gall.undescribed,
        aliases: Enum.map(aliases, &alias_to_map/1)
      }
    end)
  end

  defp gall_to_full_response(gall) do
    aliases = Species.get_aliases_for_species(gall.id)
    hosts = GallHosts.get_hosts_for_gall(gall.id)
    filter_fields = Galls.get_gall_filter_values(gall.id)
    places = Ranges.get_places_for_gall(gall.id)
    excluded_places = Ranges.get_excluded_places_for_gall(gall.id)

    %{
      id: gall.id,
      name: gall.name,
      datacomplete: gall.datacomplete,
      abundance_id: gall.abundance_id,
      abundance: gall.abundance_name,
      detachable: gall.detachable,
      undescribed: gall.undescribed,
      aliases: Enum.map(aliases, &alias_to_map/1),
      hosts: Enum.map(hosts, fn h -> %{id: h.host_species_id, name: h.host_name} end),
      colors: filter_fields.colors,
      shapes: filter_fields.shapes,
      textures: filter_fields.textures,
      plant_parts: filter_fields.plant_parts,
      alignments: filter_fields.alignments,
      walls: filter_fields.walls,
      cells: filter_fields.cells,
      seasons: filter_fields.seasons,
      forms: filter_fields.forms,
      places: places,
      excludedPlaces: excluded_places
    }
  end

  defp alias_to_map(a) do
    %{
      id: a.id,
      name: a.name,
      type: a.type,
      description: a.description
    }
  end

  defp parse_id(id) do
    case parse_int(id) do
      nil -> {:error, :invalid_id}
      id -> {:ok, id}
    end
  end

  defp fetch_gall(id) do
    case Galls.get_gall(id) do
      nil -> {:error, :not_found}
      gall -> {:ok, gall}
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(int) when is_integer(int), do: int
end
