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

  # The words of the table row naming `name`.
  defp row_words(view, name) do
    view
    |> element("tbody tr", name)
    |> render()
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.split()
  end

  describe "FamilyLive with name-based URLs" do
    test "renders family page with table of children", %{conn: conn} do
      {:ok, view, html} = live(conn, "/family/Cynipidae")

      assert html =~ "Family:"
      assert html =~ "Cynipidae"
      assert html =~ "Cynipinae"
      assert page_title(view) =~ "Cynipidae"
    end

    test "shows each child's rank and its gall and host counts", %{conn: conn} do
      {:ok, view, html} = live(conn, "/family/Cynipidae")

      assert html =~ "Children (1)"
      assert html =~ "Galls"
      assert html =~ "Hosts"
      assert row_words(view, "Cynipinae") == ["Cynipinae", "subfamily", "8", "0"]

      # A child shows its common name (the migrated taxonomy description).
      {:ok, view, _html} = live(conn, "/family/Fagaceae")

      assert row_words(view, "Notholithocarpus") ==
               ["Notholithocarpus", "(Tanoaks)", "genus", "0", "1"]
    end

    test "child URLs use names not IDs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/family/Cynipidae")

      assert has_element?(view, ~s{a[href="/subfamily/Cynipinae"]})
    end

    test "lists the Galls placed at the family itself", %{conn: conn} do
      cynipidae = Taxa.get_by_legacy_id(:taxonomy, 30)
      gall = gall_fixture(name: "Unknown (Cynipidae) family-page-fixture")

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: cynipidae.id, object_gall_id: gall.id},
          confirm(source_fixture("Weld", "1959"))
        )

      {:ok, view, html} = live(conn, "/family/Cynipidae")

      assert html =~ "Galls placed in this family (1)"
      assert has_element?(view, ~s{a[href="/gall/#{gall.id}"]})
    end

    test "an old numeric URL redirects through the crosswalk", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/family/Cynipidae"}}} = live(conn, "/family/30")
    end

    test "returns error for nonexistent family name", %{conn: conn} do
      {:ok, view, html} = live(conn, "/family/Nonexistent")

      assert html =~ "Family not found"
      assert page_title(view) =~ "Not Found"
    end
  end
end
