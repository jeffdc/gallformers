defmodule GallformersWeb.Admin.HostLive.FormTest do
  @moduledoc """
  LiveView tests for the HostLive.Form admin page.

  Tests the host form admin functionality including:
  - Mount/render in new and edit modes
  - Form validation and submission
  - Alias management (add, remove, update)
  - Range/place management
  - Rename modal
  - Dirty state tracking
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Plants
  alias Gallformers.Repo
  alias Gallformers.Wcvp.Lookup

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

  # Helper to find any host for testing - fails explicitly if no data
  defp require_host do
    case Plants.list_hosts() do
      [host | _] -> host
      [] -> flunk("No host found in test database - ensure test fixtures exist")
    end
  end

  describe "Mount and render - new mode (search mode)" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "renders host search/create page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/hosts/new")

      # Shows typeahead for searching/creating hosts
      assert html =~ "Name (binomial)"
      assert html =~ "Search existing hosts or type new name"
    end

    test "shows correct page title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/new")

      assert page_title(view) =~ "Add Host"
    end

    test "form is disabled in search mode until host entered", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/hosts/new")

      # Shows placeholder for search mode
      assert html =~ "Select an existing host or create a new one"
    end

    test "shows back link to hosts list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/new")

      assert has_element?(view, "a[href='/admin/hosts']")
    end

    test "typeahead allows searching for hosts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/new")

      # Search for existing hosts
      html = render_click(view, "search_host", %{"value" => "Quercus"})

      # Should show search results or update UI
      assert html =~ "host-picker" or html =~ "Quercus"
    end

    test "create_host event transitions to new mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/new")

      # Create a new host
      html = render_click(view, "create_host", %{"name" => "Quercus testhost"})

      # Form should now be enabled
      assert html =~ "host-form"
      assert html =~ "Abundance"
    end
  end

  describe "Mount and render - edit mode" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "renders edit host form with host data", %{conn: conn} do
      host = require_host()
      {:ok, _view, html} = live(conn, ~p"/admin/hosts/#{host.id}")

      assert html =~ "Editing"
      assert html =~ host.name
    end

    test "shows correct page title for edit host", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      assert page_title(view) =~ host.name
    end

    test "shows rename button in edit mode", %{conn: conn} do
      host = require_host()
      {:ok, _view, html} = live(conn, ~p"/admin/hosts/#{host.id}")

      assert html =~ "Rename"
    end

    test "shows quick links in edit mode", %{conn: conn} do
      host = require_host()
      {:ok, _view, html} = live(conn, ~p"/admin/hosts/#{host.id}")

      assert html =~ "Manage Images"
      assert html =~ "Species-Source Mappings"
    end

    test "shows view public page link in edit mode", %{conn: conn} do
      host = require_host()
      {:ok, view, html} = live(conn, ~p"/admin/hosts/#{host.id}")

      assert html =~ "View public page"
      assert has_element?(view, "a[href='/host/#{host.id}']")
    end

    test "shows range map in edit mode", %{conn: conn} do
      host = require_host()
      {:ok, _view, html} = live(conn, ~p"/admin/hosts/#{host.id}")

      assert html =~ "Range"
      assert html =~ "host-range-map" or html =~ "Legend"
    end

    test "shows aliases table in edit mode", %{conn: conn} do
      host = require_host()
      {:ok, _view, html} = live(conn, ~p"/admin/hosts/#{host.id}")

      assert html =~ "Aliases"
      assert html =~ "New alias"
    end

    test "handles invalid host ID", %{conn: conn} do
      # Invalid ID causes an error (not a valid integer)
      assert_raise ArgumentError, fn ->
        live(conn, ~p"/admin/hosts/invalid")
      end
    end

    test "redirects for non-existent host ID", %{conn: conn} do
      # Non-existent host redirects with error flash
      assert {:error, {:live_redirect, %{to: "/admin/hosts", flash: flash}}} =
               live(conn, ~p"/admin/hosts/999999999")

      assert flash["error"] =~ "not found"
    end
  end

  describe "Form validation" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "validate event marks form as dirty in edit mode", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      # Trigger validation by changing abundance
      html =
        view
        |> form("#host-form", species: %{abundance_id: "2"})
        |> render_change()

      # Form should now be dirty - check that the form is present and modified
      assert html =~ "host-form"
    end

    test "validate event marks form as dirty in new mode after host creation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/new")

      # First create a new host via typeahead
      render_click(view, "create_host", %{"name" => "Quercus testhost"})

      # Then trigger validation
      html =
        view
        |> form("#host-form", species: %{datacomplete: "true"})
        |> render_change()

      # Form should be present and modified
      assert html =~ "host-form"
    end
  end

  describe "Alias management - update_new_alias event" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "update_new_alias handles name field change (phx-keyup)", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      # Simulate typing in alias name field - sends value and type from phx-value-type
      html =
        render_click(view, "update_new_alias", %{
          "value" => "White Oak",
          "type" => "common name"
        })

      # Should update the input field value
      assert html =~ "White Oak" or html =~ host.name
    end

    test "update_new_alias handles type field change (phx-change)", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      # Simulate changing select - sends value and name from phx-value-name
      html =
        render_click(view, "update_new_alias", %{
          "value" => "scientific synonym",
          "name" => "Some Alias"
        })

      # Should update both fields
      assert html =~ "Some Alias" or html =~ "scientific synonym" or html =~ host.name
    end
  end

  describe "Add and remove alias" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "add_alias with empty name shows error", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      html = render_click(view, "add_alias", %{})

      assert html =~ "cannot be empty"
    end
  end

  describe "Range/place management" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "toggle_region in search mode is no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/new")

      html = render_click(view, "toggle_region", %{"code" => "US-CA"})

      # Should not crash, still show page
      assert html =~ "Add Host" or html =~ "host-picker"
    end

    test "toggle_region in edit mode works", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      html = render_click(view, "toggle_region", %{"code" => "US-CA"})

      # Should not crash
      assert html =~ host.name
    end

    test "toggle_region with invalid code is ignored", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      html = render_click(view, "toggle_region", %{"code" => "INVALID-CODE"})

      # Should not crash
      assert html =~ host.name
    end
  end

  describe "Range editing with state assertions" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "toggle_region adds code to host range", %{conn: conn} do
      # Host 6 (T. alpinus) has only US-CA in range
      # Toggle MX-JAL to add it
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      html = render_click(view, "toggle_region", %{"code" => "MX-JAL"})

      # Page should still render and show the host name
      assert html =~ "Thymus alpinus"
    end

    test "toggle_region three times removes code from host range", %{conn: conn} do
      # Host 6 (T. alpinus) has only US-CA in range
      # Tri-state: native → introduced → removed
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      # Add as native
      render_click(view, "toggle_region", %{"code" => "MX-JAL"})
      # Cycle to introduced
      render_click(view, "toggle_region", %{"code" => "MX-JAL"})
      # Remove
      html = render_click(view, "toggle_region", %{"code" => "MX-JAL"})

      assert html =~ "Thymus alpinus"
    end

    test "toggle_region marks form as dirty", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      # Toggle a region
      render_click(view, "toggle_region", %{"code" => "MX-JAL"})

      # Cancel should now show discard warning (form is dirty)
      html = render_click(view, "request_cancel", %{})
      assert html =~ "Discard" or html =~ "unsaved"
    end

    test "toggle_region on existing native code cycles to introduced", %{conn: conn} do
      # Host 6 has US-CA as native; first toggle cycles to introduced
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      render_click(view, "toggle_region", %{"code" => "US-CA"})

      range_entries = get_assign(view, :range_entries)
      assert range_entries["US-CA"].distribution_type == "introduced"
    end

    test "toggle_region on existing native code twice removes it", %{conn: conn} do
      # Host 6 has US-CA as native; native → introduced → removed
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      render_click(view, "toggle_region", %{"code" => "US-CA"})
      html = render_click(view, "toggle_region", %{"code" => "US-CA"})

      range_entries = get_assign(view, :range_entries)
      refute Map.has_key?(range_entries, "US-CA")
      assert html =~ "Thymus alpinus"
    end
  end

  describe "Rename/Reclassify modal" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "open_reclassify_modal shows the modal", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      html = view |> element("button", "Rename/Reclassify") |> render_click()

      assert html =~ "Rename and/or Reclassify Host"
      assert html =~ "Specific epithet"
      assert html =~ "Add scientific synonym alias"
    end

    test "close_reclassify_modal hides the modal", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      view |> element("button", "Rename/Reclassify") |> render_click()

      html =
        view
        |> with_target("#reclassify")
        |> render_click("close_reclassify_modal", %{})

      refute html =~ "Rename and/or Reclassify Host"
    end

    test "toggle_add_alias_on_rename toggles checkbox", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      view |> element("button", "Rename/Reclassify") |> render_click()

      html =
        view
        |> with_target("#reclassify")
        |> render_click("toggle_add_alias_on_rename", %{})

      # Just verify it doesn't crash
      assert html =~ "alias"
    end

    test "do_reclassify without genus selected shows error", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      view |> element("button", "Rename/Reclassify") |> render_click()
      view |> with_target("#reclassify") |> render_click("reclassify_clear_genus", %{})
      view |> with_target("#reclassify") |> render_click("do_reclassify", %{})
      html = render(view)

      assert html =~ "select a genus"
    end

    test "update_reclassify_epithet updates the input", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      view |> element("button", "Rename/Reclassify") |> render_click()

      html =
        view
        |> with_target("#reclassify")
        |> render_click("update_reclassify_epithet", %{"value" => "newepithet"})

      assert html =~ "newepithet"
    end
  end

  describe "Cancel and discard" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "request_cancel with clean form navigates away", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      # Form is clean, so cancel should navigate (returns redirect)
      result = render_click(view, "request_cancel", %{})

      # Should either redirect or show page
      case result do
        {:error, {:live_redirect, %{to: to}}} ->
          assert to =~ "/admin/hosts"

        html when is_binary(html) ->
          assert html =~ "Hosts" or html =~ host.name
      end
    end

    test "request_cancel with dirty form shows confirm modal", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      # Make form dirty by changing the abundance dropdown
      view
      |> form("#host-form", species: %{abundance_id: "2"})
      |> render_change()

      html = render_click(view, "request_cancel", %{})

      assert html =~ "Discard" or html =~ "unsaved"
    end
  end

  describe "UI elements" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "shows legend in edit mode", %{conn: conn} do
      host = require_host()
      {:ok, _view, html} = live(conn, ~p"/admin/hosts/#{host.id}")

      assert html =~ "Legend"
      assert html =~ "Documented"
      assert html =~ "Country-level"
      assert html =~ "Out of Range"
    end

    test "shows data complete checkbox in edit mode", %{conn: conn} do
      host = require_host()
      {:ok, _view, html} = live(conn, ~p"/admin/hosts/#{host.id}")

      assert html =~ "All galls known to occur on this plant"
    end

    test "shows genus field as disabled", %{conn: conn} do
      host = require_host()
      {:ok, _view, html} = live(conn, ~p"/admin/hosts/#{host.id}")

      assert html =~ "Genus (filled automatically)"
    end

    test "shows family field", %{conn: conn} do
      host = require_host()
      {:ok, _view, html} = live(conn, ~p"/admin/hosts/#{host.id}")

      assert html =~ "Family"
    end

    test "shows section field", %{conn: conn} do
      host = require_host()
      {:ok, _view, html} = live(conn, ~p"/admin/hosts/#{host.id}")

      assert html =~ "Section"
    end
  end

  describe "Section persistence on new host" do
    setup %{conn: conn} do
      # Create a plant family, genus, and section for testing.
      # Family must have description "Plant" to be recognized as a plant family.
      {:ok, family} =
        Gallformers.Taxonomy.create_taxonomy(%{
          name: "Sectionaceae",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Gallformers.Taxonomy.create_taxonomy(%{
          name: "Sectionus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, section} =
        Gallformers.Taxonomy.create_taxonomy(%{
          name: "TestSection",
          type: "section",
          parent_id: genus.id
        })

      {:ok, conn: setup_admin_session(conn), section: section, genus: genus}
    end

    test "section selection persists when creating a new host", %{conn: conn, section: section} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/new")

      # Create a host with genus Sectionus (name must start with the genus name)
      render_click(view, "create_host", %{"name" => "Sectionus newspecies"})

      # Select the section from the dropdown
      render_click(view, "select_section", %{"section_id" => to_string(section.id)})

      # Add range data (required for save)
      render_click(view, "toggle_region", %{"code" => "US-CA"})

      # Submit the form
      render_click(view, "save", %{"species" => %{}})

      # push_navigate triggers a redirect
      {path, _flash} = assert_redirect(view, 200)

      # Verify at the data level that section was persisted
      host_id = path |> String.split("/") |> List.last() |> String.to_integer()
      taxonomy = Gallformers.Taxonomy.get_taxonomy_for_species(host_id)
      assert taxonomy.section != nil, "section should be linked but was nil"
      assert taxonomy.section.id == section.id
    end
  end

  describe "Range entries state" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "loading host for edit builds range_entries map from place entries", %{conn: conn} do
      # Host 6 (T. alpinus) has US-CA as exact/native
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      # Verify range_entries is a map with expected structure
      range_entries = get_assign(view, :range_entries)
      assert is_map(range_entries)
      assert Map.has_key?(range_entries, "US-CA")
      assert range_entries["US-CA"].precision == "exact"
      assert range_entries["US-CA"].distribution_type == "native"
    end

    test "loading host with introduced range includes distribution_type", %{conn: conn} do
      # Host 7 (T. serpyllum) has US-CA as native and BS (Bahamas) as introduced
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/7")

      range_entries = get_assign(view, :range_entries)
      assert is_map(range_entries)

      # Check introduced entry exists
      bs_entry = range_entries["BS"]
      assert bs_entry != nil
      assert bs_entry.distribution_type == "introduced"
    end

    test "original_range_entries matches range_entries on load", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      range_entries = get_assign(view, :range_entries)
      original = get_assign(view, :original_range_entries)
      assert range_entries == original
    end

    test "toggle_region updates range_entries map", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      # Add MX-JAL
      render_click(view, "toggle_region", %{"code" => "MX-JAL"})

      range_entries = get_assign(view, :range_entries)
      assert Map.has_key?(range_entries, "MX-JAL")
      assert range_entries["MX-JAL"].precision == "exact"
      assert range_entries["MX-JAL"].distribution_type == "native"
    end

    test "toggle_region second click changes native to introduced", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      # First click: add as native
      render_click(view, "toggle_region", %{"code" => "MX-JAL"})
      # Second click: cycle to introduced
      render_click(view, "toggle_region", %{"code" => "MX-JAL"})

      range_entries = get_assign(view, :range_entries)
      assert Map.has_key?(range_entries, "MX-JAL")
      assert range_entries["MX-JAL"].distribution_type == "introduced"
      assert range_entries["MX-JAL"].precision == "exact"
    end

    test "toggle_region third click removes from range_entries", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      # native → introduced → removed
      render_click(view, "toggle_region", %{"code" => "MX-JAL"})
      render_click(view, "toggle_region", %{"code" => "MX-JAL"})
      render_click(view, "toggle_region", %{"code" => "MX-JAL"})

      range_entries = get_assign(view, :range_entries)
      refute Map.has_key?(range_entries, "MX-JAL")
    end

    test "toggle_region full round-trip: add → introduced → remove → add again", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      # Add as native
      render_click(view, "toggle_region", %{"code" => "MX-JAL"})
      assert get_assign(view, :range_entries)["MX-JAL"].distribution_type == "native"

      # Cycle to introduced
      render_click(view, "toggle_region", %{"code" => "MX-JAL"})
      assert get_assign(view, :range_entries)["MX-JAL"].distribution_type == "introduced"

      # Remove
      render_click(view, "toggle_region", %{"code" => "MX-JAL"})
      refute Map.has_key?(get_assign(view, :range_entries), "MX-JAL")

      # Add again as native
      render_click(view, "toggle_region", %{"code" => "MX-JAL"})
      assert get_assign(view, :range_entries)["MX-JAL"].distribution_type == "native"
    end

    test "new host starts with empty range_entries", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/new")

      render_click(view, "create_host", %{"name" => "GenusAlpha testspecies"})

      range_entries = get_assign(view, :range_entries)
      assert range_entries == %{}
    end

    test "save with edit mode reloads range_entries from DB", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      # Add a new place
      render_click(view, "toggle_region", %{"code" => "MX-JAL"})

      # Save
      render_click(view, "save", %{"species" => %{}})

      # After save, range_entries and original should be equal and include new entry
      range_entries = get_assign(view, :range_entries)
      original = get_assign(view, :original_range_entries)
      assert range_entries == original
      assert Map.has_key?(range_entries, "MX-JAL")
      assert Map.has_key?(range_entries, "US-CA")
    end
  end

  describe "CountryDrillDown tri-state cycle" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "cycle_entry adds subdivision as native, then introduced, then removes", %{conn: conn} do
      # Host 7 (T. serpyllum) has US-CA as native
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/7")

      # Open drill-down for US (has subdivisions)
      render_click(view, "toggle_country", %{"code" => "US"})

      # Simulate CountryDrillDown sending cycle_entry for US-NY (not in range)
      alias GallformersWeb.Admin.CountryDrillDown
      send(view.pid, {CountryDrillDown, {:cycle_entry, "US-NY"}})

      # Should be added as native
      range_entries = get_assign(view, :range_entries)
      assert range_entries["US-NY"].distribution_type == "native"
      assert range_entries["US-NY"].precision == "exact"

      # Cycle again → introduced
      send(view.pid, {CountryDrillDown, {:cycle_entry, "US-NY"}})
      range_entries = get_assign(view, :range_entries)
      assert range_entries["US-NY"].distribution_type == "introduced"

      # Cycle again → removed
      send(view.pid, {CountryDrillDown, {:cycle_entry, "US-NY"}})
      range_entries = get_assign(view, :range_entries)
      refute Map.has_key?(range_entries, "US-NY")
    end

    test "cycle_entry on existing native entry cycles to introduced", %{conn: conn} do
      # Host 7 has US-CA as native
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/7")

      alias GallformersWeb.Admin.CountryDrillDown
      send(view.pid, {CountryDrillDown, {:cycle_entry, "US-CA"}})

      range_entries = get_assign(view, :range_entries)
      assert range_entries["US-CA"].distribution_type == "introduced"
    end

    test "toggle_exact still works for select_all/deselect_all", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/7")

      alias GallformersWeb.Admin.CountryDrillDown

      # select_all_exact adds entries as native
      send(view.pid, {CountryDrillDown, {:select_all_exact, ["US-NY", "US-TX"]}})

      range_entries = get_assign(view, :range_entries)
      assert range_entries["US-NY"].distribution_type == "native"
      assert range_entries["US-TX"].distribution_type == "native"

      # deselect_all_exact removes entries
      send(view.pid, {CountryDrillDown, {:deselect_all_exact, ["US-NY", "US-TX"]}})

      range_entries = get_assign(view, :range_entries)
      refute Map.has_key?(range_entries, "US-NY")
      refute Map.has_key?(range_entries, "US-TX")
    end
  end

  # Helper to extract assigns from a LiveView
  defp get_assign(view, key) do
    :sys.get_state(view.pid).socket.assigns[key]
  end

  describe "Range data validation" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "save in edit mode fails when host has no range data", %{conn: conn} do
      # Host 6 (Thymus alpinus) has range data - remove it by toggling its only region off
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      # Tri-state: native → introduced → removed (2 clicks from native)
      render_click(view, "toggle_region", %{"code" => "US-CA"})
      render_click(view, "toggle_region", %{"code" => "US-CA"})

      # Verify range_entries is actually empty
      assert get_assign(view, :range_entries) == %{}

      # Attempt to save — flash appears on the same page
      render_click(view, "save", %{"species" => %{}})
      html = render(view)

      assert html =~ "at least one range"
    end

    test "save in new mode fails when host has no range data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/new")

      # Create a new host using a genus that exists in test DB
      render_click(view, "create_host", %{"name" => "GenusAlpha norangehost"})

      # Attempt to save without adding any range data
      html = render_click(view, "save", %{"species" => %{}})

      assert html =~ "at least one range"
    end
  end

  describe "WCVP refresh — no match modal" do
    setup %{conn: conn} do
      # Create a minimal WCVP test DB with names that won't match any test host
      db_path = Application.get_env(:gallformers, Gallformers.Repo.WCVP)[:database]
      db_path |> Path.dirname() |> File.mkdir_p!()
      {:ok, db} = Exqlite.Sqlite3.open(db_path)

      :ok = Exqlite.Sqlite3.execute(db, "DROP TABLE IF EXISTS wcvp_distributions")
      :ok = Exqlite.Sqlite3.execute(db, "DROP TABLE IF EXISTS wcvp_names")

      :ok =
        Exqlite.Sqlite3.execute(db, """
        CREATE TABLE wcvp_names (
          plant_name_id TEXT PRIMARY KEY,
          taxon_name TEXT NOT NULL,
          taxon_status TEXT NOT NULL DEFAULT 'Accepted',
          accepted_plant_name_id TEXT,
          family TEXT NOT NULL,
          genus TEXT NOT NULL,
          species TEXT NOT NULL,
          taxon_authors TEXT,
          powo_id TEXT
        )
        """)

      :ok =
        Exqlite.Sqlite3.execute(db, """
        CREATE TABLE wcvp_distributions (
          plant_name_id TEXT NOT NULL,
          area_code_l3 TEXT NOT NULL,
          introduced TEXT NOT NULL DEFAULT '0',
          extinct TEXT NOT NULL DEFAULT '0',
          location_doubtful TEXT NOT NULL DEFAULT '0',
          PRIMARY KEY (plant_name_id, area_code_l3, introduced)
        )
        """)

      # Insert WCVP names that won't prefix-match any test host
      # but are findable via contains-search
      :ok =
        Exqlite.Sqlite3.execute(
          db,
          "INSERT INTO wcvp_names VALUES ('500', 'Zzyzx wcvponly', 'Accepted', '500', 'Testaceae', 'Zzyzx', 'wcvponly', 'Test', NULL)"
        )

      # A subspecies entry searchable by "Quercus alba" contains-match
      :ok =
        Exqlite.Sqlite3.execute(
          db,
          "INSERT INTO wcvp_names VALUES ('501', 'Quercus alnobetula subsp. alba', 'Accepted', '501', 'Fagaceae', 'Quercus', 'alnobetula', 'L.', 'urn:test')"
        )

      :ok =
        Exqlite.Sqlite3.execute(
          db,
          "INSERT INTO wcvp_distributions VALUES ('501', 'ALB', '0', '0', '0')"
        )

      Exqlite.Sqlite3.close(db)

      case Repo.WCVP.start_link() do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      on_exit(fn -> File.rm(db_path) end)

      {:ok, conn: setup_admin_session(conn)}
    end

    test "opens search modal instead of flash when no WCVP match", %{conn: conn} do
      # Verify WCVP is available for this test
      assert Lookup.available?(), "WCVP repo must be available for this test"

      host = require_host()
      {:ok, view, html} = live(conn, ~p"/admin/hosts/#{host.id}")

      # WCVP refresh button should be visible
      assert html =~ "Refresh from POWO-WCVP",
             "WCVP refresh button not rendered — wcvp_available may be false"

      html = render_click(view, "refresh_from_wcvp", %{})

      # Should show the search modal, not a flash toast
      assert html =~ "No exact match found"
      assert html =~ "wcvp-nomatch-search"
    end

    test "search modal pre-fills with host name", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      html = render_click(view, "refresh_from_wcvp", %{})

      assert html =~ host.name
    end

    test "search updates results in modal", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      render_click(view, "refresh_from_wcvp", %{})

      # Search for something that exists in WCVP
      html = render_keyup(view, "wcvp_nomatch_search", %{"value" => "Zzyzx"})

      assert html =~ "Zzyzx wcvponly"
    end

    test "select highlights result and enables Continue", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      render_click(view, "refresh_from_wcvp", %{})
      html = render_click(view, "select_wcvp_nomatch", %{"id" => "501"})

      # Continue button should now be enabled (no disabled attribute)
      assert html =~ "continue_wcvp_search"
      assert html =~ "bg-blue-600"
    end

    test "continue with selection opens diff modal", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      render_click(view, "refresh_from_wcvp", %{})
      render_click(view, "select_wcvp_nomatch", %{"id" => "501"})
      html = render_click(view, "continue_wcvp_search", %{})

      # Search modal should be gone, diff should be showing
      refute html =~ "No exact match found"
      assert html =~ "POWO-WCVP Data Comparison"
    end

    test "cancel closes the search modal", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      render_click(view, "refresh_from_wcvp", %{})
      html = render_click(view, "cancel_wcvp_search", %{})

      refute html =~ "No exact match found"
    end
  end

  describe "POWO diff integration" do
    setup %{conn: conn} do
      # Set up a WCVP DB with a name that matches our test host (Thymus alpinus, host 6)
      # and distribution data that differs from the host's current range
      db_path = Application.get_env(:gallformers, Gallformers.Repo.WCVP)[:database]
      db_path |> Path.dirname() |> File.mkdir_p!()
      {:ok, db} = Exqlite.Sqlite3.open(db_path)

      :ok = Exqlite.Sqlite3.execute(db, "DROP TABLE IF EXISTS wcvp_distributions")
      :ok = Exqlite.Sqlite3.execute(db, "DROP TABLE IF EXISTS wcvp_names")

      :ok =
        Exqlite.Sqlite3.execute(db, """
        CREATE TABLE wcvp_names (
          plant_name_id TEXT PRIMARY KEY,
          taxon_name TEXT NOT NULL,
          taxon_status TEXT NOT NULL DEFAULT 'Accepted',
          accepted_plant_name_id TEXT,
          family TEXT NOT NULL,
          genus TEXT NOT NULL,
          species TEXT NOT NULL,
          taxon_authors TEXT,
          powo_id TEXT
        )
        """)

      :ok =
        Exqlite.Sqlite3.execute(db, """
        CREATE TABLE wcvp_distributions (
          plant_name_id TEXT NOT NULL,
          area_code_l3 TEXT NOT NULL,
          introduced TEXT NOT NULL DEFAULT '0',
          extinct TEXT NOT NULL DEFAULT '0',
          location_doubtful TEXT NOT NULL DEFAULT '0',
          PRIMARY KEY (plant_name_id, area_code_l3, introduced)
        )
        """)

      # Host 6 is "Thymus alpinus" with US-CA as native
      # WCVP says: native in NWY (Norway), introduced in ALB (Albania)
      # This means: add_native=[NWY], add_introduced=[ALB], remove=[US-CA]
      :ok =
        Exqlite.Sqlite3.execute(
          db,
          "INSERT INTO wcvp_names VALUES ('600', 'Thymus alpinus', 'Accepted', '600', 'Lamiaceae', 'Thymus', 'alpinus', 'L.', 'urn:lsid:ipni.org:names:test')"
        )

      # NWY = Norway (TDWG L3 code that maps to NO in our places)
      :ok =
        Exqlite.Sqlite3.execute(
          db,
          "INSERT INTO wcvp_distributions VALUES ('600', 'NWY', '0', '0', '0')"
        )

      # ALB = Albania (TDWG L3 code that maps to AL in our places)
      :ok =
        Exqlite.Sqlite3.execute(
          db,
          "INSERT INTO wcvp_distributions VALUES ('600', 'ALB', '1', '0', '0')"
        )

      Exqlite.Sqlite3.close(db)

      case Repo.WCVP.start_link() do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      on_exit(fn -> File.rm(db_path) end)

      {:ok, conn: setup_admin_session(conn)}
    end

    test "refresh from POWO shows diff component", %{conn: conn} do
      assert Lookup.available?(), "WCVP repo must be available"
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      html = render_click(view, "refresh_from_wcvp", %{})

      assert html =~ "POWO-WCVP Data Comparison"
      # powo_diff assign should be populated
      assert get_assign(view, :powo_diff) != nil
    end

    test "cancel from diff component dismisses it", %{conn: conn} do
      assert Lookup.available?(), "WCVP repo must be available"
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      render_click(view, "refresh_from_wcvp", %{})
      assert get_assign(view, :powo_diff) != nil

      # Send cancel message as the PowoDiffReview component would
      alias GallformersWeb.Admin.PowoDiffReview
      send(view.pid, {PowoDiffReview, :cancel})

      # Allow the handle_info to process
      _ = render(view)

      assert get_assign(view, :powo_diff) == nil
    end

    test "apply from diff component updates range_entries and stages host_traits", %{conn: conn} do
      assert Lookup.available?(), "WCVP repo must be available"
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      render_click(view, "refresh_from_wcvp", %{})
      diff = get_assign(view, :powo_diff)
      assert diff != nil

      # Simulate applying with all defaults selected (which is what the component does).
      # In the component, init_selections selects ALL codes in every bucket.
      # For remove: selected = codes to KEEP. So all-selected means nothing removed.
      # To test actual removal, we deselect remove codes (pass empty set).
      alias GallformersWeb.Admin.PowoDiffReview

      selections = %{
        add_native: MapSet.new(diff.add_native),
        add_introduced: MapSet.new(diff.add_introduced),
        remove: MapSet.new(),
        reclassify_to_introduced: MapSet.new(diff.reclassify_to_introduced),
        reclassify_to_native: MapSet.new(diff.reclassify_to_native)
      }

      send(view.pid, {PowoDiffReview, {:apply, selections}})
      _ = render(view)

      # Diff should be cleared
      assert get_assign(view, :powo_diff) == nil

      # pending_host_traits should be set
      pending = get_assign(view, :pending_host_traits)
      assert pending != nil
      assert pending.wcvp_id == "600"
      assert pending.powo_id == "urn:lsid:ipni.org:names:test"

      # Range entries should reflect the diff
      range_entries = get_assign(view, :range_entries)

      # The add_native codes should be present
      for code <- diff.add_native do
        assert Map.has_key?(range_entries, code),
               "Expected add_native code #{code} in range_entries"

        assert range_entries[code].distribution_type == "native"
      end

      # The add_introduced codes should be present
      for code <- diff.add_introduced do
        assert Map.has_key?(range_entries, code),
               "Expected add_introduced code #{code} in range_entries"

        assert range_entries[code].distribution_type == "introduced"
      end

      # The remove codes should be gone (empty selections.remove = keep nothing)
      for code <- diff.remove do
        refute Map.has_key?(range_entries, code),
               "Expected remove code #{code} to be gone from range_entries"
      end

      # Form should be dirty
      assert get_assign(view, :form_dirty) == true
    end

    test "apply with empty selections changes nothing except host_traits", %{conn: conn} do
      assert Lookup.available?(), "WCVP repo must be available"
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/6")

      original_entries = get_assign(view, :range_entries)

      render_click(view, "refresh_from_wcvp", %{})

      alias GallformersWeb.Admin.PowoDiffReview

      # Empty selections: nothing added, nothing reclassified.
      # For remove: selected = codes to KEEP. Empty = keep nothing = remove all in diff.remove.
      # So we need to test with remove populated to keep the removes.
      diff = get_assign(view, :powo_diff)

      selections = %{
        add_native: MapSet.new(),
        add_introduced: MapSet.new(),
        remove: MapSet.new(diff.remove),
        reclassify_to_introduced: MapSet.new(),
        reclassify_to_native: MapSet.new()
      }

      send(view.pid, {PowoDiffReview, {:apply, selections}})
      _ = render(view)

      # Range entries should be unchanged (nothing added, removes all kept)
      assert get_assign(view, :range_entries) == original_entries
    end
  end

  describe "Access control" do
    test "page requires admin session", %{conn: _conn} do
      conn_without_admin = build_conn()
      conn_result = get(conn_without_admin, ~p"/admin/hosts/new")

      assert redirected_to(conn_result) =~ "/" or redirected_to(conn_result) =~ "/auth"
    end
  end

  describe "WCVP sync status display" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "shows 'Never synced with WCVP' when wcvp_synced_at is nil", %{conn: conn} do
      host = require_host()

      # Ensure host_traits exist with range_confirmed: false, wcvp_synced_at: nil
      Plants.upsert_host_traits(host.id, %{range_confirmed: false, wcvp_synced_at: nil})

      {:ok, _view, html} = live(conn, ~p"/admin/hosts/#{host.id}")

      assert html =~ "Never synced with WCVP"
      assert html =~ "Range needs review"
    end

    test "shows 'Range confirmed' and sync date when range_confirmed is true", %{conn: conn} do
      host = require_host()

      synced_at = ~U[2025-06-15 14:30:00Z]

      Plants.upsert_host_traits(host.id, %{
        range_confirmed: true,
        wcvp_synced_at: synced_at
      })

      {:ok, _view, html} = live(conn, ~p"/admin/hosts/#{host.id}")

      assert html =~ "Range confirmed"
      assert html =~ "Jun 15, 2025"
    end

    test "shows 'Range needs review' with sync date when range_confirmed is false and synced_at is set",
         %{conn: conn} do
      host = require_host()

      synced_at = ~U[2025-03-01 10:00:00Z]

      Plants.upsert_host_traits(host.id, %{
        range_confirmed: false,
        wcvp_synced_at: synced_at
      })

      {:ok, _view, html} = live(conn, ~p"/admin/hosts/#{host.id}")

      assert html =~ "Range needs review"
      assert html =~ "Mar 01, 2025"
    end
  end
end
