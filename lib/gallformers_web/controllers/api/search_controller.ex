defmodule GallformersWeb.API.SearchController do
  @moduledoc """
  API controller for global search endpoint.
  """

  use GallformersWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gallformers.Search
  alias GallformersWeb.Schemas

  tags(["Search"])

  operation(:search,
    summary: "Global search",
    description:
      "Performs a global search across all entity types. Galls are found by name, " <>
        "alias or their inducer's names (including synonyms); hosts and taxonomy " <>
        "entries by accepted name, synonym or common name. Host IDs are unchanged; " <>
        "taxonomy IDs are the new taxon IDs.",
    parameters: [
      q: [in: :query, type: :string, description: "Search query", required: true]
    ],
    responses: [
      ok: {"Search results", "application/json", Schemas.SearchResults}
    ]
  )

  @doc """
  GET /api/v2/search?q=query
  Performs a global search across all entity types.
  """
  def search(conn, %{"q" => query}) when is_binary(query) and query != "" do
    json(conn, query |> Search.global_search() |> api_categories())
  end

  def search(conn, _params) do
    json(conn, api_categories(Search.empty_results()))
  end

  # The API keeps its documented categories: the species pages' results
  # (`species`) are the site's, not v2's.
  defp api_categories(results), do: Map.delete(results, :species)
end
