defmodule GallformersWeb.Admin.DashboardLiveTest do
  @moduledoc """
  The admin dashboard (`/admin`, design system matter bc0d): the Sources to
  review first, then the curators' recent changes (the same `change_entry`
  as the Changes page, with View and Edit); Find, Create and, for a
  superadmin, Site in the rail.

  Not async: admin access reads the site settings (persistent_term), and
  review packages create Sources and load the vocabularies.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.AuditFixtures
  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1]
  import Gallformers.ImportFixtures
  import GallformersWeb.AdminLiveHelpers

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    %{conn: conn}
  end

  setup :audit_test_metadata

  test "the page: Dashboard, with the help links", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "h1", "Dashboard")
    assert has_element?(view, "a[href*='admin-onboarding']", "Getting started")
    assert has_element?(view, "a[href^='https://discord.com']", "Discord")
  end

  describe "Sources to review" do
    test "each Source waiting, linked to its review, with what is left to decide", %{conn: conn} do
      gall =
        batch()
        |> unique_batch_id()
        |> put_in(["source", "title"], "Galls of the oaks")
        |> put_in(["source", "citation"], "Ashmead, W. H. 1897. Galls of the oaks.")

      package(gall: gall) |> with_review() |> deliver!()

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#review-queue a[href^='/admin/review/']", "Galls of the oaks")
      assert has_element?(view, "a[href='/admin/review']", "Open the review")
    end

    test "with nothing waiting, it says so", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#review-queue-section", "Nothing waiting for review.")
    end
  end

  describe "Recent changes" do
    test "the curators' latest changes, each with View and Edit, and a link to them all", %{
      conn: conn
    } do
      gall = gall_fixture(%{name: "Andricus fixturi"})
      oak = plant_fixture(name: "Quercus alba")
      source = source_fixture("Weld", "1959")

      {:ok, host} =
        Gallformers.Catalog.assert_relationship(
          Gallformers.DataCase.test_actor(),
          %{type: "host_of", subject_taxon_id: oak.id, object_gall_id: gall.id},
          confirm(source)
        )

      curator_change("Adam Kranz", "import.apply_batch", 5, [
        {"import_batches", "update", %{id: 1, package_id: package_for(source).id}},
        {"facts", "insert", %{id: host.fact.id, standing: "current"}}
      ])

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#recent-changes li [data-part=summary]", "Adam Kranz")

      assert has_element?(
               view,
               "#recent-changes [data-part=galls] a[href='/gall/#{gall.id}']",
               "View"
             )

      assert has_element?(
               view,
               "#recent-changes [data-part=galls] a[href='/gall/#{gall.id}?edit']",
               "Edit"
             )

      assert has_element?(view, "a[href='/admin/changes']", "All changes")
    end

    test "with no changes yet, it says so", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#recent-changes-section", "No changes yet.")
    end
  end

  describe "the rail" do
    test "Find and Create link the admin's lists and forms", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      for href <- ~w(/galls /admin/sources /admin/taxonomy /admin/host-range) do
        assert has_element?(view, "#find a[href='#{href}']"), "Find: #{href}"
      end

      for href <- ~w(/admin/taxonomy/new /admin/articles/new /admin/keys/new /admin/glossary/new) do
        assert has_element?(view, "#create a[href='#{href}']"), "Create: #{href}"
      end
    end

    test "Site is a superadmin's only", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      refute has_element?(view, "#site")
      refute has_element?(view, "a[href='/admin/jobs']")

      {super_conn, _} = log_in_admin(build_conn(), "Sam Super", ["superadmin"])
      {:ok, view, _html} = live(super_conn, ~p"/admin")

      for href <- ~w(/admin/users /admin/vocabulary /admin/jobs /admin/dashboard) do
        assert has_element?(view, "#site a[href='#{href}']"), "Site: #{href}"
      end
    end

    test "links to no deleted old screen", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      for prefix <- ~w(/admin/gallhost /admin/gall-range /admin/images /admin/image-audit
                       /admin/filter-terms /admin/species-sources /admin/queue) do
        refute has_element?(view, "a[href^='#{prefix}']"), "link to #{prefix}"
      end
    end
  end
end
