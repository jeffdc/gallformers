defmodule GallformersWeb.IntermediateLiveTest do
  @moduledoc """
  Tests for the public pages of the ranks between family and genus
  (subfamily, tribe, subtribe), which read `Gallformers.Taxa` and
  `Gallformers.Catalog.count_galls_under/1`.

  Uses the converted seeds (`priv/repo/test_seeds.sql`): Cynipidae >
  Cynipinae (subfamily) > Cynipini (tribe) > Andricus, Cynips, Neuroterus.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  # Reading the seeds, converted, is most of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  describe "IntermediateLive with rank-typed URLs" do
    test "renders subfamily page by name", %{conn: conn} do
      {:ok, view, html} = live(conn, "/subfamily/Cynipinae")

      assert html =~ "Subfamily"
      assert html =~ "Cynipinae"
      assert page_title(view) =~ "Subfamily: Cynipinae"
    end

    test "renders tribe page by name", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tribe/Cynipini")

      assert html =~ "Tribe"
      assert html =~ "Cynipini"
    end

    test "shows breadcrumb with parent family using names", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tribe/Cynipini")

      assert has_element?(view, ~s{a[href="/family/Cynipidae"]})
      assert has_element?(view, ~s{a[href="/subfamily/Cynipinae"]})
      refute has_element?(view, ~s{a[href="/tribe/Cynipini"]})
    end

    test "shows children with their gall counts", %{conn: conn} do
      {:ok, view, html} = live(conn, "/subfamily/Cynipinae")

      assert html =~ "Cynipini"
      assert has_element?(view, "tbody tr", ~r/Cynipini\s+tribe\s+7\s+0/)
    end

    test "shows genera as children of tribe", %{conn: conn} do
      {:ok, view, html} = live(conn, "/tribe/Cynipini")

      assert html =~ "Andricus"
      assert html =~ "Cynips"
      assert has_element?(view, "tbody tr", ~r/Andricus\s+genus\s+4\s+0/)
    end

    test "child URLs use names not IDs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/subfamily/Cynipinae")

      assert has_element?(view, ~s{a[href="/tribe/Cynipini"]})
    end

    test "an old numeric URL redirects through the crosswalk", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/tribe/Cynipini"}}} = live(conn, "/tribe/32")
    end

    test "returns not found when rank does not match", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tribe/Cynipinae")

      assert html =~ "Taxonomy not found"
    end

    test "returns not found for nonexistent name", %{conn: conn} do
      {:ok, view, html} = live(conn, "/subfamily/Nonexistent")

      assert html =~ "Taxonomy not found"
      assert page_title(view) =~ "Not Found"
    end

    test "returns not found for a rank the taxonomy no longer has", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/infratribe/Cynipini")

      assert html =~ "Taxonomy not found"
    end
  end
end
