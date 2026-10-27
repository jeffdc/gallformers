defmodule GallformersWeb.API.StatsController do
  @moduledoc """
  API controller for stats endpoint.

  Returns summary statistics about the database: galls and undescribed
  galls from the gall catalog (`Gallformers.Catalog`), hosts (plants at
  species rank or below) from `Gallformers.Taxa`.
  """

  use GallformersWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gallformers.{Catalog, Glossaries, Images, Sources, Taxa}
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
    galls = Catalog.gall_counts()

    stats = %{
      galls: galls.galls,
      hosts: Taxa.count_plants(),
      sources: Sources.count_sources(),
      glossary: Glossaries.count_glossary(),
      undescribed_galls: galls.undescribed,
      images: Images.count_images()
    }

    json(conn, stats)
  end
end
