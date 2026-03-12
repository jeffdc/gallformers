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
  use GallformersWeb.ConnCase, async: true
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
      assert has_element?(view, "h3 span.text-red-800", "Delete")
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

      assert html =~ "New Taxonomy Entry"
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

      assert html =~ "Editing"
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

    test "type select includes Intermediate option", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/taxonomy/new")
      assert html =~ "Intermediate"
    end

    test "selecting intermediate type shows rank input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      html =
        view
        |> form("#taxonomy-form", taxonomy: %{type: "intermediate"})
        |> render_change()

      assert html =~ "Rank"
      assert html =~ "Select rank"
      assert html =~ "Subfamily"
      assert html =~ "Tribe"
    end

    test "selecting intermediate type shows parent typeahead", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      html =
        view
        |> form("#taxonomy-form", taxonomy: %{type: "intermediate"})
        |> render_change()

      assert html =~ "Search for a parent (family or intermediate)"
    end
  end

  describe "intermediate creation" do
    setup %{conn: conn} do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "IntermediateFormTestFamily",
          type: "family",
          description: "Wasp"
        })

      {:ok, genus1} =
        Taxonomy.create_taxonomy(%{
          name: "IntermediateFormGenus1",
          type: "genus",
          parent_id: family.id
        })

      {:ok, genus2} =
        Taxonomy.create_taxonomy(%{
          name: "IntermediateFormGenus2",
          type: "genus",
          parent_id: family.id
        })

      {:ok, conn: setup_admin_session(conn), family: family, genus1: genus1, genus2: genus2}
    end

    test "shows children picker when parent is selected", %{
      conn: conn,
      family: family,
      genus1: genus1
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      # First select the type to reveal the parent typeahead
      view
      |> form("#taxonomy-form", taxonomy: %{type: "intermediate"})
      |> render_change()

      # Then select a parent via the typeahead
      html =
        view
        |> render_click("select_parent", %{"id" => "#{family.id}"})

      # Should show children of the selected parent
      assert html =~ genus1.name
      assert html =~ "Children to move"
    end

    test "creating intermediate re-parents selected children", %{
      conn: conn,
      family: family,
      genus1: genus1
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      # Step 1: Select type
      view
      |> form("#taxonomy-form", taxonomy: %{type: "intermediate"})
      |> render_change()

      # Step 2: Select parent via typeahead
      view |> render_click("select_parent", %{"id" => "#{family.id}"})

      # Step 3: Toggle child selection
      view |> render_click("toggle_child", %{"id" => "#{genus1.id}"})

      # Step 4: Fill in name and rank, then save
      view
      |> form("#taxonomy-form",
        taxonomy: %{
          type: "intermediate",
          name: "FormTestSubfamily",
          rank: "Subfamily"
        }
      )
      |> render_submit()

      # Should redirect to the new intermediate's edit page
      {path, _flash} = assert_redirect(view)
      assert path =~ ~r"/admin/taxonomy/\d+"

      # Verify the genus was re-parented
      updated_genus = Repo.get!(TaxonomySchema, genus1.id)
      refute updated_genus.parent_id == family.id
    end

    test "saving without children shows error", %{conn: conn, family: family} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      # Select type first
      view
      |> form("#taxonomy-form", taxonomy: %{type: "intermediate"})
      |> render_change()

      # Select parent via typeahead
      view |> render_click("select_parent", %{"id" => "#{family.id}"})

      # Submit without selecting any children
      view
      |> form("#taxonomy-form",
        taxonomy: %{
          type: "intermediate",
          name: "NoChildrenSubfamily",
          rank: "Subfamily"
        }
      )
      |> render_submit()

      # Should show error, not redirect
      assert has_element?(view, "[role=alert]", "At least one child must be selected")
    end
  end

  describe "grouped children in intermediate creation" do
    setup %{conn: conn} do
      # Family with: 2 direct genera + 1 subfamily containing 2 genera
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "GroupedChildFamily",
          type: "family",
          description: "Wasp"
        })

      {:ok, free_genus1} =
        Taxonomy.create_taxonomy(%{
          name: "FreeGenus1",
          type: "genus",
          parent_id: family.id
        })

      {:ok, free_genus2} =
        Taxonomy.create_taxonomy(%{
          name: "FreeGenus2",
          type: "genus",
          parent_id: family.id
        })

      # Create genera that will be assigned to the subfamily
      {:ok, assigned_genus1} =
        Taxonomy.create_taxonomy(%{
          name: "AssignedGenus1",
          type: "genus",
          parent_id: family.id
        })

      {:ok, assigned_genus2} =
        Taxonomy.create_taxonomy(%{
          name: "AssignedGenus2",
          type: "genus",
          parent_id: family.id
        })

      # Create subfamily with these genera as children (re-parents them)
      {:ok, subfamily} =
        Taxonomy.create_intermediate(%{
          "name" => "ExistingSubfamily",
          "type" => "intermediate",
          "rank" => "Subfamily",
          "parent_id" => to_string(family.id),
          "children_ids" => [assigned_genus1.id, assigned_genus2.id]
        })

      {:ok,
       conn: setup_admin_session(conn),
       family: family,
       free_genus1: free_genus1,
       free_genus2: free_genus2,
       subfamily: subfamily,
       assigned_genus1: assigned_genus1,
       assigned_genus2: assigned_genus2}
    end

    test "shows unassigned genera in their own section", %{
      conn: conn,
      family: family,
      free_genus1: free_genus1,
      free_genus2: free_genus2
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      view
      |> form("#taxonomy-form", taxonomy: %{type: "intermediate"})
      |> render_change()

      html = view |> render_click("select_parent", %{"id" => "#{family.id}"})

      # Should show "Unassigned genera" section with the free genera
      assert html =~ "Unassigned genera"
      assert html =~ free_genus1.name
      assert html =~ free_genus2.name
    end

    test "shows genera already under intermediates in grouped section", %{
      conn: conn,
      family: family,
      subfamily: subfamily,
      assigned_genus1: assigned_genus1,
      assigned_genus2: assigned_genus2
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      view
      |> form("#taxonomy-form", taxonomy: %{type: "intermediate"})
      |> render_change()

      html = view |> render_click("select_parent", %{"id" => "#{family.id}"})

      # Should show the intermediate group header (collapsed)
      assert html =~ subfamily.name

      # Expand the group to reveal assigned genera
      html =
        view
        |> render_click("expand_children_group", %{"group" => "under-#{subfamily.id}"})

      assert html =~ assigned_genus1.name
      assert html =~ assigned_genus2.name
    end

    test "select all selects all items across all groups", %{
      conn: conn,
      family: family,
      free_genus1: free_genus1,
      free_genus2: free_genus2,
      subfamily: subfamily,
      assigned_genus1: assigned_genus1,
      assigned_genus2: assigned_genus2
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      view
      |> form("#taxonomy-form", taxonomy: %{type: "intermediate"})
      |> render_change()

      view |> render_click("select_parent", %{"id" => "#{family.id}"})
      view |> render_click("select_all_children", %{})

      # Expand the intermediate group to check assigned genera too
      view
      |> render_click("expand_children_group", %{"group" => "under-#{subfamily.id}"})

      # All genera should be checked (free + assigned + intermediate itself)
      assert has_element?(view, "input[phx-value-id=\"#{free_genus1.id}\"][checked]")
      assert has_element?(view, "input[phx-value-id=\"#{free_genus2.id}\"][checked]")
      assert has_element?(view, "input[phx-value-id=\"#{assigned_genus1.id}\"][checked]")
      assert has_element?(view, "input[phx-value-id=\"#{assigned_genus2.id}\"][checked]")
    end

    test "can toggle assigned genera for reassignment", %{
      conn: conn,
      family: family,
      subfamily: subfamily,
      assigned_genus1: assigned_genus1
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      view
      |> form("#taxonomy-form", taxonomy: %{type: "intermediate"})
      |> render_change()

      view |> render_click("select_parent", %{"id" => "#{family.id}"})

      # Expand the intermediate group to reveal assigned genera
      view
      |> render_click("expand_children_group", %{"group" => "under-#{subfamily.id}"})

      # Toggle an assigned genus
      view |> render_click("toggle_child", %{"id" => "#{assigned_genus1.id}"})

      assert has_element?(view, "input[phx-value-id=\"#{assigned_genus1.id}\"][checked]")
    end

    test "creating intermediate with only unassigned genera works", %{
      conn: conn,
      family: family,
      free_genus1: free_genus1
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      view
      |> form("#taxonomy-form", taxonomy: %{type: "intermediate"})
      |> render_change()

      view |> render_click("select_parent", %{"id" => "#{family.id}"})
      view |> render_click("toggle_child", %{"id" => "#{free_genus1.id}"})

      view
      |> form("#taxonomy-form",
        taxonomy: %{
          type: "intermediate",
          name: "NewTribe",
          rank: "Tribe"
        }
      )
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r"/admin/taxonomy/\d+"

      # Verify the genus was re-parented
      updated = Repo.get!(TaxonomySchema, free_genus1.id)
      refute updated.parent_id == family.id
    end

    test "creating intermediate with reassigned genera moves them", %{
      conn: conn,
      family: family,
      subfamily: subfamily,
      assigned_genus1: assigned_genus1
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      view
      |> form("#taxonomy-form", taxonomy: %{type: "intermediate"})
      |> render_change()

      view |> render_click("select_parent", %{"id" => "#{family.id}"})
      view |> render_click("toggle_child", %{"id" => "#{assigned_genus1.id}"})

      view
      |> form("#taxonomy-form",
        taxonomy: %{
          type: "intermediate",
          name: "NewTribe",
          rank: "Tribe"
        }
      )
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r"/admin/taxonomy/\d+"

      # Verify the genus was moved away from its old intermediate
      updated = Repo.get!(TaxonomySchema, assigned_genus1.id)
      refute updated.parent_id == subfamily.id
    end
  end

  describe "type field locking in edit mode" do
    setup %{conn: conn} do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TypeLockTestFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "TypeLockTestGenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, conn: setup_admin_session(conn), family: family, genus: genus}
    end

    test "type field is disabled in edit mode", %{conn: conn, family: family} do
      {:ok, _view, html} = live(conn, ~p"/admin/taxonomy/#{family.id}")

      # The select for type should have a disabled attribute
      assert html =~ ~r/<select[^>]*name="taxonomy\[type\]"[^>]*disabled/s
    end

    test "type field is enabled in new mode", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/taxonomy/new")

      # The select for type should NOT have disabled
      refute html =~ ~r/<select[^>]*name="taxonomy\[type\]"[^>]*disabled/s
    end

    test "saving in edit mode preserves the original type", %{conn: conn, genus: genus} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{genus.id}")

      # Change the name (type field is disabled so it won't be in params,
      # but the handler should inject it)
      view
      |> form("#taxonomy-form", taxonomy: %{name: "RenamedTypeTestGenus"})
      |> render_submit()

      # Verify the genus still has type "genus"
      updated = Repo.get!(TaxonomySchema, genus.id)
      assert updated.type == "genus"
      assert updated.name == "RenamedTypeTestGenus"
    end
  end

  describe "edit mode subtitle" do
    setup %{conn: conn} do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "BannerTestFamily",
          type: "family",
          description: "Wasp"
        })

      {:ok, conn: setup_admin_session(conn), family: family}
    end

    test "shows type and name in edit mode header", %{conn: conn, family: family} do
      {:ok, _view, html} = live(conn, ~p"/admin/taxonomy/#{family.id}")

      assert html =~ "Editing"
      assert html =~ "family"
      assert html =~ "BannerTestFamily"
    end

    test "does not show type and name in new mode", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/taxonomy/new")

      assert html =~ "New Taxonomy Entry"
      refute html =~ "Editing"
    end
  end

  describe "section parent dropdown excludes self" do
    setup %{conn: conn} do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "SectionSelfTestFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "SectionSelfTestGenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, section} =
        Taxonomy.create_taxonomy(%{
          name: "SectionSelfTestSection",
          type: "section",
          parent_id: genus.id
        })

      {:ok, conn: setup_admin_session(conn), family: family, genus: genus, section: section}
    end

    test "section edit form does not show self in parent dropdown", %{
      conn: conn,
      section: section,
      genus: genus
    } do
      {:ok, _view, html} = live(conn, ~p"/admin/taxonomy/#{section.id}")

      # The parent dropdown should contain the genus (the actual parent)
      assert html =~ genus.name

      # But should NOT contain the section itself as a parent option
      # The section's own id should not appear as an option value
      refute html =~ ~r/<option[^>]*value="#{section.id}"[^>]*>.*#{section.name}/s
    end
  end
end
