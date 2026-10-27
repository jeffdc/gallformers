defmodule GallformersWeb.SitemapController do
  @moduledoc """
  Controller for generating sitemap.xml.

  Generates a comprehensive sitemap including all public pages, read
  through the contexts:
  - Static pages (home, about, glossary, etc.)
  - Every Gall page (`Gallformers.Catalog`)
  - Every plant page (`Gallformers.Taxa`)
  - Every rank page: family, intermediate ranks, genus, section
    (`Gallformers.Taxa`, through `GallformersWeb.TaxonomyURL`)
  - Every place page (`Gallformers.Places`)
  - Every Source page (`Gallformers.Sources`)
  """
  use GallformersWeb, :controller

  alias Gallformers.{Catalog, Places, Sources, Taxa}
  alias GallformersWeb.TaxonomyURL

  @base_url "https://gallformers.org"

  @doc """
  Renders the sitemap.xml file with all public URLs.
  """
  def index(conn, _params) do
    urls = build_all_urls()

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, render_sitemap(urls))
  end

  defp build_all_urls do
    static_urls() ++
      gall_urls() ++
      host_urls() ++
      rank_urls() ++
      place_urls() ++
      source_urls()
  end

  # Static pages with high priority
  # Note: /id is excluded - it's an interactive tool, not content for indexing
  defp static_urls do
    [
      %{loc: @base_url, changefreq: "daily", priority: "1.0"},
      %{loc: "#{@base_url}/about", changefreq: "monthly", priority: "0.8"},
      %{loc: "#{@base_url}/glossary", changefreq: "weekly", priority: "0.8"},
      %{loc: "#{@base_url}/filterguide", changefreq: "monthly", priority: "0.7"},
      %{loc: "#{@base_url}/articles", changefreq: "weekly", priority: "0.7"},
      %{loc: "#{@base_url}/galls", changefreq: "weekly", priority: "0.8"},
      %{loc: "#{@base_url}/hosts", changefreq: "weekly", priority: "0.8"},
      %{loc: "#{@base_url}/places", changefreq: "weekly", priority: "0.7"}
    ]
  end

  # Every Gall page
  defp gall_urls do
    for id <- Catalog.list_gall_ids() do
      %{loc: "#{@base_url}/gall/#{id}", changefreq: "weekly", priority: "0.8"}
    end
  end

  # Every plant (Host) page
  defp host_urls do
    for id <- Taxa.list_plant_ids() do
      %{loc: "#{@base_url}/host/#{id}", changefreq: "weekly", priority: "0.7"}
    end
  end

  # Every rank page: family, subfamily, tribe, subtribe, genus, section
  defp rank_urls do
    for page <- Taxa.list_rank_pages(), path = TaxonomyURL.public_path(page), path != nil do
      %{loc: "#{@base_url}#{path}", changefreq: "monthly", priority: rank_priority(page.rank)}
    end
  end

  defp rank_priority(rank) when rank in [:family, :genus], do: "0.6"
  defp rank_priority(_rank), do: "0.5"

  # Every place page
  defp place_urls do
    for place <- Places.list_all_places() do
      %{loc: "#{@base_url}/place/#{place.code}", changefreq: "monthly", priority: "0.5"}
    end
  end

  # Every Source page
  defp source_urls do
    for source <- Sources.list_sources() do
      %{loc: "#{@base_url}/source/#{source.id}", changefreq: "monthly", priority: "0.5"}
    end
  end

  defp render_sitemap(urls) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{Enum.map_join(urls, "\n", &render_url/1)}
    </urlset>
    """
  end

  defp render_url(url) do
    """
      <url>
        <loc>#{escape_xml(url.loc)}</loc>
        <changefreq>#{url.changefreq}</changefreq>
        <priority>#{url.priority}</priority>
      </url>
    """
  end

  defp escape_xml(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
