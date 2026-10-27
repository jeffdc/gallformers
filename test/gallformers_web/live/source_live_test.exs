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
          species_id: 300,
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
