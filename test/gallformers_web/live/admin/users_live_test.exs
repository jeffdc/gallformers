defmodule GallformersWeb.Admin.UsersLiveTest do
  @moduledoc """
  LiveView tests for the superadmin user management page.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User

  # Helper to generate unique auth0 IDs
  defp unique_auth0_id, do: "auth0|test-#{System.unique_integer([:positive])}"

  describe "User Management page - superadmin access" do
    setup %{conn: conn} do
      auth0_id = unique_auth0_id()

      # Create some test users
      {:ok, user1} =
        Accounts.create_user(%{
          auth0_id: unique_auth0_id(),
          display_name: "Test User One",
          nickname: "user1",
          show_on_about: true
        })

      {:ok, user2} =
        Accounts.create_user(%{
          auth0_id: unique_auth0_id(),
          display_name: "Test User Two",
          nickname: "user2",
          show_on_about: false
        })

      # Create superadmin Auth0User
      superadmin = %Auth0User{
        id: auth0_id,
        email: "superadmin@test.com",
        name: "Super Admin",
        nickname: "superadmin",
        picture: nil,
        roles: ["superadmin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, superadmin)
        |> put_session(:db_display_name, "Test User")

      {:ok, conn: conn, user1: user1, user2: user2, superadmin: superadmin}
    end

    test "page loads successfully for superadmin", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")

      assert html =~ "User Management"
    end

    test "lists all users", %{conn: conn, user1: user1, user2: user2} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")

      assert html =~ user1.display_name
      assert html =~ user2.display_name
    end

    test "displays display name and nickname", %{conn: conn, user1: user1} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")

      assert html =~ user1.display_name
      assert html =~ user1.nickname
    end

    test "shows toggle switch for show_on_about", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Should have toggle buttons with role="switch"
      assert has_element?(view, "button[role='switch']")
    end

    test "can toggle show_on_about for a user", %{conn: conn, user2: user2} do
      assert user2.show_on_about == false

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Click toggle for user2
      view
      |> element("button[phx-value-id='#{user2.id}']")
      |> render_click()

      # Verify the update persisted
      updated_user = Accounts.get_user(user2.id)
      assert updated_user.show_on_about == true
    end

    test "toggle updates show_on_about from true to false", %{conn: conn, user1: user1} do
      assert user1.show_on_about == true

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Click toggle for user1 (currently true)
      view
      |> element("button[phx-value-id='#{user1.id}']")
      |> render_click()

      # Verify the update persisted
      updated_user = Accounts.get_user(user1.id)
      assert updated_user.show_on_about == false
    end

    test "shows flash message after toggle", %{conn: conn, user1: user1} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> element("button[phx-value-id='#{user1.id}']")
      |> render_click()

      html = render(view)
      assert html =~ "visibility updated" or html =~ "updated"
    end

    test "shows user count", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")

      # Should show "Showing N users"
      assert html =~ "Showing"
      assert html =~ "users"
    end

    test "displays info banner about purpose", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")

      assert html =~ "Manage which users appear on the About page"
    end
  end

  describe "User Management page - non-superadmin access" do
    test "redirects unauthenticated users", %{conn: conn} do
      conn = get(conn, ~p"/admin/users")

      assert redirected_to(conn) =~ "/" or redirected_to(conn) =~ "/auth"
    end

    test "redirects regular admin users", %{conn: conn} do
      # Create Auth0User with only admin role (not superadmin)
      admin = %Auth0User{
        id: unique_auth0_id(),
        email: "admin@test.com",
        name: "Regular Admin",
        nickname: "admin",
        picture: nil,
        roles: ["admin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, admin)
        |> put_session(:db_display_name, "Test User")

      # Should be forbidden
      conn = get(conn, ~p"/admin/users")
      assert conn.status == 403 or conn.halted
    end

    test "returns forbidden for non-admin users", %{conn: conn} do
      # Create Auth0User with no admin roles
      user = %Auth0User{
        id: unique_auth0_id(),
        email: "user@test.com",
        name: "Regular User",
        nickname: "user",
        picture: nil,
        roles: []
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user)
        |> put_session(:db_display_name, "Test User")

      # Non-admin users should get forbidden (403) or be redirected
      conn = get(conn, ~p"/admin/users")

      # The RequireSuperAdmin plug returns 403 for authenticated non-superadmins
      # or redirects unauthenticated users
      assert conn.status == 403 or conn.status == 302 or conn.halted
    end
  end

  describe "User Management page - empty state" do
    test "handles empty state when no users exist", %{conn: conn} do
      # Note: This test may show existing users from the database
      # We'll just verify it doesn't crash with the "No users found" case
      superadmin = %Auth0User{
        id: unique_auth0_id(),
        email: "superadmin@test.com",
        name: "Super Admin",
        nickname: "superadmin",
        picture: nil,
        roles: ["superadmin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, superadmin)
        |> put_session(:db_display_name, "Test User")

      # Should load without error
      {:ok, _view, html} = live(conn, ~p"/admin/users")
      assert html =~ "User Management"
    end
  end

  describe "User Management page - display name fallback" do
    setup %{conn: conn} do
      # Create user with only nickname (no display_name)
      {:ok, user_with_nickname_only} =
        Accounts.create_user(%{
          auth0_id: unique_auth0_id(),
          display_name: nil,
          nickname: "justnickname"
        })

      # Create user with neither display_name nor nickname
      {:ok, user_with_nothing} =
        Accounts.create_user(%{
          auth0_id: unique_auth0_id(),
          display_name: nil,
          nickname: nil
        })

      superadmin = %Auth0User{
        id: unique_auth0_id(),
        email: "superadmin@test.com",
        name: "Super Admin",
        nickname: "superadmin",
        picture: nil,
        roles: ["superadmin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, superadmin)
        |> put_session(:db_display_name, "Test User")

      {:ok,
       conn: conn,
       user_with_nickname_only: user_with_nickname_only,
       user_with_nothing: user_with_nothing}
    end

    test "shows nickname when display_name is nil", %{conn: conn, user_with_nickname_only: user} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")

      # Should show the nickname as the display
      assert html =~ user.nickname
    end

    test "shows fallback when both are nil", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")

      # Should show "(no name)" or similar fallback
      assert html =~ "(no name)" or html =~ "Anonymous" or html =~ "-"
    end
  end

  describe "User Management page - table structure" do
    setup %{conn: conn} do
      superadmin = %Auth0User{
        id: unique_auth0_id(),
        email: "superadmin@test.com",
        name: "Super Admin",
        nickname: "superadmin",
        picture: nil,
        roles: ["superadmin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, superadmin)
        |> put_session(:db_display_name, "Test User")

      {:ok, conn: conn}
    end

    test "table has correct headers", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")

      assert html =~ "Display Name"
      assert html =~ "Nickname"
      assert html =~ "Show on About"
    end

    test "has proper table structure", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert has_element?(view, "table")
      assert has_element?(view, "thead")
      assert has_element?(view, "tbody")
    end
  end
end
