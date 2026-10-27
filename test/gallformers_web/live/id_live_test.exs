defmodule GallformersWeb.IDLiveTest do
  @moduledoc """
  LiveView tests for the ID tool page, which reads `Gallformers.Catalog.identify/1`
  (the stored per-Gall lookup table) and the `Gallformers.Taxa` typeaheads.

  Uses the converted seeds (`priv/repo/test_seeds.sql`): plant 10
  Notholithocarpus densiflorus (genus Notholithocarpus, old taxonomy 41;
  synonym Lithocarpus densiflorus; common name tanoak; data-complete) is the
  Host of Galls 300–304, whose Inducers are in Cynipidae (old taxonomy 30);
  Gall 300 has an image, Gall 304 is undescribed. Genus GenusAlpha (old
  taxonomy 10) holds the plants of Galls 100 (Andricus quercuscalifornicus,
  integral) and 101 (Amphibolips confluenta), both in California only.
  Galls with Traits are made in the tests.
  """
  # async: true is required because LiveView processes run separately and
  # need to access the database through the same connection as the test
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  # Reading the seeds, converted, is much of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [test_actor: 0]
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Taxa

  @host "Notholithocarpus densiflorus"
  @host_path "/id?h=Notholithocarpus+densiflorus"

  # The query of the URL the page last patched to, decoded.
  defp patched_query(view) do
    view
    |> assert_patch()
    |> URI.parse()
    |> Map.get(:query)
    |> Kernel.||("")
    |> URI.decode_query()
  end

  defp show_advanced(view) do
    view |> element("button[phx-click='toggle_advanced']") |> render_click()
    view
  end

  # The /gall/:id links the page shows.
  defp gall_links(view) do
    view
    |> render()
    |> then(&Regex.scan(~r{href="/gall/(\d+)"}, &1))
    |> Enum.map(fn [_, id] -> String.to_integer(id) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp cynipidae, do: Taxa.get_by_legacy_id(:taxonomy, 30)

  # A Gall on plant 10 with an Inducer outside Cynipidae and Traits, so the
  # Trait and family filters have something to tell apart.
  defp traited_gall_fixture do
    source = source_fixture("Weld", "1959")
    family = taxon_fixture(rank: :family, name: "Fixtidae", kingdom: "Animalia")
    genus = taxon_fixture(rank: :genus, name: "Fixtus", parent: family, kingdom: "Animalia")
    wasp = taxon_fixture(name: "Fixtus rubens", parent: genus, kingdom: "Animalia")
    gall = gall_fixture(name: "Fixtus rubens gall")

    relationships = [
      %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
      %{type: "host_of", subject_taxon_id: 10, object_gall_id: gall.id}
    ]

    for key <- relationships do
      {:ok, _} = Catalog.assert_relationship(test_actor(), key, confirm(source))
    end

    traits = [
      {"color", "red"},
      {"plant_part", "upper leaf"},
      {"plant_part", "lower leaf"},
      {"texture", "hairy"},
      {"season", "Spring"},
      {"detachable", "integral"}
    ]

    for {trait, value} <- traits do
      {:ok, _} =
        Catalog.assert_trait(
          test_actor(),
          %{gall_id: gall.id, trait: trait, value: value},
          confirm(source)
        )
    end

    :ok = Catalog.refresh_gall_index([gall.id])
    %{gall: gall, family: family}
  end

  describe "ID Tool page rendering" do
    test "renders the host and genus pickers", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/id")

      assert html =~ "Host Plant Species:"
      assert html =~ "Host Plant Genus / Section:"
      assert has_element?(view, "#host-picker-input[data-typeahead-input]")
      assert has_element?(view, "#genus-picker-input[data-typeahead-input]")
    end

    test "shows instruction message when no selection", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/id")

      assert html =~ "Select a Host Plant or Plant Genus/Section"
      refute html =~ "Filter by name"
    end

    test "sets the page title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/id")

      assert page_title(view) =~ "ID Tool"
    end
  end

  describe "Host typeahead" do
    test "finds plants by name, synonym and common name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/id")

      for query <- ["Notholith", "Lithocarpus", "tanoak"] do
        html = render_click(view, "search_host", %{"value" => query})
        assert html =~ "Notholithocarpus densiflorus (Lithocarpus densiflorus, tanoak)"
      end
    end

    test "does not offer gall inducers or genera", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/id")

      html = render_click(view, "search_host", %{"value" => "Andricus"})
      refute html =~ "phx-value-id"
    end

    test "selecting a host writes its name to the URL and shows the filters", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/id")

      render_click(view, "select_host", %{"id" => "10"})

      assert patched_query(view) == %{"h" => @host}
      assert render(view) =~ "Detachable"
    end

    test "clearing the host clears the selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, @host_path)

      view |> element("button[phx-click='clear_host']") |> render_click()

      assert patched_query(view) == %{}
      assert render(view) =~ "Select a Host Plant or Plant Genus/Section"
    end
  end

  describe "Genus typeahead" do
    test "finds plant genera with their common names, not gall genera", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/id")

      html = render_click(view, "search_genus", %{"value" => "Notho"})
      assert html =~ "Notholithocarpus"
      assert html =~ "Tanoaks"

      html = render_click(view, "search_genus", %{"value" => "Andricus"})
      refute html =~ "phx-value-id"
    end

    test "selecting a genus writes its name and rank to the URL", %{conn: conn} do
      genus = Taxa.get_by_legacy_id(:taxonomy, 41)
      {:ok, view, _html} = live(conn, ~p"/id")

      render_click(view, "select_genus", %{"id" => to_string(genus.id)})

      assert patched_query(view) == %{"g" => "Notholithocarpus", "gt" => "genus"}
      assert gall_links(view) == [300, 301, 302, 303, 304]
    end
  end

  describe "URL parameters" do
    test "a host name selects the host and lists its Galls", %{conn: conn} do
      {:ok, view, html} = live(conn, @host_path)

      assert html =~ "Selected: #{@host}"
      assert gall_links(view) == [300, 301, 302, 303, 304]
    end

    test "a host's former name (a synonym) still selects it", %{conn: conn} do
      {:ok, view, html} = live(conn, "/id?h=Lithocarpus+densiflorus")

      assert html =~ "Selected: #{@host}"
      assert gall_links(view) == [300, 301, 302, 303, 304]
    end

    test "an unknown host name selects nothing", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/id?h=Nonexistus+plantus")

      assert html =~ "Select a Host Plant or Plant Genus/Section"
    end

    test "a genus name selects the genus, its Galls on the genus itself too", %{conn: conn} do
      {:ok, view, html} = live(conn, "/id?g=Notholithocarpus&gt=genus")

      assert html =~ "Selected: Notholithocarpus - Tanoaks"
      assert gall_links(view) == [300, 301, 302, 303, 304]
    end

    test "a section name with gt=section selects the section", %{conn: conn} do
      genus = Taxa.get_by_legacy_id(:taxonomy, 41)
      section = plant_fixture(rank: :section, name: "Fixtsection", parent: genus)
      plant = plant_fixture(name: "Fixtsection plantus", parent: section)
      gall = gall_fixture(name: "Fixtsection gall")
      source = source_fixture("Weld", "1959")

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "host_of", subject_taxon_id: plant.id, object_gall_id: gall.id},
          confirm(source)
        )

      {:ok, view, html} = live(conn, "/id?g=Fixtsection&gt=section")

      assert html =~ "Selected: Fixtsection [Section]"
      assert gall_links(view) == [gall.id]
    end

    test "the host's incomplete-data warning shows for an incomplete host", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/id?h=Thymus+alpinus")
      assert html =~ "This host does not yet have all known galls added"

      {:ok, _view, html} = live(conn, @host_path)
      refute html =~ "This host does not yet have all known galls added"
    end

    test "the family filter lists the Inducer families of the host's Galls", %{conn: conn} do
      %{family: family} = traited_gall_fixture()
      {:ok, view, _html} = live(conn, @host_path)

      assert has_element?(
               view,
               "form[phx-value-filter='family'] option[value='#{cynipidae().id}']",
               "Cynipidae"
             )

      assert has_element?(
               view,
               "form[phx-value-filter='family'] option[value='#{family.id}']",
               "Fixtidae"
             )
    end
  end

  describe "Trait filters" do
    setup do
      traited_gall_fixture()
    end

    test "a Trait value in the URL filters the Galls and is selected", %{conn: conn, gall: gall} do
      {:ok, view, _html} = live(conn, @host_path <> "&co=red")

      assert gall_links(view) == [gall.id]

      assert view
             |> show_advanced()
             |> has_element?("form[phx-value-filter='color'] option[selected][value='red']")
    end

    test "a filter change writes readable Trait values to the URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, @host_path)

      view
      |> show_advanced()
      |> element("form[phx-value-filter='color']")
      |> render_change(%{"value" => "red"})

      assert %{"co" => "red"} = patched_query(view)

      render_click(view, "plant_part_select", %{"id" => "upper leaf"})
      assert %{"co" => "red", "lo" => "upper leaf"} = patched_query(view)
    end

    test "plant parts match any value, or all of them", %{conn: conn, gall: gall} do
      {:ok, view, _html} = live(conn, @host_path <> "&lo=upper+leaf,stem")
      assert gall_links(view) == [gall.id]

      {:ok, view, _html} = live(conn, @host_path <> "&lo=upper+leaf,stem&lol=and")
      assert gall_links(view) == []

      {:ok, view, _html} = live(conn, @host_path <> "&lo=upper+leaf,lower+leaf&lol=and")
      assert gall_links(view) == [gall.id]
    end

    test "leaf (anywhere) matches any leaf plant part", %{conn: conn, gall: gall} do
      {:ok, view, html} = live(conn, @host_path <> "&lo=leaf_anywhere")

      assert html =~ "leaf (anywhere)"
      assert gall_links(view) == [gall.id]
    end

    test "textures, season and detachable", %{conn: conn, gall: gall} do
      {:ok, view, _html} = live(conn, @host_path <> "&te=hairy&se=Spring&de=integral")
      assert gall_links(view) == [gall.id]

      {:ok, view, _html} = live(conn, @host_path <> "&se=Fall")
      assert gall_links(view) == []
    end

    test "an unknown Trait value is dropped", %{conn: conn} do
      {:ok, view, _html} = live(conn, @host_path <> "&co=chartreuse")

      assert length(gall_links(view)) == 6
    end

    test "an imageless Gall's card shows a summary of its Traits", %{conn: conn} do
      {:ok, _view, html} = live(conn, @host_path <> "&co=red")

      assert html =~ "A red, hairy gall found on the lower leaf/upper leaf in Spring."
    end

    test "the season filter is labelled by when the Gall forms and grows", %{conn: conn} do
      {:ok, view, _html} = live(conn, @host_path)

      html = view |> element("button[phx-click='toggle_advanced']") |> render_click()

      assert html =~ "Season (forms and grows)"
      refute html =~ "Show Non-Galls"
    end
  end

  describe "the family filter" do
    setup do
      traited_gall_fixture()
    end

    test "filters to the Galls whose Inducer is in the family, written by name", %{
      conn: conn,
      gall: gall,
      family: family
    } do
      {:ok, view, _html} = live(conn, @host_path)

      view
      |> element("form[phx-value-filter='family']")
      |> render_change(%{"value" => to_string(family.id)})

      assert %{"fa" => "Fixtidae"} = patched_query(view)
      assert gall_links(view) == [gall.id]
    end

    test "a family name in the URL selects it", %{conn: conn} do
      {:ok, view, _html} = live(conn, @host_path <> "&fa=Cynipidae")

      assert gall_links(view) == [300, 301, 302, 303, 304]

      assert has_element?(
               view,
               "form[phx-value-filter='family'] option[selected][value='#{cynipidae().id}']"
             )
    end
  end

  describe "old bookmarks" do
    setup do
      traited_gall_fixture()
    end

    test "integer Trait IDs and an old family ID restore the same filters", %{
      conn: conn,
      gall: gall
    } do
      # co=5 red, lo=4 upper leaf, te=10 hairy, se=1 Spring; fa=30 Cynipidae.
      {:ok, old, _html} = live(conn, @host_path <> "&co=5&lo=4,5&lol=and&te=10&se=1")

      {:ok, new, _html} =
        live(conn, @host_path <> "&co=red&lo=upper+leaf,lower+leaf&lol=and&te=hairy&se=Spring")

      assert gall_links(old) == [gall.id]
      assert gall_links(old) == gall_links(new)

      old
      |> element("form[phx-value-filter='detachable']")
      |> render_change(%{"value" => "integral"})

      assert patched_query(old) == %{
               "h" => @host,
               "co" => "red",
               "lo" => "upper leaf,lower leaf",
               "lol" => "and",
               "te" => "hairy",
               "se" => "Spring",
               "de" => "integral"
             }
    end

    test "an old family ID selects its family", %{conn: conn} do
      {:ok, view, _html} = live(conn, @host_path <> "&fa=30")

      assert gall_links(view) == [300, 301, 302, 303, 304]

      view
      |> element("form[phx-value-filter='detachable']")
      |> render_change(%{"value" => "both"})

      assert %{"fa" => "Cynipidae"} = patched_query(view)
    end

    test "an unknown old family ID is ignored", %{conn: conn, gall: gall} do
      {:ok, view, _html} = live(conn, @host_path <> "&fa=999999")

      assert gall_links(view) == Enum.sort([gall.id, 300, 301, 302, 303, 304])

      view
      |> element("form[phx-value-filter='detachable']")
      |> render_change(%{"value" => "both"})

      refute Map.has_key?(patched_query(view), "fa")
    end

    test "an unknown old Trait ID is ignored", %{conn: conn} do
      {:ok, view, _html} = live(conn, @host_path <> "&co=999")

      assert length(gall_links(view)) == 6
    end

    test "ng (show non-galls) is harmless", %{conn: conn} do
      for ng <- ["0", "1"] do
        {:ok, view, _html} = live(conn, @host_path <> "&ng=#{ng}")
        assert length(gall_links(view)) == 6

        view
        |> element("form[phx-value-filter='detachable']")
        |> render_change(%{"value" => "both"})

        refute Map.has_key?(patched_query(view), "ng")
      end
    end
  end

  describe "V1 URLs" do
    setup do
      traited_gall_fixture()
    end

    test "a V1 host URL selects the host", %{conn: conn} do
      {:ok, view, html} = live(conn, "/id?hostOrTaxon=#{URI.encode(@host)}&type=host")

      assert html =~ "Selected: #{@host}"
      assert length(gall_links(view)) == 6
    end

    test "a V1 URL without type is a host", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/id?hostOrTaxon=#{URI.encode(@host)}")

      assert html =~ "Selected: #{@host}"
    end

    test "a V1 genus URL selects the genus", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/id?hostOrTaxon=Notholithocarpus&type=genus")

      assert html =~ "Selected: Notholithocarpus - Tanoaks"
    end

    test "a V1 section URL selects the section", %{conn: conn} do
      genus = Taxa.get_by_legacy_id(:taxonomy, 41)
      plant_fixture(rank: :section, name: "Fixtvone", parent: genus)

      {:ok, _view, html} = live(conn, "/id?hostOrTaxon=Fixtvone&type=section")

      assert html =~ "Selected: Fixtvone [Section]"
    end

    test "V1 filter names with old IDs restore the filters", %{conn: conn, gall: gall} do
      url =
        "/id?hostOrTaxon=#{URI.encode(@host)}&type=host" <>
          "&color=5&locations=4&textures=10&season=1&family=30&detachable=1&undescribed=false"

      {:ok, view, _html} = live(conn, url)
      assert gall_links(view) == []

      url = String.replace(url, "family=30", "family=")
      {:ok, view, _html} = live(conn, url)
      assert gall_links(view) == [gall.id]
    end

    test "a V1 URL with empty filter params loads without error", %{conn: conn} do
      url =
        "/id?hostOrTaxon=#{URI.encode(@host)}&type=host" <>
          "&detachable=&alignment=&cells=&color=&locations=" <>
          "&season=&shape=&textures=&walls=&form=&undescribed=false&place="

      {:ok, view, html} = live(conn, url)
      assert html =~ "Selected: #{@host}"
      assert length(gall_links(view)) == 6
    end

    test "V1 undescribed=true shows only undescribed Galls", %{conn: conn} do
      {:ok, view, _html} =
        live(conn, "/id?hostOrTaxon=#{URI.encode(@host)}&type=host&undescribed=true")

      assert gall_links(view) == [304]
    end

    test "a V1 place name is resolved to the place", %{conn: conn} do
      {:ok, _view, html} =
        live(conn, "/id?hostOrTaxon=#{URI.encode(@host)}&type=host&place=California")

      assert html =~ "Selected: California"
    end
  end

  describe "grouped place search" do
    test "place search returns countries and subdivisions with groups", %{conn: conn} do
      {:ok, view, _html} = live(conn, @host_path)

      # Push the search event directly (phx-debounce prevents keyup testing)
      html = render_hook(view, "search_place", %{"value" => "ca"})

      assert html =~ "Countries"
      assert html =~ "Canada"
      assert html =~ "States &amp; Provinces"
      assert html =~ "California"
    end
  end

  describe "results" do
    test "cards link to the Gall pages, with the image and the undescribed tag", %{conn: conn} do
      {:ok, view, html} = live(conn, @host_path)

      assert has_element?(view, "a[href='/gall/300'] img[src*='300_seed_small']")
      assert has_element?(view, "a[href='/gall/301'] img[src*='noimage']")
      assert html =~ "Undescribed"
      refute html =~ "Non-gall"
      assert html =~ "galls"
    end

    test "clear_all resets the filters but keeps the host", %{conn: conn} do
      {:ok, view, _html} = live(conn, @host_path <> "&de=integral")

      view |> element("button[phx-click='clear_all']") |> render_click()

      assert patched_query(view) == %{"h" => @host}
      assert render(view) =~ "Selected: #{@host}"
    end

    test "a filter matching nothing shows the troubleshooting link", %{conn: conn} do
      {:ok, view, html} = live(conn, @host_path <> "&co=red&de=both")

      assert gall_links(view) == []
      assert html =~ "There are no galls that match your filter"
      assert html =~ "altering your filter choices"
    end
  end

  describe "Name filter" do
    test "filter_by_name narrows displayed results", %{conn: conn} do
      # GenusAlpha has galls 100 (Andricus) and 101 (Amphibolips) via seed data
      {:ok, view, html} = live(conn, ~p"/id?g=GenusAlpha&gt=genus")

      assert html =~ "Andricus"
      assert html =~ "Amphibolips"

      html = render_keyup(view, "filter_by_name", %{"value" => "Andricus"})

      assert html =~ "Andricus"
      refute html =~ "Amphibolips"
    end

    test "name filter is case-insensitive", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/id?g=GenusAlpha&gt=genus")

      html = render_keyup(view, "filter_by_name", %{"value" => "andricus"})

      assert html =~ "Andricus"
      refute html =~ "Amphibolips"
    end

    test "clear_name_filter restores all results", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/id?g=GenusAlpha&gt=genus")

      render_keyup(view, "filter_by_name", %{"value" => "Andricus"})
      html = render_click(view, "clear_name_filter")

      assert html =~ "Andricus"
      assert html =~ "Amphibolips"
    end

    test "name filter shows correct counts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/id?g=GenusAlpha&gt=genus")

      html = render_keyup(view, "filter_by_name", %{"value" => "Andricus"})

      assert html =~ "Showing"
      assert html =~ ">1<"
      assert html =~ "of 2"
    end

    test "name filter persists when structured filter changes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/id?g=GenusAlpha&gt=genus")

      render_keyup(view, "filter_by_name", %{"value" => "Andricus"})

      # detachable=integral matches gall 100, Andricus
      view
      |> element("form[phx-value-filter='detachable']")
      |> render_change(%{"value" => "integral"})

      html = render(view)

      assert html =~ ~s(value="Andricus")
      assert html =~ "Andricus"
    end
  end

  describe "Region scope hint" do
    test "shows hint when region filter produces zero results but other regions have galls", %{
      conn: conn
    } do
      # GenusAlpha's galls are in North America (California host ranges).
      {:ok, view, html} = live(conn, ~p"/id?g=GenusAlpha&gt=genus")
      assert html =~ "Showing"

      html = render_click(view, "change_region", %{"code" => "XE"})

      assert html =~ "other regions"
      assert html =~ "<strong>2</strong>"
    end

    test "does not show hint when no region filter is active and results are empty", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, ~p"/id?g=GenusAlpha&gt=genus&de=integral&co=red")

      assert html =~ "There are no galls that match your filter"
      refute html =~ "other regions"
    end
  end
end
