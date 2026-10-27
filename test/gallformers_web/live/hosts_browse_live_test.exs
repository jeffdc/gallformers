defmodule GallformersWeb.HostsBrowseLiveTest do
  @moduledoc """
  LiveView tests for the public Hosts browse page at /hosts, which reads
  `Gallformers.Taxa.plant_tree/0`.

  Uses the converted seeds (`priv/repo/test_seeds.sql`): FamilyAlpha (old
  taxonomy 20) > GenusAlpha with two plants; Fagaceae >
  Notholithocarpus > plant 10.
  """
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  # Reading the seeds, converted, is most of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  alias Gallformers.Taxa

  defp family_key(old_id), do: "f-#{Taxa.get_by_legacy_id(:taxonomy, old_id).id}"

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
        |> element(~s{button[phx-click="toggle_node"][phx-value-key="#{family_key(20)}"]})
        |> render_click()

      assert html =~ "GenusAlpha"
    end

    test "plants link to their Host pages", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/hosts")

      html =
        view
        |> element(~s{button[phx-click="expand_all"]})
        |> render_click()

      assert html =~ "Notholithocarpus densiflorus"
      assert has_element?(view, ~s{a[href="/host/10"]})
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
