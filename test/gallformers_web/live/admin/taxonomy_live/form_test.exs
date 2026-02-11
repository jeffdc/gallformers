defmodule GallformersWeb.Admin.TaxonomyLive.FormTest do
  @moduledoc """
  LiveView tests for the TaxonomyLive.Form admin page.

  Tests the cascade delete functionality including:
  - Delete button shows impact modal
  - Impact modal displays correct counts
  - Show details expands to list genera/sections
  - Wrong name shows error, nothing deleted
  - Correct name triggers delete and redirect
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Repo
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy
  alias Gallformers.Taxonomy.Taxonomy, as: TaxonomySchema

  # Helper to set up admin session
  defp setup_admin_session(conn) do
    user = %Auth0User{
      id: "test-admin-id",
      email: "admin@test.com",
      name: "Test Admin",
      nickname: nil,
      picture: nil,
      roles: ["admin"]
    }

    conn
    |> init_test_session(%{})
    |> put_session(:current_user, user)
    |> put_session(:db_display_name, "Test User")
  end

  describe "cascade delete modal" do
    setup %{conn: conn} do
      # Create a family with genera and species for cascade delete testing
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "CascadeTestFamily",
          type: "family",
          description: "Wasp"
        })

      {:ok, genus1} =
        Taxonomy.create_taxonomy(%{
          name: "CascadeTestGenus1",
          type: "genus",
          parent_id: family.id
        })

      {:ok, genus2} =
        Taxonomy.create_taxonomy(%{
          name: "CascadeTestGenus2",
          type: "genus",
          parent_id: family.id
        })

      {:ok, section} =
        Taxonomy.create_taxonomy(%{
          name: "CascadeTestSection",
          type: "section",
          parent_id: genus1.id
        })

      # Create species under genus1 and section
      {:ok, species1} =
        Repo.insert(%Species{
          name: "CascadeTestGenus1 sp1",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species1.id, genus1.id)

      {:ok, species2} =
        Repo.insert(%Species{
          name: "CascadeTestGenus1 sp2",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species2.id, section.id)

      {:ok,
       conn: setup_admin_session(conn),
       family: family,
       genus1: genus1,
       genus2: genus2,
       section: section,
       species1: species1,
       species2: species2}
    end

    test "clicking delete shows impact modal", %{conn: conn, family: family} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{family.id}")

      # Click delete button
      view |> element("button", "Delete") |> render_click()

      # Modal should appear with warning
      assert has_element?(view, "#cascade-delete-modal")
      assert has_element?(view, "h3", "Delete CascadeTestFamily?")
    end

    test "impact modal displays correct counts", %{conn: conn, family: family} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{family.id}")

      # Click delete button
      view |> element("button", "Delete") |> render_click()

      html = render(view)

      # Should show genera count (3: genus1, genus2, auto-created Unknown)
      assert html =~ "3"
      assert html =~ "genera"

      # Should show section count
      assert html =~ "1"
      assert html =~ "section"

      # Should show species count
      assert html =~ "2"
      assert html =~ "species"

      # Should mention related data
      assert html =~ "images, aliases, sources, host associations"
    end

    test "show details expands to list genera and sections", %{conn: conn, family: family} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{family.id}")

      view |> element("button", "Delete") |> render_click()

      html = render(view)

      # Should list genera by name in details section
      assert html =~ "CascadeTestGenus1"
      assert html =~ "CascadeTestGenus2"

      # Should list sections by name
      assert html =~ "CascadeTestSection"
    end

    test "wrong name shows error flash", %{conn: conn, family: family} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{family.id}")

      # Open modal
      view |> element("button", "Delete") |> render_click()

      # Submit with wrong name using the specific delete confirmation form
      view
      |> form("form[phx-submit=confirm_cascade_delete]", %{confirmation: "WrongName"})
      |> render_submit()

      # Should show error flash
      assert has_element?(view, "[role=alert]", "Name does not match")

      # Family should still exist
      assert Repo.get(TaxonomySchema, family.id)
    end

    test "correct name triggers delete and redirect", %{
      conn: conn,
      family: family,
      genus1: genus1,
      genus2: genus2,
      section: section,
      species1: species1,
      species2: species2
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{family.id}")

      # Open modal
      view |> element("button", "Delete") |> render_click()

      # Type correct name in confirmation
      render_click(view, "update_delete_confirmation", %{"value" => "CascadeTestFamily"})

      # Submit using the specific delete confirmation form
      view
      |> form("form[phx-submit=confirm_cascade_delete]", %{confirmation: "CascadeTestFamily"})
      |> render_submit()

      # Should redirect to taxonomy list
      assert_redirect(view, "/admin/taxonomy")

      # Verify all data is deleted
      refute Repo.get(TaxonomySchema, family.id)
      refute Repo.get(TaxonomySchema, genus1.id)
      refute Repo.get(TaxonomySchema, genus2.id)
      refute Repo.get(TaxonomySchema, section.id)
      refute Repo.get(Species, species1.id)
      refute Repo.get(Species, species2.id)
    end

    test "cancel closes modal without deleting", %{conn: conn, family: family} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{family.id}")

      # Open modal
      view |> element("button", "Delete") |> render_click()
      assert has_element?(view, "#cascade-delete-modal")

      # Click the Cancel text button (not the X close button)
      view |> element("button[phx-click=cancel_cascade_delete]", "Cancel") |> render_click()

      # Modal should be hidden
      refute has_element?(view, "#cascade-delete-modal")

      # Family should still exist
      assert Repo.get(TaxonomySchema, family.id)
    end
  end

  describe "cascade delete for genus" do
    setup %{conn: conn} do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "GenusDeleteTestFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "GenusDeleteTestGenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, section} =
        Taxonomy.create_taxonomy(%{
          name: "GenusDeleteTestSection",
          type: "section",
          parent_id: genus.id
        })

      {:ok, species} =
        Repo.insert(%Species{
          name: "GenusDeleteTestGenus sp1",
          taxoncode: "plant",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, genus.id)

      {:ok,
       conn: setup_admin_session(conn),
       family: family,
       genus: genus,
       section: section,
       species: species}
    end

    test "genus delete shows sections and species counts", %{conn: conn, genus: genus} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{genus.id}")

      view |> element("button", "Delete") |> render_click()

      html = render(view)

      # Should show section count
      assert html =~ "1"
      assert html =~ "section"

      # Should show species count
      assert html =~ "1"
      assert html =~ "species"

      # genera_count should be 0 (not displayed in impact summary)
      # We verify this by checking the impact data shows no genera count item
      refute has_element?(view, "#cascade-delete-modal li", "genera")
    end

    test "genus delete preserves parent family", %{
      conn: conn,
      family: family,
      genus: genus,
      section: section,
      species: species
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{genus.id}")

      view |> element("button", "Delete") |> render_click()

      render_click(view, "update_delete_confirmation", %{"value" => "GenusDeleteTestGenus"})

      view
      |> form("form[phx-submit=confirm_cascade_delete]", %{confirmation: "GenusDeleteTestGenus"})
      |> render_submit()

      assert_redirect(view, "/admin/taxonomy")

      # Genus, section, species deleted
      refute Repo.get(TaxonomySchema, genus.id)
      refute Repo.get(TaxonomySchema, section.id)
      refute Repo.get(Species, species.id)

      # Family preserved
      assert Repo.get(TaxonomySchema, family.id)
    end
  end

  describe "section delete (no cascade)" do
    setup %{conn: conn} do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "SectionDeleteTestFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "SectionDeleteTestGenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, section} =
        Taxonomy.create_taxonomy(%{
          name: "SectionDeleteTestSection",
          type: "section",
          parent_id: genus.id
        })

      {:ok, conn: setup_admin_session(conn), family: family, genus: genus, section: section}
    end

    test "section delete shows no cascade impact", %{conn: conn, section: section} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{section.id}")

      view |> element("button", "Delete") |> render_click()

      html = render(view)

      # Should show "no dependent data" message
      assert html =~ "no dependent data"
      assert html =~ "safely deleted"

      # Should NOT show "This will delete:"
      refute html =~ "This will delete:"
    end

    test "section delete only deletes section", %{
      conn: conn,
      family: family,
      genus: genus,
      section: section
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{section.id}")

      view |> element("button", "Delete") |> render_click()

      render_click(view, "update_delete_confirmation", %{"value" => "SectionDeleteTestSection"})

      view
      |> form("form[phx-submit=confirm_cascade_delete]", %{
        confirmation: "SectionDeleteTestSection"
      })
      |> render_submit()

      assert_redirect(view, "/admin/taxonomy")

      # Section deleted
      refute Repo.get(TaxonomySchema, section.id)

      # Family and genus preserved
      assert Repo.get(TaxonomySchema, family.id)
      assert Repo.get(TaxonomySchema, genus.id)
    end
  end

  describe "basic form functionality" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "renders new taxonomy form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/taxonomy/new")

      assert html =~ "Create New Taxonomy Entry"
      assert html =~ "Name"
      assert html =~ "Type"
    end

    test "renders edit taxonomy form", %{conn: conn} do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "EditTestFamily",
          type: "family",
          description: "Wasp"
        })

      {:ok, _view, html} = live(conn, ~p"/admin/taxonomy/#{family.id}")

      assert html =~ "Edit Taxonomy Entry"
      assert html =~ "EditTestFamily"
    end

    test "delete button only shows in edit mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")
      refute has_element?(view, "button", "Delete")

      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "DeleteButtonTestFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{family.id}")
      assert has_element?(view, "button", "Delete")
    end
  end
end
