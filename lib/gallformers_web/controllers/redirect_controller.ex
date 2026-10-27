defmodule GallformersWeb.RedirectController do
  @moduledoc """
  Handles 301 redirects from legacy URLs to their new canonical locations.
  """
  use GallformersWeb, :controller

  alias GallformersWeb.TaxonomyURL

  @doc """
  Redirects /refindex to /articles
  """
  def articles(conn, _params) do
    # Preserve any query params (e.g., ?tag=...)
    query_string = conn.query_string

    path =
      if query_string == "" do
        "/articles"
      else
        "/articles?#{query_string}"
      end

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: path)
  end

  @doc """
  Redirects /ref/:slug to /articles/:slug
  """
  def article(conn, %{"slug" => slug}) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: "/articles/#{slug}")
  end

  @doc """
  Redirects old /taxonomy/:id URLs (old taxonomy IDs) to the rank page of
  the taxon the crosswalk maps them to (`TaxonomyURL.legacy_path/1`):
  /family/:name, /genus/:name, /section/:name or /:rank/:name (e.g.
  /subfamily/Cynipinae). An ID the crosswalk does not know is not found.
  """
  def taxonomy(conn, %{"id" => id_str}) do
    with {_id, ""} <- Integer.parse(id_str),
         path when is_binary(path) <- TaxonomyURL.legacy_path(id_str) do
      conn
      |> put_status(:moved_permanently)
      |> redirect(to: path)
    else
      _ -> render_404(conn)
    end
  end

  defp render_404(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(GallformersWeb.ErrorHTML)
    |> render(:"404")
  end

  @doc """
  Redirects /explore to the appropriate new browse page.

  Maps old tab params to new routes:
  - /explore or /explore?tab=galls -> /galls
  - /explore?tab=undescribed -> /galls
  - /explore?tab=hosts -> /hosts
  - /explore?tab=places -> /places
  """
  def explore(conn, params) do
    path =
      case params["tab"] do
        "hosts" -> "/hosts"
        "places" -> "/places"
        _other -> "/galls"
      end

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: path)
  end
end
