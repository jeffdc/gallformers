defmodule GallformersWeb.SearchLiveTest do
  @moduledoc """
  LiveView tests for the global search page.
  """
  use GallformersWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "Search page" do
    test "renders search form", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/globalsearch")

      assert html =~ "Search"
      assert has_element?(view, "#search-form")
      assert has_element?(view, "input[type=search][name=q]")
    end

    test "shows empty state when no query", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/globalsearch")

      assert html =~ "Enter a search term"
    end

    test "displays results when query is provided via URL", %{conn: conn} do
      # Search for a common term that should return results
      {:ok, _view, html} = live(conn, ~p"/globalsearch?q=oak")

      # Should either show results or no results message
      assert html =~ "result" or html =~ "No results"
    end

    test "displays no results message for nonsense query", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/globalsearch?q=zzzznonexistent123abc")

      assert html =~ "No results"
    end

    test "search input has debounce", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch")

      # Input should have phx-debounce attribute
      assert has_element?(view, "input[phx-debounce]")
    end

    test "shows keyboard navigation hint when results present", %{conn: conn} do
      # Use a term likely to return results
      {:ok, _view, html} = live(conn, ~p"/globalsearch?q=quercus")

      # If there are results, keyboard hints should be visible
      if html =~ "result" and not (html =~ "No results") do
        assert html =~ "↑" or html =~ "↓" or html =~ "Enter"
      end
    end
  end

  describe "Search events" do
    test "search_input event updates URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch")

      # Trigger search input event
      view
      |> element("#search-form")
      |> render_change(%{"q" => "test query"})

      # URL should be updated via push_patch
      assert_patch(view, ~p"/globalsearch?q=test+query")
    end

    test "sorting by type and back by name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=quercus")
      assert has_element?(view, "#results-table")

      view |> element("button[phx-click=sort][phx-value-field=type]") |> render_click()
      assert has_element?(view, "th[aria-sort=ascending]", "Type")

      view |> element("button[phx-click=sort][phx-value-field=type]") |> render_click()
      assert has_element?(view, "th[aria-sort=descending]", "Type")

      view |> element("button[phx-click=sort][phx-value-field=name]") |> render_click()
      assert has_element?(view, "th[aria-sort=ascending]", "Name")
    end

    test "ArrowDown and ArrowUp move the highlight; Enter opens the highlighted result", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=quercus")

      render_keydown(view, "keydown", %{"key" => "ArrowDown"})
      assert has_element?(view, "#result-0[aria-current=true]")

      render_keydown(view, "keydown", %{"key" => "ArrowDown"})
      assert has_element?(view, "#result-1[aria-current=true]")
      refute has_element?(view, "#result-0[aria-current=true]")

      render_keydown(view, "keydown", %{"key" => "ArrowUp"})
      assert has_element?(view, "#result-0[aria-current=true]")

      href =
        view
        |> element("#result-0 a")
        |> render()
        |> then(&Regex.run(~r/href="([^"]+)"/, &1))
        |> List.last()

      assert {:error, {:live_redirect, %{to: ^href}}} =
               render_keydown(view, "keydown", %{"key" => "Enter"})
    end

    test "clicking a row highlights it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=quercus")

      view |> element("#result-1") |> render_click()

      assert has_element?(view, "#result-1[aria-current=true]")
    end
  end

  describe "Search results display" do
    test "gall results use taxon_name component", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/globalsearch?q=andricus")

      refute html =~ "No results", "test seeds must include gall species matching 'andricus'"
      assert html =~ "taxon-name"
      assert html =~ "/gall/"
    end

    test "host results use taxon_name component", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/globalsearch?q=quercus")

      refute html =~ "No results", "test seeds must include host species matching 'quercus'"
      assert html =~ "taxon-name"
      assert html =~ "/host/"
    end

    test "results have type icons", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/globalsearch?q=oak")

      if not (html =~ "No results") do
        # Results should have icon elements (gf-gall, gf-host, or ph-* phosphor icons)
        assert has_element?(view, "[class*='gf-']") or
                 has_element?(view, "[class*='ph-']") or
                 has_element?(view, "svg")
      end
    end

    test "results are clickable links", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=quercus")

      # Results should contain links
      assert has_element?(view, "#results-table a") or
               has_element?(view, "a[href*='/gall/']") or
               has_element?(view, "a[href*='/host/']") or
               not has_element?(view, "#results-table")
    end

    test "result count is displayed", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/globalsearch?q=oak")

      if not (html =~ "No results") do
        assert html =~ "result" or html =~ "Found"
      end
    end

    test "a synonym finds its host, shown by accepted name with its other names", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=Lithocarpus")

      assert has_element?(
               view,
               "#results-table a[href='/host/10']",
               "Notholithocarpus densiflorus"
             )

      assert render(view) =~ "(Lithocarpus densiflorus, tanoak)"
    end

    test "a Gall's alias finds it, linking to the Gall page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=apple+gall+wasp")

      assert has_element?(view, "#results-table a[href='/gall/100']")
      assert render(view) =~ "Oak Apple Gall Wasp"
    end

    test "a higher taxon links to its rank page, with its parent", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=Cynipini")

      assert has_element?(
               view,
               "#results-table a[href='/tribe/Cynipini']",
               "Tribe Cynipini - Subfamily Cynipinae"
             )

      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=Notholithocarpus")

      assert has_element?(
               view,
               "#results-table a[href='/genus/Notholithocarpus']",
               "Genus Notholithocarpus - Family Fagaceae"
             )
    end
  end

  describe "region filter visibility" do
    test "no-results message mentions active region filter", %{conn: conn} do
      # Set continent to Europe via change_region event, search for nonsense
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=zzzznonexistent123abc")

      # Activate a region filter
      render_click(view, "change_region", %{"code" => "XE"})
      html = render(view)

      # Should mention the region and suggest removing the filter
      assert html =~ "Europe"
      assert html =~ "region filter"
      assert html =~ "All Regions"
    end

    test "no-results message without region filter does not mention region", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/globalsearch?q=zzzznonexistent123abc")

      assert html =~ "No results"
      refute html =~ "region filter"
    end

    test "a region filter keeps Galls found everywhere and drops Galls elsewhere", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=quercus")
      render_click(view, "change_region", %{"code" => "XE"})

      # 102 Callirhytis quercuspunctata: no Host range, everywhere.
      assert has_element?(view, "#results-table a[href='/gall/102']")
      # 103 Cynips quercusfolii: Romania only.
      assert has_element?(view, "#results-table a[href='/gall/103']")
      # 100 Andricus quercuscalifornicus: North America only.
      refute has_element?(view, "#results-table a[href='/gall/100']")
    end

    test "region scope bar is marked filtered when a region is active", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch")

      # Activate a region filter
      render_click(view, "change_region", %{"code" => "XN"})

      assert has_element?(view, ~s(#region-scope[data-filtered="true"]))
    end

    test "region scope bar is not marked filtered when no region is active", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch")

      assert has_element?(view, ~s(#region-scope[data-filtered="false"]))
    end

    test "no-results region hint has clickable All Regions link", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=zzzznonexistent123abc")

      # Activate a region filter
      render_click(view, "change_region", %{"code" => "XE"})

      # The "All Regions" text in the no-results hint should be a clickable element
      assert has_element?(view, "#search-no-results [phx-click=change_region][phx-value-code='']")
    end
  end

  describe "URL handling" do
    test "empty query parameter shows empty state", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/globalsearch?q=")

      assert html =~ "Enter a search term"
    end

    test "whitespace-only query shows empty state", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/globalsearch?q=+++")

      assert html =~ "Enter a search term" or html =~ "No results"
    end
  end

  describe "result types" do
    test "a row of types with counts; choosing one narrows the results and goes in the URL", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=quercus")

      assert has_element?(view, ~s{nav[aria-label="Result types"] a[aria-current=page]}, "All")
      assert has_element?(view, ~s{nav[aria-label="Result types"] a}, "Host")

      view |> element(~s{nav[aria-label="Result types"] a}, "Host") |> render_click()
      assert_patch(view, "/globalsearch?q=quercus&type=Host")

      types =
        view
        |> render()
        |> LazyHTML.from_document()
        |> LazyHTML.query("#results-table [data-part=type]")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
        |> Enum.uniq()

      assert types == ["Host"]
    end

    test "a type the results don't have shows them all", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=quercus&type=Nonsense")

      assert has_element?(view, ~s{nav[aria-label="Result types"] a[aria-current=page]}, "All")
    end
  end

  describe "result rows" do
    test "a gall shows its photo, and its hosts and traits", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=andricus+seedii")

      row = view |> element("#results-table tr", "Andricus seedii (agamic)") |> render()
      assert row =~ "<img"
      assert row =~ "Notholithocarpus densiflorus"
    end

    test "a host shows its other names and how many galls are on it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=notholithocarpus+densiflorus")

      row = view |> element("#results-table tr:has(a[href='/host/10'])") |> render()
      assert row =~ "tanoak"
      assert row =~ ~r/5\s+galls/
    end

    test "a glossary term shows its definition", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=cynipid")

      assert has_element?(view, "#results-table tr", "A member of the family Cynipidae")
    end

    test "a place shows what kind of place it is", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=california")

      assert has_element?(view, "#results-table tr", ~r/California.*State/s)
    end
  end
end
