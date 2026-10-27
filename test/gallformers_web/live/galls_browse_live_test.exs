defmodule GallformersWeb.GallsBrowseLiveTest do
  @moduledoc """
  LiveView tests for the public Galls browse page at /galls, which reads
  `Gallformers.Catalog.gall_tree/0` and `undescribed_gall_tree/0`.

  Uses the converted seeds (`priv/repo/test_seeds.sql`): Cynipidae (old
  taxonomy 30) holds Andricus, Cynips and Neuroterus with their Galls; Gall
  304 is undescribed (its Inducer is the genus Andricus).
  """
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  # Reading the seeds, converted, is most of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  alias Gallformers.Taxa

  defp family_key(old_id), do: "f-#{Taxa.get_by_legacy_id(:taxonomy, old_id).id}"

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
        |> element(~s{button[phx-click="toggle_node"][phx-value-key="#{family_key(30)}"]})
        |> render_click()

      assert html =~ "Andricus"
      assert html =~ "Neuroterus"
    end

    test "lists each Gall of a generation pair under its Inducer's genus", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/galls")

      html =
        view
        |> element(~s{button[phx-click="expand_all"]})
        |> render_click()

      assert html =~ "Andricus seedii (agamic)"
      assert html =~ "Andricus seedii (sexgen)"
      assert has_element?(view, ~s{a[href="/gall/300"]})
      assert has_element?(view, ~s{a[href="/gall/301"]})
      refute html =~ "Andricus quercuscalifornicus"
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

      view
      |> element(~s{button[phx-click="toggle_undescribed"]})
      |> render_click()

      assert has_element?(view, "[data-active-view=undescribed]")

      html =
        view
        |> element(~s{button[phx-click="expand_all"]})
        |> render_click()

      # Gall 304's Inducer is the genus Andricus; 300's is a species
      assert html =~ "Andricus n-densiflorus-seed-gall"
      refute html =~ "Andricus seedii (agamic)"
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
