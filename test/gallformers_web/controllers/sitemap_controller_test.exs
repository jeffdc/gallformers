defmodule GallformersWeb.SitemapControllerTest do
  @moduledoc """
  The sitemap (`803b` Task 12): every Gall, plant, rank page, place and
  Source URL, read through `Gallformers.Catalog`, `Gallformers.Taxa`,
  `Gallformers.Places` and `Gallformers.Sources`.

  Uses the converted seeds (`priv/repo/test_seeds.sql`): Gall 300, plant
  10, Cynipidae > Cynipinae > Cynipini > Andricus; plant 11 was a genus
  placeholder and is no taxon.
  """
  use GallformersWeb.ConnCase, async: true

  # The seeds' converted taxa are part of what the sitemap lists.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures

  @base "https://gallformers.org"

  defp locs(conn) do
    body = response(conn, 200)
    Regex.scan(~r{<loc>([^<]+)</loc>}, body, capture: :all_but_first) |> List.flatten()
  end

  test "is XML listing the static pages", %{conn: conn} do
    conn = get(conn, "/sitemap.xml")

    assert response_content_type(conn, :xml) =~ "application/xml"
    assert "#{@base}/about" in locs(conn)
  end

  test "lists every Gall and plant of the new back-end, not old placeholders", %{conn: conn} do
    gall = gall_fixture()
    genus = plant_fixture(rank: :genus, name: "Fixtursitemapus")
    plant = plant_fixture(parent: genus, name: "Fixtursitemapus albus")

    urls = conn |> get("/sitemap.xml") |> locs()

    assert "#{@base}/gall/#{gall.id}" in urls
    assert "#{@base}/gall/300" in urls
    assert "#{@base}/host/#{plant.id}" in urls
    assert "#{@base}/host/10" in urls
    refute "#{@base}/host/11" in urls
    refute "#{@base}/host/#{genus.id}" in urls
  end

  test "lists the rank pages of the taxa, each once", %{conn: conn} do
    plant_fixture(
      rank: :section,
      parent: plant_fixture(rank: :genus, name: "Fixtursitemapia"),
      name: "Fixtursitemapia sect. Fixturae"
    )

    urls = conn |> get("/sitemap.xml") |> locs()

    for path <- [
          "/family/Cynipidae",
          "/subfamily/Cynipinae",
          "/tribe/Cynipini",
          "/genus/Andricus",
          "/genus/Fixtursitemapia",
          "/section/Fixtursitemapia%20sect.%20Fixturae"
        ] do
      assert "#{@base}#{path}" in urls, path
    end

    assert urls == Enum.uniq(urls)
  end

  test "lists places and Sources", %{conn: conn} do
    source = source_fixture("Sitemap", "1959")

    urls = conn |> get("/sitemap.xml") |> locs()

    assert "#{@base}/place/US-CA" in urls
    assert "#{@base}/source/#{source.id}" in urls
  end
end
