defmodule GallformersWeb.API.SourceController do
  @moduledoc """
  API controller for source endpoints.
  """

  use GallformersWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gallformers.{Catalog, Sources}
  alias GallformersWeb.Schemas

  tags(["Sources"])

  operation(:index,
    summary: "List sources",
    description: "Lists all sources with optional search and pagination",
    parameters: [
      q: [in: :query, type: :string, description: "Search query"],
      limit: [in: :query, type: :integer, description: "Maximum number of results"],
      offset: [in: :query, type: :integer, description: "Number of results to skip"]
    ],
    responses: [
      ok:
        {"List of sources", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{
             data: %OpenApiSpex.Schema{type: :array, items: Schemas.Source},
             total: %OpenApiSpex.Schema{type: :integer},
             limit: %OpenApiSpex.Schema{type: :integer, nullable: true},
             offset: %OpenApiSpex.Schema{type: :integer}
           }
         }}
    ]
  )

  @doc """
  GET /api/v2/sources
  Lists all sources with optional search and pagination.
  """
  def index(conn, params) do
    limit = parse_int(params["limit"])
    offset = parse_int(params["offset"]) || 0
    query = params["q"]

    {sources, total} =
      case {query, limit} do
        {nil, nil} ->
          all = Sources.list_sources()
          {all, length(all)}

        {nil, limit} ->
          total = Sources.count_sources()
          paginated = Sources.list_sources_paginated(limit, offset)
          {paginated, total}

        {query, nil} ->
          results = Sources.search_sources(query)
          {results, length(results)}

        {query, limit} ->
          all = Sources.search_sources(query)
          paginated = all |> Enum.drop(offset) |> Enum.take(limit)
          {paginated, length(all)}
      end

    json(conn, %{
      data: Enum.map(sources, &source_to_map/1),
      total: total,
      limit: limit,
      offset: offset
    })
  end

  operation(:show,
    summary: "Get a source",
    description:
      "Gets a single source by ID with the galls it speaks of (`species`): those it cites, " <>
        "has a Gallformers note on, or is the source of a fact about. Each gall's " <>
        "`description` is the citation's text or the note's, when there is one.",
    parameters: [
      id: [in: :path, type: :integer, description: "Source ID", required: true]
    ],
    responses: [
      ok: {"Source details", "application/json", Schemas.Source},
      not_found: {"Source not found", "application/json", Schemas.Error}
    ]
  )

  @doc """
  GET /api/v2/sources/:id
  Gets a single source by ID with its species.
  """
  def show(conn, %{"id" => id}) do
    case parse_int(id) do
      nil ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid source ID"})

      id ->
        case Sources.get_source(id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Source not found"})

          source ->
            galls = id |> Catalog.list_galls_for_source() |> Catalog.add_citations(id)

            json(conn, %{
              id: source.id,
              title: source.title,
              author: source.author,
              pubyear: source.pubyear,
              link: source.link,
              citation: source.citation,
              datacomplete: source.datacomplete,
              species:
                Enum.map(galls, fn g ->
                  %{
                    id: g.id,
                    name: g.name,
                    taxoncode: "gall",
                    description: g.description,
                    externallink: g.externallink
                  }
                end)
            })
        end
    end
  end

  # Private functions

  defp source_to_map(source) do
    %{
      id: source.id,
      title: source.title,
      author: source.author,
      pubyear: source.pubyear,
      link: source.link,
      citation: source.citation,
      datacomplete: source.datacomplete
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
