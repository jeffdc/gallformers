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
      {:ok, view, _html} = live(conn, "/subfamily/Cynipinae?tab=within")

      assert has_element?(view, "#children li", ~r/Cynipini\s+tribe\s+8 galls/)
    end

    test "shows genera as children of tribe", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tribe/Cynipini?tab=within")

      assert has_element?(view, "#within h2", "Genera")
      assert has_element?(view, "#children li", ~r/Andricus\s+4 galls/)
      assert has_element?(view, "#children li", "Cynips")
    end

    test "the name filter and the sort apply to the taxa within", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tribe/Cynipini?tab=within")

      view |> element("#intermediate-search-form") |> render_change(%{"query" => "cynips"})
      assert has_element?(view, "#children li", "Cynips")
      refute has_element?(view, "#children li", "Andricus")

      view |> element("#intermediate-search-form") |> render_change(%{"query" => ""})
      view |> element("button[phx-click=sort][phx-value-field=gall_count]") |> render_click()

      assert has_element?(view, "button[phx-value-field=gall_count][aria-pressed=true]")
      assert view |> element("#children li:first-child") |> render() =~ "Andricus"
    end

    test "child URLs use names not IDs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/subfamily/Cynipinae?tab=within")

      assert has_element?(view, ~s{a[href="/tribe/Cynipini"]})
    end

    test "an old numeric URL redirects through the crosswalk", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/tribe/Cynipini"}}} = live(conn, "/tribe/32")
    end

    test "a name of another rank is a 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, "/tribe/Cynipinae") end
    end

    test "an unknown name is a 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, "/subfamily/Nonexistent") end
    end

    test "a rank the taxonomy no longer has is a 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, "/infratribe/Cynipini") end
    end
  end
end
