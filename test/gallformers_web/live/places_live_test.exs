defmodule GallformersWeb.PlacesLiveTest do
  @moduledoc """
  LiveView tests for the public Places browse page.
  """
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "places browse page" do
    test "renders the page with Places title", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/places")

      assert html =~ "Browse geographic places"
      assert page_title(view) =~ "Places"
    end

    test "renders the tree with Western Hemisphere root", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/places")

      assert html =~ "Western Hemisphere"
    end

    test "shows continents when root is expanded", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places")

      html =
        view
        |> element(~s{button[phx-click="toggle_node"][phx-value-key="p-WH"]})
        |> render_click()

      assert html =~ "North America"
      assert html =~ "Caribbean"
    end

    test "expand all reveals the full tree", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places")

      html =
        view
        |> element(~s{button[phx-click="expand_all"]})
        |> render_click()

      assert html =~ "Western Hemisphere"
      assert html =~ "North America"
      assert html =~ "United States"
      assert html =~ "California"
    end

    test "collapse all hides expanded nodes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places")

      # First expand all
      view
      |> element(~s{button[phx-click="expand_all"]})
      |> render_click()

      # Then collapse all
      html =
        view
        |> element(~s{button[phx-click="collapse_all"]})
        |> render_click()

      # Root should still be visible but children should not be expanded
      assert html =~ "Western Hemisphere"
      # North America should not be visible (collapsed)
      refute html =~ "California"
    end

    test "search filters the tree", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places")

      html =
        view
        |> element("#places-tree-search-form")
        |> render_change(%{"query" => "California"})

      assert html =~ "California"
    end

    test "search with no results shows empty tree", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places")

      view
      |> element("#places-tree-search-form")
      |> render_change(%{"query" => "Xyzzynotaplace"})

      # The tree should have no nodes - no toggle buttons should be present
      refute has_element?(view, ~s{button[phx-click="toggle_node"]})
    end

    test "clearing search restores full tree", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places")

      # Search first
      view
      |> element("#places-tree-search-form")
      |> render_change(%{"query" => "California"})

      # Clear search
      html =
        view
        |> element("#places-tree-search-form")
        |> render_change(%{"query" => ""})

      assert html =~ "Western Hemisphere"
    end
  end
end
