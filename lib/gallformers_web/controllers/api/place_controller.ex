defmodule GallformersWeb.API.PlaceController do
  @moduledoc """
  API controller for place endpoints.
  """

  use GallformersWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gallformers.Places
  alias GallformersWeb.Schemas

  tags(["Places"])

  operation(:index,
    summary: "List places",
    description: "Lists all places hierarchically",
    responses: [
      ok:
        {"List of places", "application/json",
         %OpenApiSpex.Schema{type: :array, items: Schemas.Place}}
    ]
  )

  @doc """
  GET /api/v2/places
  Lists all places hierarchically.
  """
  def index(conn, _params) do
    places =
      Places.list_all_places()
      |> Enum.map(fn p ->
        %{id: p.id, name: p.name, code: p.code, type: p.type, parent_id: p.parent_id}
      end)

    json(conn, places)
  end
end
