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
      {:ok, view, _html} = live(conn, ~p"/source/59")

      assert has_element?(view, "#source-galls-section [data-part=count]", "1")
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

      {:ok, view, _html} = live(conn, ~p"/source/#{source.id}")

      assert has_element?(view, "#source-galls-section [data-part=count]", "1")
      assert has_element?(view, "a[href^='/gall/#{gall.id}']", "Facts-only gall")
    end

    test "a Source with no Galls says so", %{conn: conn} do
      source = source_fixture("Lonely", "2000")

      {:ok, _view, html} = live(conn, ~p"/source/#{source.id}")

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

    test "its taxonomic statements, each with the curator's mark", %{conn: conn} do
      {_admin_conn, _user} = GallformersWeb.AdminLiveHelpers.log_in_admin(conn, "Ada Curator")
      actor = DataCase.test_actor()
      source = source_fixture("Revises things", "1990")
      family = Gallformers.TaxaFixtures.taxon_fixture(rank: :family, name: "Saidae")
      other = Gallformers.TaxaFixtures.taxon_fixture(rank: :family, name: "Othersaidae")
      genus = Gallformers.TaxaFixtures.taxon_fixture(rank: :genus, name: "Saida", parent: family)

      {:ok, %{attribution: moved}} =
        Gallformers.Taxa.assert_placement(
          actor,
          %{taxon_id: genus.id, parent_id: other.id},
          confirm(source)
        )

      {:ok, %{attribution: renamed}} =
        Gallformers.Taxa.assert_name(
          actor,
          %{taxon_id: genus.id, name: "Saidella", rank: :genus},
          confirm(source)
        )

      {:ok, _} = Gallformers.Facts.accept(actor, moved.id)
      {:ok, _} = Gallformers.Facts.decline(actor, renamed.id, "A misspelling")

      {:ok, view, _html} = live(conn, ~p"/source/#{source.id}")

      refute has_element?(view, "#source-facts", "No facts from this Source yet.")
      assert has_element?(view, "#source-facts h3", "Taxonomy changes")

      assert has_element?(
               view,
               "#source-facts [data-category=acts] [data-decision=accepted]",
               "Othersaidae"
             )

      assert has_element?(view, "#source-facts [data-decision=accepted]", "Ada Curator")
      assert has_element?(view, "#source-facts [data-decision=declined]", "Saidella")
      assert has_element?(view, "#source-facts [data-decision=declined]", "A misspelling")
      refute has_element?(view, "#source-facts [data-role=fact-menu]")
    end

    test "a Source that says nothing says so", %{conn: conn} do
      source = source_fixture("Silent", "2000")

      {:ok, view, _html} = live(conn, ~p"/source/#{source.id}")

      assert has_element?(view, "#source-facts", "No facts from this Source yet.")
    end
  end

  describe "the design system's Source page" do
    test "shows its DOI as a link, and Original when it has a link", %{conn: conn} do
      source =
        "Weld"
        |> source_fixture("1959")
        |> Ecto.Changeset.change(doi: "10.1234/fixture.doi", link: "https://example.org/weld")
        |> Gallformers.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/source/#{source.id}")

      assert has_element?(view, ~s{header a[href="https://doi.org/10.1234/fixture.doi"]})
      assert has_element?(view, ~s{a[href="https://example.org/weld"]}, "Original")
    end

    test "a retracted Source says so, linking the retraction notice", %{conn: conn} do
      notice = source_fixture("Retraction notice", "2026")

      source =
        "Retracted fixture"
        |> source_fixture("1990")
        |> Ecto.Changeset.change(retracted_on: ~D[2026-01-02], retracted_by_id: notice.id)
        |> Gallformers.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/source/#{source.id}")

      assert has_element?(view, "header", "Retracted")
      assert has_element?(view, "[role=alert]", "Retracted on 2026-01-02")
      assert has_element?(view, ~s{[role=alert] a[href="/source/#{notice.id}"]})
    end

    test "with no images, there is no empty photo box", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/source/58")

      refute has_element?(view, "#source-images")
      refute html =~ "No images available"
    end
  end

  describe "Not found" do
    test "an ID that isn't a number is a 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, ~p"/source/invalid") end
    end

    test "a missing ID is a 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, ~p"/source/999999999") end
    end
  end
end
