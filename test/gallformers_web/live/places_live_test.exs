defmodule GallformersWeb.PlacesTabTest do
  @moduledoc """
  LiveView tests for the Places tab within Explore.
  """
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "explore places tab" do
    test "renders the places tab with tree", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/explore?tab=places")

      assert html =~ "North America"
      assert html =~ "Europe"
    end

    test "shows countries when continent is expanded", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/explore?tab=places")

      html =
        view
        |> element(~s{button[phx-click="toggle_node"][phx-value-key="p-XN"]})
        |> render_click()

      assert html =~ "United States"
      assert html =~ "Canada"
    end

    test "expand all reveals the full tree", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/explore?tab=places")

      html =
        view
        |> element(~s{button[phx-click="expand_all"]})
        |> render_click()

      assert html =~ "North America"
      assert html =~ "United States"
      assert html =~ "California"
    end

    test "collapse all hides expanded nodes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/explore?tab=places")

      # First expand all
      view
      |> element(~s{button[phx-click="expand_all"]})
      |> render_click()

      # Then collapse all
      html =
        view
        |> element(~s{button[phx-click="collapse_all"]})
        |> render_click()

      # Continents should still be visible but children should not be expanded
      assert html =~ "North America"
      # California should not be visible (collapsed)
      refute html =~ "California"
    end

    test "search filters the tree", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/explore?tab=places")

      html =
        view
        |> element("#explore-places-search-form")
        |> render_change(%{"query" => "California"})

      assert html =~ "California"
    end

    test "search with no results shows empty tree", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/explore?tab=places")

      view
      |> element("#explore-places-search-form")
      |> render_change(%{"query" => "Xyzzynotaplace"})

      # The tree should have no nodes - no toggle buttons should be present
      refute has_element?(view, ~s{button[phx-click="toggle_node"]})
    end

    test "clearing search restores full tree", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/explore?tab=places")

      # Search first
      view
      |> element("#explore-places-search-form")
      |> render_change(%{"query" => "California"})

      # Clear search
      html =
        view
        |> element("#explore-places-search-form")
        |> render_change(%{"query" => ""})

      assert html =~ "North America"
    end
  end

  describe "/places redirect" do
    test "redirects /places to /explore?tab=places", %{conn: conn} do
      conn = get(conn, ~p"/places")
      assert redirected_to(conn, 301) == "/explore?tab=places"
    end
  end
end
