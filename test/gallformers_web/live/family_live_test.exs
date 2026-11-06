defmodule GallformersWeb.FamilyLiveTest do
  @moduledoc """
  Tests for the public family page, which reads `Gallformers.Taxa`
  (`get_by_name/2`, `children_with_ranks/1`, `count_plants_under/1`) and
  `Gallformers.Catalog.count_galls_under/1`.

  Uses the converted seeds (`priv/repo/test_seeds.sql`): Cynipidae >
  Cynipinae (8 Galls under it); Fagaceae > Notholithocarpus (1 plant).
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  # Reading the seeds, converted, is most of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [test_actor: 0]

  alias Gallformers.Catalog
  alias Gallformers.Taxa

  # The words of the element naming `name`.
  defp words(view, selector, name) do
    view
    |> element(selector, name)
    |> render()
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.split()
  end

  describe "FamilyLive with name-based URLs" do
    test "opens on its Galls, with a tab for the taxa within it", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/family/Cynipidae")

      assert has_element?(view, "h1", "Cynipidae")
      assert has_element?(view, "header", "Family")
      assert page_title(view) =~ "Cynipidae"
      assert has_element?(view, "#rank-galls-section [data-part=count]", "8")
      assert has_element?(view, ~s{nav a[aria-current=page]}, "Galls")
      assert has_element?(view, ~s{nav a[href="?tab=within"]}, "Within it")
    end

    test "the taxa within a Gallformer family, with their rank and Galls", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/family/Cynipidae?tab=within")

      assert words(view, "#children li", "Cynipinae") == ["Cynipinae", "subfamily", "8", "galls"]
      assert has_element?(view, ~s{#children a[href="/subfamily/Cynipinae"]})
    end

    test "a plant family lists its genera with common name, species and the Galls on them", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/family/Fagaceae")

      assert has_element?(view, "header", "Host plants")

      assert words(view, "#children tr", "Notholithocarpus") ==
               ["Notholithocarpus", "Tanoaks", "1", "5"]
    end

    test "its Galls include those placed at the family itself", %{conn: conn} do
      cynipidae = Taxa.get_by_legacy_id(:taxonomy, 30)
      gall = gall_fixture(name: "Unknown (Cynipidae) family-page-fixture")

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: cynipidae.id, object_gall_id: gall.id},
          confirm(source_fixture("Weld", "1959"))
        )

      :ok = Catalog.refresh_gall_index([gall.id])
      {:ok, view, _html} = live(conn, "/family/Cynipidae")

      assert has_element?(view, "#rank-galls-section [data-part=count]", "9")
      assert has_element?(view, ~s{a[href="/gall/#{gall.id}"]}, "Undescribed")
    end

    test "an old numeric URL redirects through the crosswalk", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/family/Cynipidae"}}} = live(conn, "/family/30")
    end

    test "an unknown family name is a 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, "/family/Nonexistent") end
    end
  end
end
