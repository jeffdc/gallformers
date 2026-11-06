defmodule GallformersWeb.PlaceLiveTest do
  @moduledoc """
  The public place page, `/place/:code`: the place on the range map, its
  sub-places, and the Galls known there.

  Uses the seeds' places: North America (XN) > United States (US) >
  California (US-CA), and their Galls' ranges in `gall_index`.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  # Reads the converted seeds' places and gall index.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  alias Gallformers.Catalog

  test "the place in its breadcrumb, with its type and code", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/place/US-CA")

    assert has_element?(view, "h1", "California")
    assert has_element?(view, ~s{nav a[href="/places"]}, "Places")
    assert has_element?(view, ~s{nav a[href="/place/XN"]}, "North America")
    assert has_element?(view, ~s{nav a[href="/place/US"]}, "United States")
    assert has_element?(view, "header", "State")
    assert has_element?(view, "header dd", "US-CA")
    assert page_title(view) =~ "California"
    assert has_element?(view, "#place-range-map")
  end

  test "its sub-places, each with the Galls known there", %{conn: conn} do
    %{counts: counts} = Catalog.place_gall_counts()
    {:ok, view, _html} = live(conn, ~p"/place/US")

    assert has_element?(view, ~s{#sub-places a[href="/place/US-CA"]}, "California")
    assert has_element?(view, "#sub-places", "#{counts["US-CA"]}")
  end

  test "the Galls known there, not those with no range data", %{conn: conn} do
    %{counts: counts} = Catalog.place_gall_counts()
    {:ok, view, _html} = live(conn, ~p"/place/US-CA")

    assert has_element?(view, "#place-galls-section h2", "Galls known here")
    assert has_element?(view, "#place-galls-section [data-part=count]", "#{counts["US-CA"]}")
    assert has_element?(view, ~s{#place-galls-section a[href="/gall/100"]})
    # Gall 102's range is everywhere (no range data).
    refute has_element?(view, ~s{#place-galls-section a[href="/gall/102"]})
  end

  test "the name filter narrows the Galls", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/place/US-CA")

    view |> element("#place-search-form") |> render_change(%{"query" => "zzzz-no-gall"})

    assert has_element?(view, "#place-galls-section", "No galls match these filters.")
  end

  test "an unknown code is a 404", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, "/place/ZZ-NOPE") end
  end

  test "a leaf country has no sub-places", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/place/BS")

    assert has_element?(view, "h1", "Bahamas")
    refute has_element?(view, "#sub-places")
  end

  test "a continent lists its countries", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/place/XN")

    assert has_element?(view, "#sub-places", "United States")
    assert has_element?(view, "#sub-places", "Canada")
  end

  test "the map is the range map, and a click on a place opens its page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/place/US")

    assert html =~ ~s(phx-hook="RangeMap")

    assert {:error, {:live_redirect, %{to: "/place/US-CA"}}} =
             render_hook(view, "navigate_to_place", %{"code" => "US-CA"})
  end
end
