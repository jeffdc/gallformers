defmodule GallformersWeb.AnalyticsLiveTest do
  @moduledoc """
  The public analytics page (`/analytics`): the period (`?range=`, today by
  default), totals, the daily chart (`bar_chart`) for longer periods, top
  pages, referrers (15 a page), devices and browsers with their shares.

  Page views are inserted for today, which every period reads raw.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Gallformers.Analytics.PageView
  alias Gallformers.Repo

  defp view!(attrs) do
    Repo.insert!(
      PageView.changeset(
        %PageView{},
        Map.merge(
          %{path: "/gall/821", visitor_hash: "v1", browser: "Firefox", device_type: "desktop"},
          attrs
        )
      )
    )
  end

  setup do
    view!(%{})
    view!(%{visitor_hash: "v2", referrer_host: "www.inaturalist.org"})
    view!(%{path: "/id", visitor_hash: "v2", browser: "Safari", device_type: "mobile"})
    :ok
  end

  test "today by default: page views and unique visitors, no chart", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/analytics")

    assert has_element?(view, "h1", "Site analytics")
    assert has_element?(view, ~s{nav[aria-label=Period] a[aria-current=page]}, "Today")
    assert has_element?(view, "[data-part=label]", "Unique visitors")
    refute has_element?(view, "#daily-analytics-chart")
    assert page_title(view) =~ "Analytics"
  end

  test "a longer period: totals and the daily chart, the period in the URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/analytics?range=7d")

    assert has_element?(view, ~s{nav[aria-label=Period] a[aria-current=page]}, "7 days")
    assert has_element?(view, "[data-part=label]", "Visitors a day, on average")
    assert has_element?(view, "#daily-analytics-chart svg[role=img]")
    assert has_element?(view, "#daily-analytics-chart table.sr-only tbody tr")
  end

  test "choosing a period patches the URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/analytics")

    view |> element("nav[aria-label=Period] a", "30 days") |> render_click()

    assert_patch(view, ~p"/analytics?range=30d")
    assert has_element?(view, "#daily-analytics-chart")
  end

  test "an unknown period is today", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/analytics?range=forever")
    assert has_element?(view, ~s{nav[aria-label=Period] a[aria-current=page]}, "Today")
  end

  test "top pages, each linked, with views and visitors", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/analytics")

    assert has_element?(view, ~s{#top-pages a[href="/gall/821"]}, "/gall/821")
    assert view |> element(~s{#top-pages tr[id$="/gall/821"]}) |> render() =~ ~r/>\s*2\s*</
  end

  test "referrers, devices and browsers with their shares", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/analytics")

    assert has_element?(view, "#referrers", "www.inaturalist.org")
    assert has_element?(view, "#devices li", "Desktop")
    assert has_element?(view, "#devices li", "66.7%")
    assert has_element?(view, "#browsers li", "Safari")
  end

  test "referrers page through 15 at a time", %{conn: conn} do
    for i <- 1..16, do: view!(%{visitor_hash: "r#{i}", referrer_host: "site#{i}.example"})

    {:ok, view, _html} = live(conn, ~p"/analytics")
    assert has_element?(view, "#referrers tr:nth-child(15)")
    refute has_element?(view, "#referrers tr:nth-child(16)")

    render_click(view, "referrer_page", %{"page" => 2})
    assert has_element?(view, "#referrers tr")
    refute has_element?(view, "#referrers tr:nth-child(15)")
  end
end
