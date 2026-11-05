defmodule GallformersWeb.SourceLiveTest do
  @moduledoc """
  LiveView tests for the Source page, which lists the Galls a Source speaks
  of (`Gallformers.Catalog.list_galls_for_source/1`) and its images.

  Uses the converted seeds (`priv/repo/test_seeds.sql`): Source 59 is cited
  on Gall 300; Source 58 is the Gallformers Source, with notes on Galls 300
  and 301.

  Not async: a test uses the Gallformers Source (see
  `Gallformers.CatalogFixtures`).
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  # Reading the seeds, converted, is part of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1]
  import Gallformers.ImportFixtures, only: [applied_package!: 3, imported_source!: 2]

  alias Gallformers.Catalog
  alias Gallformers.DataCase
  alias Gallformers.Images

  describe "Source page" do
    test "shows the Source's details", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/source/59")

      assert html =~ "Cynipid galls of the seed slope"
      assert html =~ "Weld, L. H."
      assert html =~ "1957"
      assert page_title(view) =~ "Cynipid galls of the seed slope"
    end

    test "an admin gets a link to the Source editor; a visitor does not", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/source/59")
      refute has_element?(view, "a[href='/admin/sources/59']")

      {admin_conn, _user} = GallformersWeb.AdminLiveHelpers.log_in_admin(conn)
      {:ok, view, _html} = live(admin_conn, ~p"/source/59")
      assert has_element?(view, "a[href='/admin/sources/59']")
    end

    test "lists the Galls it cites, linking to their Source entry", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/source/59")

      assert html =~ "Connected Galls (1)"
      assert has_element?(view, "a[href='/gall/300?source=59']", "Andricus seedii (agamic)")
    end

    test "the Gallformers Source lists the Galls with its notes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/source/58")

      assert has_element?(view, "a[href='/gall/300?source=58']")
    end

    test "a Source attributing Facts only lists those Galls", %{conn: conn} do
      source = source_fixture("Facts only", "1990")
      gall = gall_fixture(name: "Facts-only gall")

      {:ok, _} =
        Catalog.assert_alias(
          DataCase.test_actor(),
          %{gall_id: gall.id, name: "facts-only alias"},
          confirm(source)
        )

      {:ok, view, html} = live(conn, ~p"/source/#{source.id}")

      assert html =~ "Connected Galls (1)"
      assert has_element?(view, "a[href^='/gall/#{gall.id}']", "Facts-only gall")
    end

    test "a Source with no Galls says so", %{conn: conn} do
      source = source_fixture("Lonely", "2000")

      {:ok, _view, html} = live(conn, ~p"/source/#{source.id}")

      assert html =~ "Connected Galls (0)"
      assert html =~ "No galls connected to this source."
    end

    test "shows the Source's images", %{conn: conn} do
      source = source_fixture("Pictures", "2000")

      {:ok, _image} =
        Images.create_image(%{
          gall_id: 300,
          source_id: source.id,
          path: "gall/300/300_source_original.jpg",
          creator: "Source Photographer",
          license: "CC-BY"
        })

      {:ok, view, html} = live(conn, ~p"/source/#{source.id}")

      assert has_element?(view, "#source-images img[alt]")
      assert html =~ "Source Photographer"
    end
  end

  describe "when the Source came to Gallformers" do
    setup :audit_test_metadata

    test "says when it was added and last updated", %{conn: conn} do
      source = imported_source!("Added and updated", ~U[2026-10-01 09:00:00Z])
      applied_package!(source, ~U[2026-11-02 12:00:00Z], [])

      {:ok, view, _html} = live(conn, ~p"/source/#{source.id}")

      assert has_element?(
               view,
               "#source-dates",
               "Added to Gallformers October 01, 2026 · updated November 02, 2026"
             )
    end

    test "leaves out an update on the day it was added", %{conn: conn} do
      source = imported_source!("Added once", ~U[2026-10-01 09:00:00Z])
      applied_package!(source, ~U[2026-10-01 17:00:00Z], [])

      {:ok, view, _html} = live(conn, ~p"/source/#{source.id}")

      assert has_element?(view, "#source-dates", "Added to Gallformers October 01, 2026")
      refute has_element?(view, "#source-dates", "updated")
    end

    test "a Source from the old data says so instead of a date", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/source/59")

      assert has_element?(view, "#source-dates", "From the original Gallformers data")
      refute has_element?(view, "#source-dates", "Added to Gallformers")
    end
  end

  describe "What this Source says" do
    test "its Facts, grouped by Gall then category, read-only", %{conn: conn} do
      source = source_fixture("Says things", "1990")
      gall = gall_fixture(name: "Speaking gall")

      {:ok, _} =
        Catalog.assert_alias(
          DataCase.test_actor(),
          %{gall_id: gall.id, name: "the talking gall"},
          confirm(source)
        )

      # An admin sees what a visitor sees: no edits, no review links.
      {admin_conn, _user} = GallformersWeb.AdminLiveHelpers.log_in_admin(conn)
      {:ok, view, _html} = live(admin_conn, ~p"/source/#{source.id}")

      assert has_element?(view, "#source-facts h2", "What this Source says")
      assert has_element?(view, "#source-facts h3", "Speaking gall")
      assert has_element?(view, "#source-facts a[href='/gall/#{gall.id}']")
      assert has_element?(view, "#source-facts [data-category=aliases]", "the talking gall")

      refute has_element?(view, "#source-facts [data-role=fact-menu]")
      refute has_element?(view, "#source-facts a[href^='/admin']")
      refute has_element?(view, "#source-facts .gf-mark-new")
    end

    test "a Source that says nothing says so", %{conn: conn} do
      source = source_fixture("Silent", "2000")

      {:ok, view, _html} = live(conn, ~p"/source/#{source.id}")

      assert has_element?(view, "#source-facts", "No Facts from this Source yet.")
    end
  end

  describe "Not found" do
    test "for an invalid ID", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/source/invalid")
      assert html =~ "Invalid source ID"
    end

    test "for a missing ID", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/source/999999999")

      assert html =~ "Source not found"
      assert page_title(view) =~ "Not Found"
    end
  end
end
