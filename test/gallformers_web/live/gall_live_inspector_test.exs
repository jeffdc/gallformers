defmodule GallformersWeb.GallLiveInspectorTest do
  @moduledoc """
  The Gall page read through the Fact inspector (matter `87a1`, task 5):
  every Fact-backed value is a `fact_ref`; selecting one opens who says so
  in the rail's place (a sheet on phones), and the selected Fact is in the
  URL (`?fact=host:7`), so a link opens it. Readers get a hint that the
  underline means something.

  Not async: the fixtures make the Gallformers Source (one per database).
  """
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import GallformersWeb.AdminLiveHelpers
  import GallformersWeb.CurationWebFixtures
  import Gallformers.CatalogFixtures, only: [place_id: 1]

  alias Gallformers.Catalog
  alias Gallformers.DataCase

  setup do
    ctx = curated_gall!(DataCase.test_actor())
    alberta = place_id("CA-AB")

    {:ok, _} =
      Catalog.assert_range(
        DataCase.test_actor(),
        %{gall_id: ctx.gall.id, adjustment: :exclude, place_id: alberta},
        Gallformers.CatalogFixtures.confirm(ctx.weld)
      )

    {:ok, _} =
      Catalog.assert_alias(
        DataCase.test_actor(),
        %{gall_id: ctx.gall.id, name: "webcurata oak gall", kind: :common_name},
        Gallformers.CatalogFixtures.confirm(ctx.weld)
      )

    Map.put(ctx, :alberta, alberta)
  end

  defp ref(key), do: "button[aria-controls=fact-inspector][phx-value-key='#{key}']"

  describe "the values" do
    test "the Inducer, the Hosts, the Traits, the range places and the common names are each a value with Sources",
         %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/gall/#{ctx.gall.id}")

      assert has_element?(
               view,
               "#gall-inducer " <> ref("inducer:#{ctx.wasp.id}"),
               "Andricus webcuratus"
             )

      assert has_element?(view, "#gall-hosts " <> ref("host:#{ctx.oak.id}"), "Quercus webcurata")
      assert has_element?(view, "#gall-traits " <> ref("trait:season:Spring"), "Spring")

      assert has_element?(
               view,
               "#gall-range " <> ref("range:exclude:#{ctx.alberta}"),
               "not in Alberta"
             )

      assert has_element?(
               view,
               "#gall-common-names " <> ref("alias:webcurata oak gall"),
               "webcurata oak gall"
             )
    end

    test "they are on the first render, before the page connects (what search engines read)",
         %{conn: conn} = ctx do
      html = conn |> get(~p"/gall/#{ctx.gall.id}") |> html_response(200)

      assert html =~ ~s(phx-value-key="host:#{ctx.oak.id}")
      assert html =~ "Quercus webcurata"
    end
  end

  describe "the inspector" do
    test "selecting a Host opens who says so in the rail's place, and puts it in the URL",
         %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/gall/#{ctx.gall.id}")
      refute has_element?(view, "section#fact-inspector")

      view |> element("#gall-hosts " <> ref("host:#{ctx.oak.id}")) |> render_click()

      assert_patch(view, ~p"/gall/#{ctx.gall.id}?fact=host:#{ctx.oak.id}")
      assert has_element?(view, "section#fact-inspector [data-part=kind]", "Host")

      assert has_element?(
               view,
               "section#fact-inspector [data-part=of] a[href='/host/#{ctx.oak.id}']"
             )

      assert has_element?(view, "section#fact-inspector a[href='/source/#{ctx.weld.id}']")
      assert has_element?(view, ref("host:#{ctx.oak.id}") <> "[aria-pressed=true]")
      assert has_element?(view, "[data-part=rail-content][data-inspecting]")
    end

    test "closing it brings the rail back", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/gall/#{ctx.gall.id}?fact=host:#{ctx.oak.id}")
      assert has_element?(view, "section#fact-inspector")

      view |> element("section#fact-inspector button[aria-label=Close]") |> render_click()

      assert_patch(view, ~p"/gall/#{ctx.gall.id}")
      refute has_element?(view, "section#fact-inspector")
      refute has_element?(view, "[data-part=rail-content][data-inspecting]")
    end

    test "?fact= opens the inspector on that Fact; an unknown or malformed key is ignored",
         %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/gall/#{ctx.gall.id}?fact=trait:season:Spring")
      assert has_element?(view, "section#fact-inspector [data-part=kind]", "Season")

      {:ok, view, _html} = live(conn, ~p"/gall/#{ctx.gall.id}?fact=host:999999")
      refute has_element?(view, "section#fact-inspector")

      {:ok, view, _html} = live(conn, ~p"/gall/#{ctx.gall.id}?fact=nonsense")
      refute has_element?(view, "section#fact-inspector")
    end

    test "selecting another value moves the inspector to it", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/gall/#{ctx.gall.id}?fact=host:#{ctx.oak.id}")

      view |> element("#gall-traits " <> ref("trait:season:Spring")) |> render_click()

      assert_patch(view, ~p"/gall/#{ctx.gall.id}?fact=trait:season:Spring")
      assert has_element?(view, "section#fact-inspector [data-part=kind]", "Season")
    end
  end

  describe "the readers' hint" do
    test "readers see it, remembered dismissed by the browser", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/gall/#{ctx.gall.id}")

      assert has_element?(
               view,
               "#fact-hint[phx-hook=Dismissible][data-key=gf-fact-hint]",
               "Underlined values show the Sources that state them. Select one to see who says so."
             )

      assert has_element?(view, "#fact-hint button[aria-label=Dismiss]")
    end

    test "a curator in Edit mode doesn't see it", %{conn: conn} = ctx do
      {conn, _user} = log_in_admin(conn, "Ada Curator")
      {:ok, view, _html} = live(conn, ~p"/gall/#{ctx.gall.id}?edit")

      refute has_element?(view, "#fact-hint")
    end
  end
end
