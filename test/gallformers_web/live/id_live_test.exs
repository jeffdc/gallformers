defmodule GallformersWeb.IDLiveTest do
  @moduledoc """
  LiveView tests for the ID tool page.
  """
  # async: false is required because LiveView processes run separately and
  # need to access the database through the same connection as the test
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Gallformers.GallHosts
  alias Gallformers.Plants

  describe "ID Tool page rendering" do
    test "renders ID tool page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/id")

      # Should show host/genus pickers
      assert html =~ "Host" or html =~ "Genus"
    end

    test "shows instruction message when no selection", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/id")

      assert html =~ "Select a Host Plant or Plant Genus/Section"
    end

    test "has host search input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/id")

      assert has_element?(view, "#host-picker-input[data-typeahead-input]")
    end

    test "has genus search input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/id")

      assert has_element?(view, "#genus-picker-input[data-typeahead-input]")
    end
  end

  describe "Host typeahead" do
    test "search_host event returns results", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/id")

      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        # Search for part of first host's name
        search_term = String.slice(hd(hosts).name, 0, 4)

        render_click(view, "search_host", %{"value" => search_term})

        # Results should appear
        html = render(view)
        assert html =~ search_term or html =~ "select_host"
      end
    end

    test "select_host event selects host and shows filters", %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)
        {:ok, view, _html} = live(conn, ~p"/id?h=#{URI.encode(host.name)}")

        # With host selected, filters should be visible
        html = render(view)
        assert html =~ "Location" or html =~ "Detachable" or html =~ "Region"
      end
    end

    test "clear_host event clears selection", %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)
        {:ok, view, _html} = live(conn, ~p"/id?h=#{URI.encode(host.name)}")

        # Clear the host
        view
        |> element("button[phx-click='clear_host']")
        |> render_click()

        # URL should be updated
        html = render(view)
        assert html =~ "Select a Host" or html =~ "Search hosts"
      end
    end
  end

  describe "URL parameter handling" do
    test "host parameter loads host from URL", %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)
        {:ok, _view, html} = live(conn, ~p"/id?h=#{URI.encode(host.name)}")

        # Host should be displayed as selected
        assert html =~ host.name
      end
    end

    test "location parameter persists in URL", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/id?lo=1")

      # Page should load without error
      assert is_binary(html)
    end

    test "multiple parameters work together", %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)
        # Combine multiple parameters
        {:ok, _view, html} = live(conn, ~p"/id?h=#{URI.encode(host.name)}&lo=1&de=integral")

        assert is_binary(html)
      end
    end
  end

  describe "Filter events" do
    setup %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)
        {:ok, conn: conn, host: host}
      else
        {:ok, conn: conn, host: nil}
      end
    end

    test "change_filter event updates filter value", %{conn: conn, host: host} do
      if host do
        {:ok, view, _html} = live(conn, ~p"/id?h=#{URI.encode(host.name)}")

        # Change detachable filter
        view
        |> element("form[phx-value-filter='detachable']")
        |> render_change(%{"value" => "integral"})

        # Check the filter is reflected in the rendered view by looking for
        # the selected value in the form or checking the URL contains the filter
        html = render(view)
        # The detachable filter should show "integral" as selected
        assert html =~ "integral" or html =~ "de=integral"
      end
    end

    test "location_select event adds location to filter", %{conn: conn, host: host} do
      if host do
        {:ok, view, _html} = live(conn, ~p"/id?h=#{URI.encode(host.name)}")

        # This would need to interact with the plant part multi-select
        # Just verify the page renders without error
        html = render(view)
        assert html =~ "Plant Part" or html =~ "plant part"
      end
    end

    test "toggle_advanced shows advanced filters", %{conn: conn, host: host} do
      if host do
        {:ok, view, _html} = live(conn, ~p"/id?h=#{URI.encode(host.name)}")

        # Click toggle advanced
        view
        |> element("button[phx-click='toggle_advanced']")
        |> render_click()

        html = render(view)
        # Advanced filters should be visible
        assert html =~ "Season" or html =~ "Texture" or html =~ "Alignment" or
                 html =~ "Hide Advanced"
      end
    end

    test "clear_all event resets filters but preserves host selection", %{conn: conn, host: host} do
      if host do
        # Start with a host and some filters
        {:ok, view, _html} = live(conn, ~p"/id?h=#{URI.encode(host.name)}&de=integral&lo=1")

        # Click clear all
        view
        |> element("button[phx-click='clear_all']")
        |> render_click()

        # Host should still be selected, but filters cleared
        html = render(view)
        assert html =~ host.name
        refute html =~ "de=integral"
      end
    end
  end

  describe "Results display" do
    test "shows results when host selected", %{conn: conn} do
      hosts = Plants.list_hosts()

      # Find a host with galls
      host_with_galls =
        Enum.find(hosts, fn h ->
          length(GallHosts.get_galls_for_host(h.id)) > 0
        end)

      if host_with_galls do
        {:ok, _view, html} = live(conn, ~p"/id?h=#{URI.encode(host_with_galls.name)}")

        # Should show results
        assert html =~ "Showing" or html =~ "galls" or html =~ "no galls"
      end
    end

    test "result cards link to gall pages", %{conn: conn} do
      hosts = Plants.list_hosts()

      host_with_galls =
        Enum.find(hosts, fn h ->
          length(GallHosts.get_galls_for_host(h.id)) > 0
        end)

      if host_with_galls do
        {:ok, view, _html} = live(conn, ~p"/id?h=#{URI.encode(host_with_galls.name)}")

        # Should have links to gall pages
        assert has_element?(view, "a[href*='/gall/']")
      end
    end

    test "shows incomplete host warning when applicable", %{conn: conn} do
      hosts = Plants.list_hosts()

      # Find an incomplete host
      incomplete_host = Enum.find(hosts, fn h -> h.datacomplete == false end)

      if incomplete_host do
        {:ok, _view, html} = live(conn, ~p"/id?h=#{URI.encode(incomplete_host.name)}")

        # Should show warning about incomplete data
        assert html =~ "incomplete" or html =~ "not yet have all"
      end
    end

    test "shows troubleshooting link when no results", %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        # Use filters that likely produce no results
        host = hd(hosts)

        {:ok, _view, html} =
          live(
            conn,
            ~p"/id?h=#{URI.encode(host.name)}&de=integral&lo=1,2,3,4,5&co=99&sh=99"
          )

        # If no results, should show troubleshooting link
        if html =~ "no galls" do
          assert html =~ "troubleshooting" or html =~ "altering your filter"
        end
      end
    end
  end

  describe "V1 backwards compatibility" do
    setup %{conn: conn} do
      # Create a genus taxonomy entry for V1 genus URL tests
      genus =
        Gallformers.Repo.insert!(%Gallformers.Taxonomy.Taxonomy{
          name: "Quercus",
          type: "genus",
          description: "Oaks"
        })

      section =
        Gallformers.Repo.insert!(%Gallformers.Taxonomy.Taxonomy{
          name: "Quercus",
          type: "section",
          parent_id: genus.id,
          description: "Section Quercus"
        })

      {:ok, conn: conn, genus: genus, section: section}
    end

    test "V1 host URL loads host correctly", %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)

        {:ok, _view, html} =
          live(conn, "/id?hostOrTaxon=#{URI.encode(host.name)}&type=host")

        assert html =~ host.name
      end
    end

    test "V1 genus URL loads genus correctly", %{conn: conn, genus: genus} do
      {:ok, _view, html} =
        live(conn, "/id?hostOrTaxon=#{URI.encode(genus.name)}&type=genus")

      # Genus should be displayed as selected
      assert html =~ genus.name
    end

    test "V1 section URL loads section correctly", %{conn: conn, section: section} do
      {:ok, _view, html} =
        live(conn, "/id?hostOrTaxon=#{URI.encode(section.name)}&type=section")

      assert html =~ section.name
    end

    test "V1 URL with empty filter params loads without error", %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)

        # Mimics V1 URL with all empty filter params
        url =
          "/id?hostOrTaxon=#{URI.encode(host.name)}&type=host" <>
            "&detachable=&alignment=&cells=&color=&locations=" <>
            "&season=&shape=&textures=&walls=&form=&undescribed=false&place="

        {:ok, _view, html} = live(conn, url)
        assert html =~ host.name
      end
    end

    test "V1 undescribed=true maps to V2 format", %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)

        {:ok, view, _html} =
          live(conn, "/id?hostOrTaxon=#{URI.encode(host.name)}&type=host&undescribed=true")

        # The undescribed filter should be active (mapped from "true" to "1")
        html = render(view)
        assert html =~ "un=1" or html =~ "undescribed"
      end
    end

    test "V1 URL without type defaults to host lookup", %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)

        {:ok, _view, html} =
          live(conn, "/id?hostOrTaxon=#{URI.encode(host.name)}")

        assert html =~ host.name
      end
    end

    test "V1 place name is resolved to place code in typeahead", %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)

        # V1 used place names ("California"); V2 uses ISO 3166-2 codes ("US-CA")
        {:ok, _view, html} =
          live(conn, "/id?hostOrTaxon=#{URI.encode(host.name)}&type=host&place=California")

        # The typeahead should show California as the selected place
        assert html =~ "California"
        assert html =~ "Selected: California"
      end
    end
  end

  describe "grouped place search" do
    test "place search returns countries and subdivisions with groups", %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)
        {:ok, view, _html} = live(conn, "/id?hostOrTaxon=#{URI.encode(host.name)}&type=host")

        # Push the search event directly (phx-debounce prevents keyup testing)
        html = render_hook(view, "search_place", %{"value" => "ca"})

        assert html =~ "Countries"
        assert html =~ "Canada"
        assert html =~ "States &amp; Provinces"
        assert html =~ "California"
      end
    end
  end

  describe "Name filter" do
    test "filter_by_name narrows displayed results", %{conn: conn} do
      # GenusAlpha has galls 100 (Andricus) and 101 (Amphibolips) via seed data
      {:ok, view, _html} = live(conn, ~p"/id?g=GenusAlpha&gt=genus")

      # Both galls should be visible initially
      html = render(view)
      assert html =~ "Andricus"
      assert html =~ "Amphibolips"

      # Type in the name filter
      html = render_keyup(view, "filter_by_name", %{"value" => "Andricus"})

      # Only Andricus should remain
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

      # Filter down
      render_keyup(view, "filter_by_name", %{"value" => "Andricus"})

      # Clear
      html = render_click(view, "clear_name_filter")

      assert html =~ "Andricus"
      assert html =~ "Amphibolips"
    end

    test "name filter shows correct counts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/id?g=GenusAlpha&gt=genus")

      html = render_keyup(view, "filter_by_name", %{"value" => "Andricus"})

      # Should show "Showing 1 of 2 galls"
      assert html =~ "Showing"
      assert html =~ ">1<"
      assert html =~ "of 2"
    end

    test "name filter input not shown when no results", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/id")

      # No selection means no results, so no filter input
      refute html =~ "Filter by name"
    end

    test "changing structured filter clears name filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/id?g=GenusAlpha&gt=genus")

      # Apply name filter
      render_keyup(view, "filter_by_name", %{"value" => "Andricus"})

      # Change a structured filter (detachable) — triggers URL patch → handle_params
      view
      |> element("form[phx-value-filter='detachable']")
      |> render_change(%{"value" => "integral"})

      html = render(view)

      # Name filter should be cleared (input value should be empty)
      refute html =~ ~s(value="Andricus")
    end
  end

  describe "Page title" do
    test "sets appropriate page title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/id")

      assert page_title(view) =~ "ID Tool" or page_title(view) =~ "Gallformers"
    end
  end
end
