defmodule GallformersWeb.API.PlaceController do
  @moduledoc """
  API controller for place endpoints.
  """

  use GallformersWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import Ecto.Query

  alias Gallformers.Places
  alias Gallformers.Places.Place
  alias Gallformers.Repo
  alias Gallformers.Species.Species
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
    places = list_all_places()
    json(conn, places)
  end

  operation(:show,
    summary: "Get a place",
    description: "Gets a single place by ID with its parent and associated hosts",
    parameters: [
      id: [in: :path, type: :integer, description: "Place ID", required: true]
    ],
    responses: [
      ok: {"Place details", "application/json", Schemas.Place},
      not_found: {"Place not found", "application/json", Schemas.Error}
    ]
  )

  @doc """
  GET /api/v2/places/:id
  Gets a single place by ID with its parent and associated hosts.
  """
  def show(conn, %{"id" => id}) do
    case parse_int(id) do
      nil ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid place ID"})

      id ->
        case Places.get_place(id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Place not found"})

          place ->
            parent = get_parent_place(place.parent_id)
            hosts = get_hosts_for_place(id)

            json(conn, %{
              id: place.id,
              name: place.name,
              code: place.code,
              type: place.type,
              parent:
                if parent do
                  %{id: parent.id, name: parent.name, code: parent.code}
                else
                  nil
                end,
              hosts:
                Enum.map(hosts, fn h ->
                  %{id: h.id, name: h.name}
                end)
            })
        end
    end
  end

  # Private functions

  defp list_all_places do
    from(p in Place,
      order_by: [p.type, p.name],
      select: %{
        id: p.id,
        name: p.name,
        code: p.code,
        type: p.type,
        parent_id: p.parent_id
      }
    )
    |> Repo.all()
  end

  defp get_parent_place(nil), do: nil

  defp get_parent_place(parent_id) do
    Places.get_place(parent_id)
  end

  defp get_hosts_for_place(place_id) do
    from(s in Species,
      join: hr in "host_range",
      on: hr.species_id == s.id,
      where: hr.place_id == ^place_id and s.taxoncode == "plant",
      order_by: s.name,
      select: %{
        id: s.id,
        name: s.name
      }
    )
    |> Repo.all()
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
