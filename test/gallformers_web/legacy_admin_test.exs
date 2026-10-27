defmodule GallformersWeb.LegacyAdminTest do
  @moduledoc """
  The switch that disables the old-domain admin screens on taxogall (matter
  `a856`): the `:legacy_admin_enabled` flag, checked by
  `GallformersWeb.Plugs.RequireLegacyAdmin` on HTTP requests and by the
  `GallformersWeb.LegacyAdmin` `on_mount` hook on live navigation and socket
  connects, and the links to the gated screens it hides.

  Uses the converted seeds (`priv/repo/test_seeds.sql`): Gall 300 has a Host
  (plant 10), an image and Sources; Source 59 is cited on it.

  Not async: the tests flip a global application env flag.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  # The public pages read the seeds.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  alias Gallformers.Accounts.Auth0User
  alias GallformersWeb.LegacyAdmin

  @admin_paths ~w(
    /admin/galls
    /admin/galls/new
    /admin/galls/undescribed
    /admin/galls/1
    /admin/gallhost
    /admin/gall-range
    /admin/hosts
    /admin/hosts/new
    /admin/hosts/1
    /admin/host-range
    /admin/taxonomy
    /admin/taxonomy/new
    /admin/taxonomy/1
    /admin/section
    /admin/section/1
    /admin/sources
    /admin/sources/new
    /admin/sources/1
    /admin/species-sources/add
    /admin/species-sources/find
    /admin/images
    /admin/image-audit
  )

  @superadmin_paths ~w(
    /admin/filter-terms
    /admin/filter-terms/new
    /admin/filter-terms/1
  )

  # Link prefixes of the gated screens; none may show while they are disabled.
  @gated_prefixes ~w(
    /admin/galls
    /admin/gallhost
    /admin/gall-range
    /admin/hosts
    /admin/host-range
    /admin/taxonomy
    /admin/section
    /admin/sources
    /admin/species-sources
    /admin/images
    /admin/image-audit
    /admin/filter-terms
  )

  setup do
    previous = Application.fetch_env(:gallformers, :legacy_admin_enabled)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:gallformers, :legacy_admin_enabled, value)
        :error -> Application.delete_env(:gallformers, :legacy_admin_enabled)
      end
    end)

    :ok
  end

  defp set_enabled(enabled?),
    do: Application.put_env(:gallformers, :legacy_admin_enabled, enabled?)

  defp log_in(conn, roles) do
    user = %Auth0User{
      id: "auth0|legacy-admin-test",
      email: "admin@test.com",
      name: "Test Admin",
      nickname: "testadmin",
      picture: nil,
      roles: roles
    }

    conn
    |> init_test_session(%{})
    |> put_session(:current_user, user)
    |> put_session(:db_display_name, "Test Admin")
  end

  defp refute_gated_links(view) do
    for prefix <- @gated_prefixes do
      refute has_element?(view, "a[href^='#{prefix}']"), "unexpected link to #{prefix}"
    end
  end

  describe "enabled?/0" do
    test "reads the :legacy_admin_enabled flag at runtime" do
      set_enabled(false)
      assert LegacyAdmin.enabled?() == false

      set_enabled(true)
      assert LegacyAdmin.enabled?() == true
    end

    test "is on in the test environment" do
      assert Application.fetch_env!(:gallformers, :legacy_admin_enabled) == true
    end
  end

  describe "gated screens over HTTP, disabled" do
    setup %{conn: conn} do
      set_enabled(false)
      {:ok, conn: log_in(conn, ["superadmin"])}
    end

    test "each gated route shows the being-rebuilt page, not the old LiveView", %{conn: conn} do
      for path <- @admin_paths ++ @superadmin_paths do
        html = conn |> get(path) |> html_response(200)

        assert html =~ "This admin screen is being rebuilt", "no notice at #{path}"
        refute html =~ "data-phx-session", "a LiveView mounted at #{path}"
      end
    end

    test "the page keeps the admin layout and links back to the dashboard", %{conn: conn} do
      html = conn |> get(~p"/admin/galls") |> html_response(200)

      assert html =~ ~s(id="admin-nav")
      assert html =~ ~s(href="/admin")
    end
  end

  describe "gated screens over HTTP, enabled" do
    setup %{conn: conn} do
      set_enabled(true)
      {:ok, conn: log_in(conn, ["superadmin"])}
    end

    test "the old LiveViews mount", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/galls")
      refute html =~ "This admin screen is being rebuilt"

      {:ok, _view, html} = live(conn, ~p"/admin/filter-terms")
      refute html =~ "This admin screen is being rebuilt"
    end
  end

  describe "gated screens over a live socket" do
    setup %{conn: conn} do
      {:ok, conn: log_in(conn, ["admin"])}
    end

    test "a socket connecting to a gated screen after it was disabled is sent to the dashboard",
         %{conn: conn} do
      set_enabled(true)
      conn = get(conn, ~p"/admin/galls")
      assert html_response(conn, 200) =~ "data-phx-session"

      set_enabled(false)

      result = live(conn)
      assert {:error, {:redirect, %{to: "/admin"}}} = result

      {:ok, conn} = follow_redirect(result, conn)
      assert html_response(conn, 200) =~ "This admin screen is being rebuilt"
    end

    test "live navigation between gated screens is stopped once they are disabled",
         %{conn: conn} do
      set_enabled(true)
      {:ok, view, _html} = live(conn, ~p"/admin/galls")

      set_enabled(false)

      result = live_redirect(view, to: ~p"/admin/hosts")
      assert {:error, {:redirect, %{to: "/admin"}}} = result

      {:ok, conn} = follow_redirect(result, conn)
      assert html_response(conn, 200) =~ "This admin screen is being rebuilt"
    end

    # LiveView logs a warning when navigation crosses live sessions.
    @tag :capture_log
    test "live navigation from the dashboard into a gated screen reloads the page over HTTP",
         %{conn: conn} do
      set_enabled(false)
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert {:error, {:redirect, %{to: to}}} = live_redirect(view, to: ~p"/admin/galls")
      assert to =~ "/admin/galls"
    end
  end

  describe "who can reach the gated screens" do
    test "an anonymous visitor is sent to log in, whether or not they are enabled",
         %{conn: conn} do
      for enabled? <- [true, false] do
        set_enabled(enabled?)
        conn = get(conn, ~p"/admin/galls")
        assert redirected_to(conn) == "/auth/auth0"
      end
    end

    test "a non-admin user is forbidden, whether or not they are enabled", %{conn: conn} do
      conn = log_in(conn, [])

      for enabled? <- [true, false] do
        set_enabled(enabled?)
        assert conn |> get(~p"/admin/galls") |> response(403)
      end
    end

    test "filter terms stay superadmin-only, whether or not they are enabled", %{conn: conn} do
      conn = log_in(conn, ["admin"])

      for enabled? <- [true, false] do
        set_enabled(enabled?)
        assert conn |> get(~p"/admin/filter-terms") |> response(403)
      end
    end

    test "read-only mode still blocks them", %{conn: conn} do
      set_enabled(false)
      :persistent_term.put({Gallformers.SiteSettings, :cache}, %{"read_only" => true})

      conn = conn |> log_in(["admin"]) |> get(~p"/admin/galls")

      assert response(conn, 503) =~ "read-only mode"
    end
  end

  describe "screens that are not gated, disabled" do
    setup %{conn: conn} do
      set_enabled(false)
      {:ok, conn: conn}
    end

    test "admin screens still mount", %{conn: conn} do
      conn = log_in(conn, ["admin"])

      for path <- ~w(/admin /admin/glossary /admin/articles /admin/keys /admin/profile) do
        assert {:ok, _view, html} = live(conn, path)
        refute html =~ "This admin screen is being rebuilt", "gated: #{path}"
      end
    end

    test "superadmin screens still mount", %{conn: conn} do
      conn = log_in(conn, ["superadmin"])

      assert {:ok, _view, _html} = live(conn, ~p"/admin/users")
    end
  end

  describe "admin navigation and dashboard, disabled" do
    setup %{conn: conn} do
      set_enabled(false)
      {:ok, conn: log_in(conn, ["superadmin"])}
    end

    test "link to no gated screen", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      refute_gated_links(view)
    end

    test "keep the links to the screens that are not gated", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      for href <- ~w(/admin/glossary /admin/articles /admin/keys /admin/articles/new
                     /admin/keys/new /admin/glossary/new /admin/users /admin/jobs) do
        assert has_element?(view, "a[href='#{href}']"), "missing link to #{href}"
      end
    end

    test "show the gated actions as being rebuilt", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Create a New Gall"
      assert html =~ "Filter Terms"
      assert html =~ "Being rebuilt (taxogall step 10)"
    end

    test "still show the counts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#admin-stats", "Galls")
      assert has_element?(view, "#admin-stats", "Images")
    end
  end

  describe "admin navigation and dashboard, enabled" do
    setup %{conn: conn} do
      set_enabled(true)
      {:ok, conn: log_in(conn, ["superadmin"])}
    end

    test "link to the gated screens", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      for href <- ~w(/admin/galls /admin/hosts /admin/sources /admin/images /admin/taxonomy
                     /admin/galls/new /admin/galls/undescribed /admin/hosts/new
                     /admin/sources/new /admin/gallhost /admin/gall-range /admin/host-range
                     /admin/species-sources/add /admin/species-sources/find
                     /admin/taxonomy/new /admin/section /admin/filter-terms) do
        assert has_element?(view, "a[href='#{href}']"), "missing link to #{href}"
      end
    end
  end

  describe "admin links on the public pages" do
    setup %{conn: conn} do
      {:ok, conn: log_in(conn, ["admin"])}
    end

    test "are hidden while the old screens are disabled", %{conn: conn} do
      set_enabled(false)

      for path <- [~p"/gall/300", ~p"/host/10", ~p"/source/59"] do
        {:ok, view, _html} = live(conn, path)
        refute_gated_links(view)
      end
    end

    test "show on the Gall page while they are enabled", %{conn: conn} do
      set_enabled(true)
      {:ok, view, _html} = live(conn, ~p"/gall/300")

      assert has_element?(view, "a[href='/admin/galls/300']")
      assert has_element?(view, "a[href='/admin/gallhost?id=300']")
      assert has_element?(view, "a[href='/admin/species-sources/add?species_id=300']")
      assert has_element?(view, "a[href^='/admin/species-sources/find?species_id=300']")
      assert has_element?(view, "a[href='/admin/images?species_id=300']")
    end

    test "show on the Host page while they are enabled", %{conn: conn} do
      set_enabled(true)
      {:ok, view, _html} = live(conn, ~p"/host/10")

      assert has_element?(view, "a[href='/admin/hosts/10']")
      assert has_element?(view, "a[href^='/admin/gallhost?id=']")
    end

    test "show on the Source page while they are enabled", %{conn: conn} do
      set_enabled(true)
      {:ok, view, _html} = live(conn, ~p"/source/59")

      assert has_element?(view, "a[href='/admin/sources/59']")
    end
  end
end
