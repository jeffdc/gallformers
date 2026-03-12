defmodule GallformersWeb.HostsBrowseLiveTest do
  @moduledoc """
  LiveView tests for the public Hosts browse page at /hosts.
  """
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "/hosts page" do
    test "renders the hosts browse page with tree", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/hosts")

      # FamilyAlpha and FamilyBeta are the families linked to host species in test seeds
      assert html =~ "FamilyAlpha" or html =~ "FamilyBeta"
    end

    test "displays page title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/hosts")

      assert page_title(view) =~ "Hosts"
    end

    test "shows genera when family is expanded", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/hosts")

      html =
        view
        |> element(~s{button[phx-click="toggle_node"][phx-value-key="f-20"]})
        |> render_click()

      assert html =~ "GenusAlpha"
    end

    test "search filters the tree", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/hosts")

      html =
        view
        |> element("#hosts-browse-search-form")
        |> render_change(%{"query" => "GenusAlpha"})

      assert html =~ "GenusAlpha"
    end

    test "search with no results shows empty message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/hosts")

      view
      |> element("#hosts-browse-search-form")
      |> render_change(%{"query" => "Xyzzynotaspecies"})

      refute has_element?(view, ~s{button[phx-click="toggle_node"]})
    end

    test "expand all reveals the full tree", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/hosts")

      html =
        view
        |> element(~s{button[phx-click="expand_all"]})
        |> render_click()

      assert html =~ "FamilyAlpha"
    end

    test "collapse all hides expanded nodes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/hosts")

      # Expand all first
      view
      |> element(~s{button[phx-click="expand_all"]})
      |> render_click()

      # Then collapse all
      html =
        view
        |> element(~s{button[phx-click="collapse_all"]})
        |> render_click()

      assert html =~ "FamilyAlpha"
    end
  end
end
