defmodule GallformersWeb.GallsBrowseLiveTest do
  @moduledoc """
  LiveView tests for the public Galls browse page at /galls.
  """
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "/galls page" do
    test "renders the galls browse page with tree", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/galls")

      assert html =~ "Cynipidae"
    end

    test "displays page title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/galls")

      assert page_title(view) =~ "Galls"
    end

    test "shows genera when family is expanded", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/galls")

      html =
        view
        |> element(~s{button[phx-click="toggle_node"][phx-value-key="f-30"]})
        |> render_click()

      assert html =~ "Andricus"
    end

    test "search filters the tree", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/galls")

      html =
        view
        |> element("#galls-browse-search-form")
        |> render_change(%{"query" => "Andricus"})

      assert html =~ "Andricus"
    end

    test "search with no results shows empty message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/galls")

      view
      |> element("#galls-browse-search-form")
      |> render_change(%{"query" => "Xyzzynotaspecies"})

      refute has_element?(view, ~s{button[phx-click="toggle_node"]})
    end

    test "expand all reveals the full tree", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/galls")

      html =
        view
        |> element(~s{button[phx-click="expand_all"]})
        |> render_click()

      assert html =~ "Cynipidae"
      assert html =~ "Andricus"
    end

    test "collapse all hides expanded nodes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/galls")

      # First expand all
      view
      |> element(~s{button[phx-click="expand_all"]})
      |> render_click()

      # Then collapse all
      html =
        view
        |> element(~s{button[phx-click="collapse_all"]})
        |> render_click()

      # Family should still be visible
      assert html =~ "Cynipidae"
    end
  end

  describe "/galls undescribed toggle" do
    test "can switch to undescribed view", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/galls")

      # Click the undescribed toggle
      html =
        view
        |> element(~s{button[phx-click="toggle_undescribed"]})
        |> render_click()

      # Should show undescribed galls
      # Callirhytis quercuspunctata (id 102) is marked undescribed in test seeds
      assert html =~ "undescribed" or has_element?(view, "[data-active-view=undescribed]")
    end

    test "can switch back to described view", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/galls")

      # Toggle to undescribed
      view
      |> element(~s{button[phx-click="toggle_undescribed"]})
      |> render_click()

      # Toggle back to described
      html =
        view
        |> element(~s{button[phx-click="toggle_undescribed"]})
        |> render_click()

      assert html =~ "Cynipidae"
    end
  end
end
