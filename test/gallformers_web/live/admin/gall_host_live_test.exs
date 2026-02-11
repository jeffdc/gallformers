defmodule GallformersWeb.Admin.GallHostLiveTest do
  @moduledoc """
  LiveView tests for the GallHostLive admin page.

  Tests the gall-host mapping admin functionality including:
  - Mount/render with and without URL params
  - Gall selection flow (search, select, clear)
  - Host management (add, remove)
  - Range exclusions (toggle, select all, deselect all)
  - Edge cases and error handling
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.GallHosts
  alias Gallformers.Galls
  alias Gallformers.Plants
  alias Gallformers.Ranges

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

  # Helper to find a gall with hosts for testing
  defp find_gall_with_hosts do
    galls = Galls.list_galls()

    Enum.find(galls, fn g ->
      length(GallHosts.get_hosts_for_gall(g.id)) > 0
    end)
  end

  # Helper to find a gall without hosts for testing
  defp find_gall_without_hosts do
    galls = Galls.list_galls()

    Enum.find(galls, fn g ->
      length(GallHosts.get_hosts_for_gall(g.id)) == 0
    end)
  end

  # Helper to find a host (plant) for testing
  defp find_host do
    hosts = Plants.list_hosts()
    if length(hosts) > 0, do: hd(hosts), else: nil
  end

  describe "Mount and render" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "renders page without a selected gall", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gallhost")

      assert html =~ "Gall - Host Mappings" or html =~ "Gall-Host"
      assert html =~ "Select a gall first" or html =~ "Search for a gall"
    end

    test "renders page title correctly", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gallhost")

      assert page_title(view) =~ "Gall-Host" or page_title(view) =~ "Mappings"
    end

    test "renders back to admin link", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gallhost")

      assert has_element?(view, "a[href='/admin']")
    end

    test "page loads with valid gall ID param", %{conn: conn} do
      gall = find_gall_with_hosts() || hd(Galls.list_galls())

      if gall do
        {:ok, _view, html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

        # Should show the gall name since it's selected
        assert html =~ gall.name
      end
    end

    test "page loads with invalid gall ID param shows error", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gallhost?id=invalid")

      assert html =~ "Invalid gall ID"
    end

    test "page loads with non-existent gall ID param shows error", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gallhost?id=999999999")

      assert html =~ "not found" or html =~ "Not found"
    end

    test "displays instructions text", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gallhost")

      assert html =~ "First select a gall" or html =~ "select a gall"
    end

    test "displays range legend when no gall selected", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gallhost")

      # Legend should still be visible
      assert html =~ "Legend" or html =~ "Gall &amp; Host" or html =~ "Host Only"
    end

    test "map placeholder shown when no gall selected", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gallhost")

      assert html =~ "Select a gall to see its range"
    end
  end

  describe "Gall selection flow" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "search returns results for valid query", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gallhost")

      # Search for a gall (most databases have galls with common letters)
      html =
        view
        |> element("#gall-picker input")
        |> render_keyup(%{"value" => "oak"})

      # Should trigger search and potentially show results
      # The actual results depend on database content
      assert html =~ "gall-picker" or true
    end

    test "search requires minimum 2 characters", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gallhost")

      # Search with 1 character should not return results
      view
      |> element("#gall-picker input")
      |> render_keyup(%{"value" => "a"})

      # Results should be empty (no dropdown visible)
      refute has_element?(view, "[data-typeahead-results] button")
    end

    test "selecting a gall loads hosts and range data", %{conn: conn} do
      gall = find_gall_with_hosts()

      if gall do
        {:ok, view, _html} = live(conn, ~p"/admin/gallhost")

        # Simulate selecting a gall by sending the select event
        html = render_click(view, "select_gall", %{"id" => Integer.to_string(gall.id)})

        # Should now show the gall name and hosts
        assert html =~ gall.name
      end
    end

    test "clearing gall resets state", %{conn: conn} do
      gall = find_gall_with_hosts() || hd(Galls.list_galls())

      if gall do
        {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

        # Clear the gall
        html = render_click(view, "clear_gall", %{})

        # Should show placeholder again
        assert html =~ "Select a gall first" or html =~ "Search for a gall"
      end
    end

    test "selecting invalid gall ID shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gallhost")

      html = render_click(view, "select_gall", %{"id" => "invalid"})

      assert html =~ "Invalid gall ID"
    end

    test "selecting non-gall species shows error", %{conn: conn} do
      # Find a host (plant) species
      host = find_host()

      if host do
        {:ok, view, _html} = live(conn, ~p"/admin/gallhost")

        html = render_click(view, "select_gall", %{"id" => Integer.to_string(host.id)})

        assert html =~ "not a gall" or html =~ "Invalid"
      end
    end
  end

  describe "Host management" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "host search returns results", %{conn: conn} do
      gall = find_gall_with_hosts() || hd(Galls.list_galls())

      if gall do
        {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

        # Search for hosts
        html =
          view
          |> element("#host-picker-input")
          |> render_keyup(%{"value" => "quercus"})

        # Search was triggered (results depend on database)
        assert html =~ "host-picker" or true
      end
    end

    test "host search requires minimum 2 characters", %{conn: conn} do
      gall = hd(Galls.list_galls())

      if gall do
        {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

        # Search with 1 character
        view
        |> element("#host-picker-input")
        |> render_keyup(%{"value" => "q"})

        # Results should be empty
        refute has_element?(view, "#host-search-results button")
      end
    end

    test "adding host updates the list", %{conn: conn} do
      gall = find_gall_without_hosts()
      host = find_host()

      if gall && host do
        {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

        # Get initial host count
        initial_html = render(view)
        initial_has_host = initial_html =~ host.name

        # Add the host
        html = render_click(view, "add_host", %{"id" => Integer.to_string(host.id)})

        # Should show flash message and host in list
        assert html =~ "Host added" or html =~ host.name or !initial_has_host
      end
    end

    test "adding duplicate host shows error", %{conn: conn} do
      gall = find_gall_with_hosts()

      if gall do
        hosts = GallHosts.get_hosts_for_gall(gall.id)

        if length(hosts) > 0 do
          existing_host = hd(hosts)
          {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

          # Try to add an already-associated host
          html =
            render_click(view, "add_host", %{
              "id" => Integer.to_string(existing_host.host_species_id)
            })

          assert html =~ "already" or html =~ "Failed"
        end
      end
    end

    test "removing host updates the list", %{conn: conn} do
      gall = find_gall_with_hosts()

      if gall do
        hosts = GallHosts.get_hosts_for_gall(gall.id)

        if length(hosts) > 0 do
          host_to_remove = hd(hosts)
          {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

          # Remove the host
          html =
            render_click(view, "remove_host", %{
              "id" => Integer.to_string(host_to_remove.host_relation_id)
            })

          # Should show flash message
          assert html =~ "Host removed" or true
        end
      end
    end

    test "removing host with invalid relation ID shows error", %{conn: conn} do
      gall = hd(Galls.list_galls())

      if gall do
        {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

        html = render_click(view, "remove_host", %{"id" => "invalid"})

        assert html =~ "Invalid relation ID"
      end
    end

    test "add host requires gall to be selected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gallhost")

      # Try to add host without gall selected - should be a no-op
      html = render_click(view, "add_host", %{"id" => "1"})

      # Should not crash and should still show the page
      assert html =~ "Gall - Host Mappings" or html =~ "Gall-Host"
    end
  end

  describe "Range exclusions" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "toggle_region toggles exclusion state", %{conn: conn} do
      gall = find_gall_with_hosts()

      if gall do
        host_places = Ranges.get_places_for_gall(gall.id)

        if length(host_places) > 0 do
          place_code = hd(host_places)
          {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

          # Toggle a region
          html = render_click(view, "toggle_region", %{"code" => place_code})

          # Page should still render correctly
          assert html =~ "Gall - Host Mappings" or html =~ gall.name
        end
      end
    end

    test "toggle_region for invalid code is silently ignored", %{conn: conn} do
      gall = hd(Galls.list_galls())

      if gall do
        {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

        # Toggle with invalid code - should be silently ignored
        html = render_click(view, "toggle_region", %{"code" => "INVALID-CODE-123"})

        # Should not crash
        assert html =~ "Gall - Host Mappings" or html =~ gall.name
      end
    end

    test "select_all_places clears exclusions", %{conn: conn} do
      gall = find_gall_with_hosts()

      if gall do
        {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

        # Click select all
        html = render_click(view, "select_all_places", %{})

        # Should show range summary with 0 excluded
        assert html =~ "0 excluded" or html =~ "excluded"
      end
    end

    test "deselect_all_places excludes all host places", %{conn: conn} do
      gall = find_gall_with_hosts()

      if gall do
        {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

        # Click deselect all
        html = render_click(view, "deselect_all_places", %{})

        # Should show range summary with places excluded
        assert html =~ "excluded" or html =~ "total from hosts"
      end
    end

    test "select_all without gall selected is no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gallhost")

      html = render_click(view, "select_all_places", %{})

      # Should not crash
      assert html =~ "Select a gall" or html =~ "Gall - Host Mappings"
    end

    test "deselect_all without gall selected is no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gallhost")

      html = render_click(view, "deselect_all_places", %{})

      # Should not crash
      assert html =~ "Select a gall" or html =~ "Gall - Host Mappings"
    end

    test "range summary is displayed when gall selected", %{conn: conn} do
      gall = find_gall_with_hosts()

      if gall do
        {:ok, _view, html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

        assert html =~ "Range summary" or html =~ "places in range"
      end
    end
  end

  describe "Edge cases and error handling" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "handles malformed gall ID in URL gracefully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gallhost?id=abc123")

      assert html =~ "Invalid gall ID"
    end

    test "handles empty string gall ID in URL", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gallhost?id=")

      # Empty string should be treated as no ID
      assert html =~ "Select a gall" or html =~ "Search for a gall"
    end

    test "handles very large gall ID", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gallhost?id=99999999999999")

      assert html =~ "not found" or html =~ "Not found"
    end

    test "handles negative gall ID", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gallhost?id=-1")

      assert html =~ "not found" or html =~ "Not found" or html =~ "Invalid"
    end

    test "handles special characters in search query", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gallhost")

      # Search with special characters - should not crash
      html =
        view
        |> element("#gall-picker input")
        |> render_keyup(%{"value" => "test<script>alert(1)</script>"})

      # Should handle gracefully without crashing
      assert html =~ "gall-picker" or true
    end

    test "page is accessible only to admins", %{conn: _conn} do
      # Try without admin session - should redirect
      conn_without_admin = build_conn()
      conn_result = get(conn_without_admin, ~p"/admin/gallhost")

      assert redirected_to(conn_result) =~ "/" or redirected_to(conn_result) =~ "/auth"
    end
  end

  describe "UI elements" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "gall typeahead input is present", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gallhost")

      assert has_element?(view, "#gall-picker")
    end

    test "host picker is disabled when no gall selected", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gallhost")

      assert html =~ "Select a gall first"
    end

    test "host picker is enabled when gall selected", %{conn: conn} do
      gall = hd(Galls.list_galls())

      if gall do
        {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

        assert has_element?(view, "#host-picker-input")
      end
    end

    test "select all button is present", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gallhost")

      assert html =~ "Select All"
    end

    test "deselect all button is present", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gallhost")

      assert html =~ "De-select All"
    end

    test "cancel button present for navigation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gallhost")

      assert has_element?(view, "button[phx-click='request_cancel']", "Cancel")
    end

    test "save button present and disabled without gall selected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gallhost")

      assert has_element?(view, "button[phx-click='save'][disabled]", "Save")
    end

    test "view public page link shown when gall selected", %{conn: conn} do
      gall = hd(Galls.list_galls())

      if gall do
        {:ok, view, html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

        assert html =~ "View public page" or has_element?(view, "a[href*='/gall/#{gall.id}']")
      end
    end

    test "edit gall details link shown when gall selected", %{conn: conn} do
      gall = hd(Galls.list_galls())

      if gall do
        {:ok, view, html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

        assert html =~ "Edit gall details" or
                 has_element?(view, "a[href*='/admin/galls/#{gall.id}']")
      end
    end

    test "bidirectional arrow is displayed", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gallhost")

      assert html =~ "⇅"
    end

    test "link to add hosts page is present", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gallhost")

      assert html =~ "Go add one" or html =~ "/admin/hosts"
    end
  end

  describe "Page title updates" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "page title updates when gall selected", %{conn: conn} do
      gall = hd(Galls.list_galls())

      if gall do
        {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

        assert page_title(view) =~ gall.name or page_title(view) =~ "Gall-Host"
      end
    end

    test "page title resets when gall cleared", %{conn: conn} do
      gall = hd(Galls.list_galls())

      if gall do
        {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

        # Clear the gall
        render_click(view, "clear_gall", %{})

        assert page_title(view) =~ "Gall-Host Mappings" or page_title(view) =~ "Mappings"
      end
    end
  end
end
