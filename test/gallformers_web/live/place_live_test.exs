defmodule GallformersWeb.PlaceLiveTest do
  use GallformersWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "place detail page" do
    test "renders a subdivision by code", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/place/US-CA")

      assert html =~ "California"
      assert html =~ "US-CA"
    end

    test "renders a country with children links", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/place/US")

      assert html =~ "United States"
      assert html =~ "California"
    end

    test "renders breadcrumb ancestors", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/place/US-CA")

      assert html =~ "North America"
      assert html =~ "United States"
    end

    test "renders a leaf country with no children section", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/place/BS")

      assert html =~ "Bahamas"
      refute html =~ "Subdivisions"
    end

    test "renders a continent with countries", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/place/XN")

      assert html =~ "North America"
      assert html =~ "United States"
      assert html =~ "Canada"
    end

    test "includes range map", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/place/US")

      assert html =~ "phx-hook=\"RangeMap\""
    end

    test "navigate_to_place event redirects to place page", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/place/US")

      assert {:error, {:live_redirect, %{to: "/place/US-CA"}}} =
               render_hook(view, "navigate_to_place", %{"code" => "US-CA"})
    end
  end
end
