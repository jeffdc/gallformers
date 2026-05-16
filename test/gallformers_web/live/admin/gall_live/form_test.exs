defmodule GallformersWeb.Admin.GallLive.FormTest do
  @moduledoc """
  LiveView tests for the GallLive.Form admin page.

  Tests the gall admin form functionality including:
  - Mount/render with typeahead search
  - Deep linking to existing galls
  - Create and edit workflows
  - Alias, host, and filter management
  - Rename modal
  - Dirty state tracking
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Galls
  alias Gallformers.Plants

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

  # Helper to find any gall for testing - fails explicitly if no data
  defp require_gall do
    case Galls.list_galls() do
      [gall | _] -> gall
      [] -> flunk("No gall found in test database - ensure test fixtures exist")
    end
  end

  # Helper to find any host for testing - fails explicitly if no data
  defp require_host do
    case Plants.list_hosts() do
      [host | _] -> host
      [] -> flunk("No host found in test database - ensure test fixtures exist")
    end
  end

  describe "Mount and render - search mode" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "renders gall admin page with typeahead", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/galls/new")

      assert html =~ "Gall"
      assert html =~ "Name (binomial)"
      assert html =~ "Search existing galls or type new name"
    end

    test "shows intro text", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/galls/new")

      assert html =~ "Search for an existing gall to edit, or type a new name to create one"
    end

    test "form fields are disabled in search mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/galls/new")

      # Form fields should be disabled until a gall is selected
      assert has_element?(view, "fieldset[disabled]")
      # Placeholder message shown
      assert has_element?(view, "p", "Select an existing gall or create a new one")
    end
  end

  describe "Mount and render - deep link to existing gall" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "renders edit form with gall data", %{conn: conn} do
      gall = require_gall()
      {:ok, _view, html} = live(conn, ~p"/admin/galls/#{gall.id}")

      assert html =~ "Editing"
      assert html =~ gall.name
    end

    test "shows correct page title for existing gall", %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      assert page_title(view) =~ gall.name
    end

    test "shows rename button in edit mode", %{conn: conn} do
      gall = require_gall()
      {:ok, _view, html} = live(conn, ~p"/admin/galls/#{gall.id}")

      assert html =~ "Rename"
    end

    test "shows quick links in edit mode", %{conn: conn} do
      gall = require_gall()
      {:ok, _view, html} = live(conn, ~p"/admin/galls/#{gall.id}")

      assert html =~ "Manage Images"
      assert html =~ "Gall-Host Mappings"
      assert html =~ "Species-Source Mappings"
    end

    test "shows view public page link in edit mode", %{conn: conn} do
      gall = require_gall()
      {:ok, view, html} = live(conn, ~p"/admin/galls/#{gall.id}")

      assert html =~ "View public page"
      assert has_element?(view, "a[href='/gall/#{gall.id}']")
    end

    test "shows filter fields in edit mode", %{conn: conn} do
      gall = require_gall()
      {:ok, _view, html} = live(conn, ~p"/admin/galls/#{gall.id}")

      assert html =~ "Detachable"
      assert html =~ "Walls"
      assert html =~ "Cells"
      assert html =~ "Color"
      assert html =~ "Shape"
    end

    test "redirects with error flash for invalid gall ID format", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/galls", flash: flash}}} =
               live(conn, ~p"/admin/galls/invalid")

      assert flash["error"] =~ "Invalid gall ID"
    end

    test "redirects with error flash for non-existent gall ID", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/galls", flash: flash}}} =
               live(conn, ~p"/admin/galls/999999999")

      assert flash["error"] =~ "not found"
    end
  end

  describe "Gall search - search_gall event" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "search_gall with short query returns no results", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/galls/new")

      html = render_click(view, "search_gall", %{"value" => "q"})

      # Should not show results dropdown
      refute html =~ "data-typeahead-option"
    end

    test "search_gall with valid query returns results", %{conn: conn} do
      gall = require_gall()
      # Use first 3 chars of gall name for search
      query = String.slice(gall.name, 0..2)

      {:ok, view, _html} = live(conn, ~p"/admin/galls/new")

      html = render_click(view, "search_gall", %{"value" => query})

      # Should show results or create option
      assert html =~ "data-typeahead-results" or html =~ gall.name
    end
  end

  describe "Select existing gall - select_gall event" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "selecting a gall loads it for editing", %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/new")

      html = render_click(view, "select_gall", %{"id" => Integer.to_string(gall.id)})

      assert html =~ "Editing"
      assert html =~ gall.name
    end
  end

  describe "Clear gall - clear_gall event" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "clearing gall redirects to list", %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      # Should redirect to gall list
      assert {:error, {:live_redirect, %{to: "/admin/galls"}}} =
               render_click(view, "clear_gall", %{})
    end

    test "clearing dirty form shows discard-confirm modal instead of redirecting",
         %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      # Dirty the form by adding a pending alias (issue #547 regression).
      render_hook(view, "update_new_alias_name", %{"value" => "Dirtying alias"})
      render_click(view, "add_alias", %{})

      # Clearing must NOT redirect; it must show the discard-confirm modal.
      html = render_click(view, "clear_gall", %{})

      assert html =~ "Discard"
    end
  end

  describe "Alias management" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "typing in alias name input updates new_alias_name", %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      html = render_hook(view, "update_new_alias_name", %{"value" => "Test Alias"})

      assert html =~ ~s(value="Test Alias")
    end

    test "selecting scientific from type select preserves typed name", %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      render_hook(view, "update_new_alias_name", %{"value" => "Foobar synonym"})

      html = render_change(view, "update_new_alias_type", %{"value" => "scientific"})

      assert html =~ ~s(value="Foobar synonym")
      assert html =~ ~r/<option[^>]*value="scientific"[^>]*selected/
    end

    test "add_alias with empty name shows error", %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      html = render_click(view, "add_alias", %{})

      assert html =~ "cannot be empty"
    end
  end

  describe "Host search and management" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "search_hosts handles value parameter correctly", %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      html = render_click(view, "search_hosts", %{"value" => "quercus"})

      assert html =~ "Editing" or html =~ gall.name
    end

    test "add_host adds host to the list", %{conn: conn} do
      gall = require_gall()
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      # First search for the host to populate host_search_results
      query = String.slice(host.name, 0..2)
      render_click(view, "search_hosts", %{"value" => query})

      # Now add the host
      html = render_click(view, "add_host", %{"id" => Integer.to_string(host.id)})

      # Host should be added to pending list, or already associated, or not found in results
      assert html =~ host.name or html =~ "already" or html =~ "not found"
    end
  end

  describe "Filter management" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "filter_search handles value parameter correctly", %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      html = render_click(view, "filter_search", %{"type" => "colors", "value" => "red"})

      assert html =~ "Editing" or html =~ gall.name
    end

    test "filter_search works for various filter types", %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      filter_types = ~w(walls cells alignments colors shapes seasons forms plant_parts textures)

      for filter_type <- filter_types do
        html = render_click(view, "filter_search", %{"type" => filter_type, "value" => "test"})
        assert html =~ gall.name, "Failed for filter type: #{filter_type}"
      end
    end

    test "filter dropdowns render data-search-type for typeahead hook", %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      # The Typeahead hook needs data-search-type on the wrapper div to include
      # the filter type in search events. Without it, filter_search receives no
      # type param and crashes the LiveView (regression from phx-keyup removal).
      for id <- ~w(colors shapes textures alignments walls cells plant_parts forms seasons) do
        assert has_element?(view, "##{id}[data-search-type]"),
               "#{id} dropdown missing data-search-type attribute"
      end
    end
  end

  describe "Detachable - update_detachable event" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "update_detachable marks form as dirty", %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      # Initially form should not be dirty (save button disabled)
      assert has_element?(view, "button[type='submit'][disabled]")

      # Change detachable value
      render_click(view, "update_detachable", %{"value" => "2"})

      # Form should now be dirty (save button enabled)
      refute has_element?(view, "button[type='submit'][disabled]")
    end
  end

  describe "Undescribed toggle" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "toggle_undescribed marks form as dirty", %{conn: conn} do
      gall = require_gall()

      # The undescribed checkbox is locked when the gall has no sources or has a
      # placeholder genus. Add a genus and source so the checkbox is unlocked.
      {:ok, genus} =
        Gallformers.Repo.insert(%Gallformers.Taxonomy.Taxonomy{
          name: "Andricus",
          description: "",
          type: "genus",
          is_placeholder: false
        })

      Gallformers.Repo.insert_all("species_taxonomy", [
        [species_id: gall.id, taxonomy_id: genus.id]
      ])

      {:ok, source} =
        Gallformers.Sources.create_source(%{
          title: "Test Source",
          author: "Test Author",
          pubyear: "2026",
          link: "https://example.com",
          citation: "Test citation",
          license: "CC0"
        })

      Gallformers.Sources.create_species_source(%{
        species_id: gall.id,
        source_id: source.id
      })

      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      # Initially form should not be dirty (save button disabled)
      assert has_element?(view, "button[type='submit'][disabled]")

      # Toggle undescribed
      render_click(view, "toggle_undescribed", %{})

      # Form should now be dirty (save button enabled)
      refute has_element?(view, "button[type='submit'][disabled]")
    end
  end

  describe "Rename/Reclassify modal" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "open_reclassify_modal shows the modal", %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      html = view |> element("button", "Rename/Reclassify") |> render_click()

      assert html =~ "Rename and/or Reclassify Gall"
      assert html =~ "Specific epithet"
      assert html =~ "Add scientific synonym alias"
    end

    test "close_reclassify_modal hides the modal", %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      view |> element("button", "Rename/Reclassify") |> render_click()

      html =
        view
        |> with_target("#reclassify")
        |> render_click("close_reclassify_modal", %{})

      refute html =~ "Rename and/or Reclassify Gall"
    end

    test "do_reclassify without genus selected shows error", %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      view |> element("button", "Rename/Reclassify") |> render_click()
      # Clear genus selection to test guard
      view |> with_target("#reclassify") |> render_click("reclassify_clear_genus", %{})
      view |> with_target("#reclassify") |> render_click("do_reclassify", %{})
      html = render(view)

      assert html =~ "select a genus"
    end

    test "happy path: reclassify gall to different genus", %{conn: conn} do
      # Set up taxonomy: Family "Cynipidae" with two genera
      {:ok, family} =
        Gallformers.Repo.insert(%Gallformers.Taxonomy.Taxonomy{
          name: "Cynipidae",
          description: "Gall Wasps",
          type: "family",
          is_placeholder: false
        })

      {:ok, source_genus} =
        Gallformers.Repo.insert(%Gallformers.Taxonomy.Taxonomy{
          name: "Andricus",
          description: "",
          type: "genus",
          parent_id: family.id,
          is_placeholder: false
        })

      {:ok, target_genus} =
        Gallformers.Repo.insert(%Gallformers.Taxonomy.Taxonomy{
          name: "Callirhytis",
          description: "",
          type: "genus",
          parent_id: family.id,
          is_placeholder: false
        })

      # Link gall species 100 ("Andricus quercuscalifornicus") to source genus
      gall_id = 100

      Gallformers.Repo.insert_all("species_taxonomy", [
        [species_id: gall_id, taxonomy_id: source_genus.id]
      ])

      # Link gall species 102 to target genus (so it appears in taxoncode-filtered search)
      Gallformers.Repo.insert_all("species_taxonomy", [
        [species_id: 102, taxonomy_id: target_genus.id]
      ])

      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall_id}")

      # Open the reclassify modal
      view |> element("button", "Rename/Reclassify") |> render_click()

      # Search and select the target family
      view
      |> with_target("#reclassify")
      |> render_click("reclassify_search_family", %{"value" => "Cynip"})

      view
      |> with_target("#reclassify")
      |> render_click("reclassify_select_family", %{"id" => Integer.to_string(family.id)})

      # Search and select the target genus
      view
      |> with_target("#reclassify")
      |> render_click("reclassify_search_genus", %{"value" => "Call"})

      view
      |> with_target("#reclassify")
      |> render_click("reclassify_select_genus", %{"id" => Integer.to_string(target_genus.id)})

      # Submit reclassification
      view
      |> with_target("#reclassify")
      |> render_click("do_reclassify", %{})

      html = render(view)

      # Verify: species renamed and success flash shown
      assert html =~ "Callirhytis quercuscalifornicus"
      assert html =~ "updated successfully"
      # The old name should appear as a scientific synonym alias
      assert html =~ "Andricus quercuscalifornicus"
    end

    test "reclassify to new genus under existing family", %{conn: conn} do
      {:ok, family} =
        Gallformers.Repo.insert(%Gallformers.Taxonomy.Taxonomy{
          name: "Cynipidae",
          description: "Gall Wasps",
          type: "family",
          is_placeholder: false
        })

      {:ok, source_genus} =
        Gallformers.Repo.insert(%Gallformers.Taxonomy.Taxonomy{
          name: "Andricus",
          description: "",
          type: "genus",
          parent_id: family.id,
          is_placeholder: false
        })

      gall_id = 100

      Gallformers.Repo.insert_all("species_taxonomy", [
        [species_id: gall_id, taxonomy_id: source_genus.id]
      ])

      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall_id}")

      # Open the reclassify modal
      view |> element("button", "Rename/Reclassify") |> render_click()

      # Select family
      view
      |> with_target("#reclassify")
      |> render_click("reclassify_search_family", %{"value" => "Cynip"})

      view
      |> with_target("#reclassify")
      |> render_click("reclassify_select_family", %{"id" => Integer.to_string(family.id)})

      # Create a brand-new genus
      view
      |> with_target("#reclassify")
      |> render_click("reclassify_create_genus", %{"name" => "Newcynipgenus"})

      # Submit reclassification
      view
      |> with_target("#reclassify")
      |> render_click("do_reclassify", %{})

      html = render(view)

      assert html =~ "Newcynipgenus quercuscalifornicus"
      assert html =~ "updated successfully"

      # Verify genus was actually created in the DB
      assert Gallformers.Taxonomy.get_taxonomy_by_name("Newcynipgenus", "genus") != nil
    end
  end

  describe "Cancel and discard" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "request_cancel with clean form redirects to list", %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      # Form is clean, so cancel should redirect to list
      assert {:error, {:live_redirect, %{to: "/admin/galls"}}} =
               render_click(view, "request_cancel", %{})
    end

    test "request_cancel with dirty form shows confirm modal", %{conn: conn} do
      gall = require_gall()
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      # Make form dirty
      render_click(view, "update_detachable", %{"value" => "2"})

      # Request cancel - should show confirm modal
      html = render_click(view, "request_cancel", %{})

      assert html =~ "Discard" or html =~ "unsaved"
    end
  end

  describe "Access control" do
    test "page requires admin session", %{conn: _conn} do
      conn_without_admin = build_conn()
      conn_result = get(conn_without_admin, ~p"/admin/galls/new")

      assert redirected_to(conn_result) =~ "/" or redirected_to(conn_result) =~ "/auth"
    end
  end

  describe "Datacomplete lock on new gall" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "datacomplete checkbox is disabled when creating a new gall (no sources possible yet)",
         %{conn: conn} do
      # Use Cynipidae (30) / Andricus (33) from test seeds — non-placeholder genus
      # so we exercise the regular init_new_gall_form path.
      {:ok, view, _html} = live(conn, ~p"/admin/galls/new")

      render_click(view, "create_gall", %{"name" => "Andricus testius"})

      assert has_element?(
               view,
               "input[name='species[datacomplete]'][disabled]"
             ),
             "datacomplete checkbox must be disabled for a new gall " <>
               "(no sources can exist until the gall is saved)"
    end

    # credo:disable-for-next-line Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData
    test "saving a new gall with datacomplete=true does not persist datacomplete=true",
         %{conn: conn} do
      # Data is created via the `create_gall` LiveView event handler — this test
      # specifically exercises that path, so pre-creating via Repo.insert! would
      # defeat its purpose.
      {:ok, view, _html} = live(conn, ~p"/admin/galls/new")

      render_click(view, "create_gall", %{"name" => "Andricus regressionius"})

      # Simulate the bad request: client somehow submits datacomplete=true
      # (e.g. crafted POST, stale form state). Server-side enforcement must
      # force-clear it because no sources can exist on an unsaved gall.
      render_submit(view, "save", %{"species" => %{"datacomplete" => "true"}})

      saved =
        Gallformers.Repo.one(
          from s in "species",
            where: s.name == "Andricus regressionius",
            select: %{id: s.id, datacomplete: s.datacomplete}
        )

      assert saved, "species should have been created"

      refute saved.datacomplete,
             "newly-created gall must not be datacomplete (it has zero sources)"
    end
  end
end
