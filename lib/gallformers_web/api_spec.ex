defmodule GallformersWeb.ApiSpec do
  @moduledoc """
  OpenAPI specification for the Gallformers API.
  """

  alias OpenApiSpex.{Info, OpenApi, Paths, Server}

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      info: %Info{
        title: "Gallformers API",
        version: "2.0.0",
        description: """
        Public API for accessing Gallformers data.

        The Gallformers API provides read-only access to:
        - Galls (plant growths caused by insects and other organisms)
        - Host plants
        - Taxonomy (families, genera, sections)
        - Sources (scientific references)
        - Glossary terms
        - Geographic places
        - Search and explore functionality

        ## Caching

        All successful API responses include HTTP caching headers:
        - `Cache-Control: public, max-age=3600` (1 hour TTL)
        - `ETag` header with a content hash

        Clients can send `If-None-Match` with a previously received ETag value to get
        a `304 Not Modified` response if the data hasn't changed, saving bandwidth.
        Error responses (4xx/5xx) are not cached (`Cache-Control: no-store`).
        """
      },
      servers: servers_for_env(),
      paths: Paths.from_router(GallformersWeb.Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp servers_for_env do
    prod_server = %Server{url: "https://gallformers.org", description: "Production"}
    dev_server = %Server{url: "http://localhost:4000", description: "Development"}

    if Application.get_env(:gallformers, :env) == :prod do
      [prod_server, dev_server]
    else
      [dev_server, prod_server]
    end
  end
end
