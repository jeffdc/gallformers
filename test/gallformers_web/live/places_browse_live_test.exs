defmodule GallformersWeb.PlacesBrowseLiveTest do
  @moduledoc """
  LiveView tests for the public Places browse page at /places.
  """
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

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

    test "shows countries when continent is expanded", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places")

      html =
        view
        |> element(~s{button[phx-click="toggle_node"][phx-value-key="p-XN"]})
        |> render_click()

      assert html =~ "United States"
      assert html =~ "Canada"
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
      refute html =~ "California"
    end
  end
end
