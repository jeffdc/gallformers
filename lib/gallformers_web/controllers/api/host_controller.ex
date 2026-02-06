defmodule GallformersWeb.API.HostController do
  @moduledoc """
  API controller for host endpoints.
  """

  use GallformersWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gallformers.{GallHosts, Ranges, Search, Species}
  alias Gallformers.Images.Image
  alias Gallformers.Plants
  alias GallformersWeb.Schemas

  tags(["Hosts"])

  operation(:index,
    summary: "List hosts",
    description: "Lists all hosts with optional search and pagination",
    parameters: [
      q: [in: :query, type: :string, description: "Search query"],
      limit: [in: :query, type: :integer, description: "Maximum number of results"],
      offset: [in: :query, type: :integer, description: "Number of results to skip"],
      simple: [in: :query, type: :boolean, description: "Return simplified response"]
    ],
    responses: [
      ok: {"List of hosts", "application/json", Schemas.HostListResponse}
    ]
  )

  @doc """
  GET /api/v2/hosts
  Lists all hosts with optional search and pagination.
  Supports ?simple=true for lightweight response.
  """
  def index(conn, params) do
    limit = parse_int(params["limit"])
    offset = parse_int(params["offset"]) || 0
    query = params["q"]
    simple = params["simple"] == "true"

    {hosts, total} =
      case {query, limit} do
        {nil, nil} ->
          all = Plants.list_hosts()
          {all, length(all)}

        {nil, limit} ->
          total = Plants.count_hosts()
          paginated = Plants.list_hosts_paginated(limit, offset)
          {paginated, total}

        {query, nil} ->
          results = Search.search_hosts(query)
          {results, length(results)}

        {query, limit} ->
          total = Search.count_search_hosts(query)
          results = Search.search_hosts_paginated(query, limit, offset)
          {results, total}
      end

    response =
      if simple do
        hosts_with_places(hosts)
      else
        Enum.map(hosts, &host_to_response/1)
      end

    json(conn, %{
      data: response,
      total: total,
      limit: limit,
      offset: offset
    })
  end

  operation(:show,
    summary: "Get a host",
    description: "Gets a single host by ID with full details",
    parameters: [
      id: [in: :path, type: :integer, description: "Host ID", required: true],
      simple: [in: :query, type: :boolean, description: "Return simplified response"]
    ],
    responses: [
      ok: {"Host details", "application/json", Schemas.HostResponse},
      not_found: {"Host not found", "application/json", Schemas.Error}
    ]
  )

  @doc """
  GET /api/v2/hosts/:id
  Gets a single host by ID with full details.
  """
  def show(conn, %{"id" => id} = params) do
    simple = params["simple"] == "true"

    with {:ok, id} <- parse_id(id),
         {:ok, host} <- fetch_host(id) do
      response = build_host_response(host, simple)
      json(conn, response)
    else
      {:error, :invalid_id} -> bad_request(conn, "Invalid host ID")
      {:error, :not_found} -> not_found(conn, "Host not found")
    end
  end

  operation(:images,
    summary: "Get host images",
    description: "Returns all images for a host plant species",
    parameters: [
      id: [in: :path, type: :integer, description: "Host species ID", required: true]
    ],
    responses: [
      ok:
        {"List of images", "application/json",
         %OpenApiSpex.Schema{type: :array, items: Schemas.Image}},
      bad_request: {"Invalid ID", "application/json", Schemas.Error},
      not_found: {"Host not found", "application/json", Schemas.Error}
    ]
  )

  @doc """
  GET /api/v2/hosts/:id/images
  Returns all images for a host plant species.
  """
  def images(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, _host} <- fetch_host(id) do
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
    else
      {:error, :invalid_id} -> bad_request(conn, "Invalid host ID")
      {:error, :not_found} -> not_found(conn, "Host not found")
    end
  end

  operation(:galls,
    summary: "Get galls for a host",
    description: "Returns all galls that form on a host plant",
    parameters: [
      id: [in: :path, type: :integer, description: "Host species ID", required: true]
    ],
    responses: [
      ok:
        {"List of galls", "application/json",
         %OpenApiSpex.Schema{type: :array, items: Schemas.GallListItem}},
      bad_request: {"Invalid ID", "application/json", Schemas.Error},
      not_found: {"Host not found", "application/json", Schemas.Error}
    ]
  )

  @doc """
  GET /api/v2/hosts/:id/galls
  Returns all galls that form on a host plant.
  """
  def galls(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, _host} <- fetch_host(id) do
      galls = GallHosts.get_galls_for_host(id)

      response =
        Enum.map(galls, fn g ->
          %{
            id: g.id,
            name: g.name,
            undescribed: g.undescribed,
            datacomplete: g.datacomplete
          }
        end)

      json(conn, response)
    else
      {:error, :invalid_id} -> bad_request(conn, "Invalid host ID")
      {:error, :not_found} -> not_found(conn, "Host not found")
    end
  end

  defp parse_id(id) do
    case parse_int(id) do
      nil -> {:error, :invalid_id}
      id -> {:ok, id}
    end
  end

  defp fetch_host(id) do
    case Plants.get_host(id) do
      nil -> {:error, :not_found}
      host -> {:ok, host}
    end
  end

  defp build_host_response(host, true), do: host_to_simple_response(host)
  defp build_host_response(host, false), do: host_to_full_response(host)

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

  # Private functions

  defp host_to_response(host) do
    %{
      id: host.id,
      name: host.name,
      taxoncode: host.taxoncode,
      datacomplete: host.datacomplete
    }
  end

  defp hosts_with_places(hosts) do
    ids = Enum.map(hosts, & &1.id)
    places_map = Ranges.get_places_for_hosts(ids)

    Enum.map(hosts, fn host ->
      %{
        id: host.id,
        name: host.name,
        taxoncode: host.taxoncode,
        datacomplete: host.datacomplete,
        places: Map.get(places_map, host.id, [])
      }
    end)
  end

  defp host_to_simple_response(host) do
    places = Ranges.get_places_for_host(host.id)

    %{
      id: host.id,
      name: host.name,
      taxoncode: host.taxoncode,
      datacomplete: host.datacomplete,
      places: places
    }
  end

  defp host_to_full_response(host) do
    places = Ranges.get_places_for_host(host.id)
    galls = GallHosts.get_galls_for_host(host.id)

    %{
      id: host.id,
      name: host.name,
      taxoncode: host.taxoncode,
      datacomplete: host.datacomplete,
      places: places,
      galls:
        Enum.map(galls, fn g ->
          %{id: g.id, name: g.name, undescribed: g.undescribed}
        end)
    }
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
