defmodule GallformersWeb.API.GallController do
  @moduledoc """
  API controller for gall endpoints, read from the gall catalog
  (`Gallformers.Catalog`). Gall IDs are unchanged from the old model.
  """

  use GallformersWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gallformers.Catalog
  alias Gallformers.Images
  alias Gallformers.Images.Image
  alias GallformersWeb.Schemas

  # Each response field holding a Trait's values, with the Trait it holds.
  @trait_fields [
    colors: "color",
    shapes: "shape",
    textures: "texture",
    plant_parts: "plant_part",
    alignments: "alignment",
    walls: "walls",
    cells: "cells",
    seasons: "season",
    forms: "form"
  ]

  tags(["Galls"])

  operation(:index,
    summary: "List galls",
    description: "Lists all galls with optional search and pagination",
    parameters: [
      q: [
        in: :query,
        type: :string,
        description:
          "Search query: every word in the gall's name, one of its aliases, or a name of its inducer"
      ],
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

    %{entries: galls, total: total} =
      Catalog.paginate_galls(q: params["q"], limit: limit, offset: offset)

    json(conn, %{
      data: Enum.map(galls, &gall_to_map/1),
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
      bad_request: {"Invalid ID", "application/json", Schemas.Error},
      not_found: {"Gall not found", "application/json", Schemas.Error}
    ]
  )

  @doc """
  GET /api/v2/galls/:id
  Gets a single gall by ID with full details.
  """
  def show(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, gall} <- fetch(Catalog.gall_details(id)) do
      json(conn, gall_to_full_response(gall))
    else
      {:error, :invalid_id} -> error(conn, :bad_request, "Invalid gall ID")
      {:error, :not_found} -> error(conn, :not_found, "Gall not found")
    end
  end

  operation(:images,
    summary: "Get gall images",
    description: "Returns all images for a gall",
    parameters: [
      id: [in: :path, type: :integer, description: "Gall ID", required: true]
    ],
    responses: [
      ok:
        {"List of images", "application/json",
         %OpenApiSpex.Schema{type: :array, items: Schemas.Image}},
      bad_request: {"Invalid ID", "application/json", Schemas.Error}
    ]
  )

  @doc """
  GET /api/v2/galls/:id/images
  Returns all images for a gall.
  """
  def images(conn, %{"id" => id}) do
    case parse_id(id) do
      {:ok, id} -> json(conn, id |> Images.list_images_for_gall() |> Enum.map(&image_to_map/1))
      {:error, :invalid_id} -> error(conn, :bad_request, "Invalid gall ID")
    end
  end

  operation(:sources,
    summary: "Get gall sources",
    description:
      "Returns a gall's sources: its Gallformers note (the newest) and its citations, " <>
        "its default source first, then the note, then the rest by title",
    parameters: [
      id: [in: :path, type: :integer, description: "Gall ID", required: true]
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
  Returns a gall's Gallformers note and its citations.
  """
  def sources(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, sources} <- fetch(Catalog.list_gall_sources(id)) do
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
      {:error, :invalid_id} -> error(conn, :bad_request, "Invalid gall ID")
      {:error, :not_found} -> error(conn, :not_found, "Gall not found")
    end
  end

  # Private functions

  defp gall_to_map(gall) do
    %{
      id: gall.id,
      gall_id: gall.id,
      name: gall.name,
      datacomplete: gall.datacomplete,
      abundance_id: gall.abundance_id,
      abundance: gall.abundance,
      detachable: gall.detachable,
      undescribed: gall.undescribed,
      aliases: gall.aliases
    }
  end

  defp gall_to_full_response(gall) do
    traits =
      Map.new(@trait_fields, fn {field, trait} ->
        values = Map.get(gall.traits, trait, [])
        {field, Enum.map(values, &%{id: &1.id, field: &1.value, description: &1.definition})}
      end)

    gall
    |> gall_to_map()
    |> Map.merge(traits)
    |> Map.merge(%{hosts: gall.hosts, places: range_codes(gall.id)})
  end

  # The place codes of the Gall's potential range; none when its range is
  # everywhere (no Host range data: missing data is not absence).
  defp range_codes(gall_id) do
    case Catalog.potential_range(gall_id) do
      :everywhere -> []
      places -> Enum.map(places, & &1.code)
    end
  end

  defp image_to_map(img) do
    %{
      id: img.id,
      path: img.path,
      url: "#{Image.base_url()}/#{img.path}",
      default: Image.default?(img),
      creator: img.creator,
      attribution: img.attribution,
      sourcelink: img.sourcelink,
      license: img.license,
      licenselink: img.licenselink,
      caption: img.caption
    }
  end

  defp fetch({:ok, value}), do: {:ok, value}
  defp fetch(:not_found), do: {:error, :not_found}

  defp error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{error: message})
  end

  defp parse_id(id) do
    case parse_int(id) do
      nil -> {:error, :invalid_id}
      id -> {:ok, id}
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
