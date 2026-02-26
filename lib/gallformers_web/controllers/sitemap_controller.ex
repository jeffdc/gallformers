defmodule GallformersWeb.SitemapController do
  @moduledoc """
  Controller for generating sitemap.xml.

  Generates a comprehensive sitemap including all public pages:
  - Static pages (home, about, glossary, etc.)
  - All gall species pages
  - All host plant pages
  - All family pages
  - All genus pages
  - All section pages
  - All place pages
  - All source pages
  """
  use GallformersWeb, :controller

  import Ecto.Query

  alias Gallformers.Repo
  alias Gallformers.Species.Species

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
      family_urls() ++
      genus_urls() ++
      section_urls() ++
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
      %{loc: "#{@base_url}/explore", changefreq: "weekly", priority: "0.8"}
    ]
  end

  # All gall species pages
  defp gall_urls do
    from(s in Species,
      where: s.taxoncode == "gall",
      select: s.id
    )
    |> Repo.all()
    |> Enum.map(fn id ->
      %{loc: "#{@base_url}/gall/#{id}", changefreq: "weekly", priority: "0.8"}
    end)
  end

  # All host plant pages
  defp host_urls do
    from(s in Species,
      where: s.taxoncode == "plant",
      select: s.id
    )
    |> Repo.all()
    |> Enum.map(fn id ->
      %{loc: "#{@base_url}/host/#{id}", changefreq: "weekly", priority: "0.7"}
    end)
  end

  # All family pages
  defp family_urls do
    from(t in "taxonomy",
      where: t.type == "family",
      select: t.id
    )
    |> Repo.all()
    |> Enum.map(fn id ->
      %{loc: "#{@base_url}/family/#{id}", changefreq: "monthly", priority: "0.6"}
    end)
  end

  # All genus pages
  defp genus_urls do
    from(t in "taxonomy",
      where: t.type == "genus",
      select: t.id
    )
    |> Repo.all()
    |> Enum.map(fn id ->
      %{loc: "#{@base_url}/genus/#{id}", changefreq: "monthly", priority: "0.6"}
    end)
  end

  # All section pages
  defp section_urls do
    from(t in "taxonomy",
      where: t.type == "section",
      select: t.id
    )
    |> Repo.all()
    |> Enum.map(fn id ->
      %{loc: "#{@base_url}/section/#{id}", changefreq: "monthly", priority: "0.5"}
    end)
  end

  # All place pages
  defp place_urls do
    from(p in "place",
      select: p.code
    )
    |> Repo.all()
    |> Enum.map(fn code ->
      %{loc: "#{@base_url}/place/#{code}", changefreq: "monthly", priority: "0.5"}
    end)
  end

  # All source pages
  defp source_urls do
    from(s in "source",
      select: s.id
    )
    |> Repo.all()
    |> Enum.map(fn id ->
      %{loc: "#{@base_url}/source/#{id}", changefreq: "monthly", priority: "0.5"}
    end)
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
