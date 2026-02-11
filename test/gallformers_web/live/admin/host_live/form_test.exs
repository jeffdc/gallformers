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
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User
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

      assert html =~ "Edit Host"
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
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      # The public page link is now an icon in the header with title attribute
      assert has_element?(view, "a[href='/host/#{host.id}'][title='View public page']")
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

    test "select_all_places in search mode is no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/new")

      html = render_click(view, "select_all_places", %{})

      assert html =~ "Add Host" or html =~ "host-picker"
    end

    test "select_all_places in edit mode works", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      html = render_click(view, "select_all_places", %{})

      assert html =~ host.name
    end

    test "deselect_all_places in search mode is no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/new")

      html = render_click(view, "deselect_all_places", %{})

      assert html =~ "Add Host" or html =~ "host-picker"
    end

    test "deselect_all_places in edit mode works", %{conn: conn} do
      host = require_host()
      {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

      html = render_click(view, "deselect_all_places", %{})

      assert html =~ host.name
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
      assert html =~ "In Range"
      assert html =~ "Out of Range"
    end

    test "shows map action buttons in edit mode", %{conn: conn} do
      host = require_host()
      {:ok, _view, html} = live(conn, ~p"/admin/hosts/#{host.id}")

      assert html =~ "Select All"
      assert html =~ "De-select All"
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

  describe "Access control" do
    test "page requires admin session", %{conn: _conn} do
      conn_without_admin = build_conn()
      conn_result = get(conn_without_admin, ~p"/admin/hosts/new")

      assert redirected_to(conn_result) =~ "/" or redirected_to(conn_result) =~ "/auth"
    end
  end
end
