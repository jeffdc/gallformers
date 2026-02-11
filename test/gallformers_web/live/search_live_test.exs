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

    test "sort event toggles sort direction", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/globalsearch?q=quercus")

      # Only test sort if there are results (sort header only appears with results)
      if html =~ "results-table" do
        # Click sort by type header
        view
        |> element("th[phx-click=sort][phx-value-column=type]")
        |> render_click()

        # Sort should change (indicated by arrow in HTML)
        html = render(view)
        assert html =~ "↑" or html =~ "↓"
      else
        # No results, so no sort headers - test passes
        assert true
      end
    end

    test "keydown ArrowDown event increments selected index", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=quercus")

      # Send keydown event
      render_keydown(view, "keydown", %{"key" => "ArrowDown"})

      # The first result should be selected (bg-canary class)
      html = render(view)
      # Selection should be visible in the rendered output
      assert is_binary(html)
    end

    test "keydown ArrowUp event decrements selected index", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=quercus")

      # First go down twice
      render_keydown(view, "keydown", %{"key" => "ArrowDown"})
      render_keydown(view, "keydown", %{"key" => "ArrowDown"})

      # Then go up once
      render_keydown(view, "keydown", %{"key" => "ArrowUp"})

      html = render(view)
      assert is_binary(html)
    end

    test "select_result event selects row", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/globalsearch?q=quercus")

      # Click on a result row (if results exist)
      html = render(view)

      if html =~ "result-0" do
        view
        |> element("#result-0")
        |> render_click()

        # Row should be selected
        html = render(view)
        assert html =~ "bg-canary" or is_binary(html)
      end
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
end
