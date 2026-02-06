defmodule GallformersWeb.API.StatsController do
  @moduledoc """
  API controller for stats endpoint.

  Returns summary statistics about the database.
  """

  use GallformersWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gallformers.{Galls, Glossaries, Images, Sources}
  alias Gallformers.Plants
  alias GallformersWeb.Schemas

  tags(["Stats"])

  operation(:index,
    summary: "Get statistics",
    description: "Returns summary statistics about the database",
    responses: [
      ok: {"Statistics", "application/json", Schemas.Stats}
    ]
  )

  @doc """
  GET /api/v2/stats
  Returns summary statistics.
  """
  def index(conn, _params) do
    stats = %{
      galls: Galls.count_galls(),
      hosts: Plants.count_hosts(),
      sources: Sources.count_sources(),
      glossary: Glossaries.count_glossary(),
      undescribed_galls: Galls.count_undescribed_galls(),
      images: Images.count_images()
    }

    json(conn, stats)
  end
end
