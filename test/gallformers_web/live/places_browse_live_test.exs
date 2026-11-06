defmodule GallformersWeb.PlacesBrowseLiveTest do
  @moduledoc """
  LiveView tests for the public Places browse page at /places.
  """
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp format(n), do: GallformersWeb.Helpers.format_number(n)

  describe "/places page" do
    test "renders the places browse page with tree", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/places")

      assert html =~ "North America"
      assert html =~ "Europe"
    end

    test "displays page title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places")

      assert page_title(view) =~ "Places"
    end

    test "a continent's tile shows its countries", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places")

      view |> element(~s{nav[aria-label=Continents] a}, "Europe") |> render_click()

      assert_patch(view, "/places?c=XE")
      assert has_element?(view, "#countries", "Romania")
      refute has_element?(view, "#countries", "Canada")
      assert has_element?(view, ~s{nav[aria-label=Continents] a[aria-current=page]}, "Europe")
    end

    test "opens on the continent with the most galls, countries ranked by galls", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places")
      %{counts: counts} = Gallformers.Catalog.place_gall_counts()

      assert has_element?(
               view,
               ~s{nav[aria-label=Continents] a[aria-current=page]},
               "North America"
             )

      assert has_element?(view, "#countries", "United States")
      assert has_element?(view, "#countries", format(counts["US"]))
      assert has_element?(view, ~s{nav[aria-label="Browse by"] a[aria-current=page]}, "By place")
    end

    test "the filter finds places in every continent", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places")

      view |> element("#places-browse-search-form") |> render_change(%{"query" => "Bucharest"})

      assert has_element?(view, "#countries", "Romania")
      assert has_element?(view, "#countries a", "Bucharest")
      refute has_element?(view, "#countries", "United States")
    end

    test "search filters the tree", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places")

      html =
        view
        |> element("#places-browse-search-form")
        |> render_change(%{"query" => "California"})

      assert html =~ "California"
    end

    test "search with no results shows empty message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places")

      view
      |> element("#places-browse-search-form")
      |> render_change(%{"query" => "Xyzzynotaplace"})

      refute has_element?(view, ~s{button[phx-click="toggle_node"]})
    end

    test "expand all reveals the full tree", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places")

      html =
        view
        |> element(~s{button[phx-click="expand_all"]})
        |> render_click()

      assert html =~ "North America"
      assert html =~ "United States"
      assert html =~ "California"
    end

    test "collapse all hides expanded nodes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places")

      # Expand all first
      view
      |> element(~s{button[phx-click="expand_all"]})
      |> render_click()

      # Then collapse all
      html =
        view
        |> element(~s{button[phx-click="collapse_all"]})
        |> render_click()

      assert html =~ "North America"
      # A country's busiest few stay in its row; only the rest fold away.
      assert html =~ "California"
    end
  end
end
