defmodule GallformersWeb.Admin.ProfileLiveTest do
  @moduledoc """
  LiveView tests for the admin profile page.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User

  # Helper to generate unique auth0 IDs
  defp unique_auth0_id, do: "auth0|test-#{System.unique_integer([:positive])}"

  describe "Profile page - authenticated admin" do
    setup %{conn: conn} do
      auth0_id = unique_auth0_id()

      # Create a user profile in the database
      {:ok, user} =
        Accounts.create_user(%{
          auth0_id: auth0_id,
          display_name: "Test Admin",
          nickname: "testadmin",
          show_on_about: false
        })

      # Create a mock Auth0User session
      auth0_user = %Auth0User{
        id: auth0_id,
        email: "admin@test.com",
        name: "Test Admin",
        nickname: "testadmin",
        picture: nil,
        roles: ["admin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, auth0_user)
        |> put_session(:db_display_name, "Test User")

      {:ok, conn: conn, user: user, auth0_user: auth0_user}
    end

    test "page loads successfully for logged-in admin", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/profile")

      assert html =~ "Editing"
      assert html =~ "Display Name"
    end

    test "displays current user profile data", %{conn: conn, user: user} do
      {:ok, _view, html} = live(conn, ~p"/admin/profile")

      assert html =~ user.display_name
    end

    test "displays form fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      assert has_element?(view, "#profile-form")
      assert has_element?(view, "input[name='user[display_name]']")
      # iNaturalist is now a username field that gets converted to URL on save
      assert has_element?(view, "input[name='user[inat_username]']")
      assert has_element?(view, "input[name='user[social_url]']")
      assert has_element?(view, "input[name='user[personal_url]']")
      assert has_element?(view, "input[name='user[show_on_about]']")
    end

    test "can edit display_name and save", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      # Submit form with new display name
      view
      |> form("#profile-form", user: %{display_name: "New Display Name"})
      |> render_submit()

      # Verify the update persisted
      updated_user = Accounts.get_user(user.id)
      assert updated_user.display_name == "New Display Name"
    end

    test "can edit URLs and save", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      # Submit form with URLs
      # iNaturalist uses username-only field that converts to full URL on save
      view
      |> form("#profile-form",
        user: %{
          inat_username: "testuser",
          social_url: "https://twitter.com/testuser",
          personal_url: "https://example.com"
        }
      )
      |> render_submit()

      # Verify the update persisted
      updated_user = Accounts.get_user(user.id)
      # Username is converted to full URL when saved
      assert updated_user.inaturalist_url == "https://www.inaturalist.org/people/testuser"
      assert updated_user.social_url == "https://twitter.com/testuser"
      assert updated_user.personal_url == "https://example.com"
    end

    test "can toggle show_on_about and save", %{conn: conn, user: user} do
      assert user.show_on_about == false

      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      # Submit form with show_on_about toggled on
      view
      |> form("#profile-form", user: %{show_on_about: "true"})
      |> render_submit()

      # Verify the update persisted
      updated_user = Accounts.get_user(user.id)
      assert updated_user.show_on_about == true
    end

    test "URL fields use browser validation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      # iNaturalist is now a text field for username (not a URL)
      assert has_element?(view, "input[type='text'][name='user[inat_username]']")
      # These URL inputs have type="url" for browser validation
      assert has_element?(view, "input[type='url'][name='user[social_url]']")
      assert has_element?(view, "input[type='url'][name='user[personal_url]']")
    end

    test "redirects to refresh-session after save", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      assert {:error, {:redirect, %{to: to}}} =
               view
               |> form("#profile-form", user: %{display_name: "Updated Name"})
               |> render_submit()

      assert to =~ "/admin/refresh-session"
      assert to =~ "return_to=/admin/profile"
    end

    test "displays Auth0 nickname as read-only", %{conn: conn, auth0_user: auth0_user} do
      {:ok, _view, html} = live(conn, ~p"/admin/profile")

      # Should show the nickname from Auth0
      assert html =~ auth0_user.nickname
      # The nickname field should be disabled
      assert html =~ "disabled"
    end
  end

  describe "Profile page - non-admin access" do
    test "redirects unauthenticated users", %{conn: conn} do
      # Without session setup, should redirect
      conn = get(conn, ~p"/admin/profile")

      # Should redirect to login or home
      assert redirected_to(conn) =~ "/" or redirected_to(conn) =~ "/auth"
    end

    test "redirects non-admin users", %{conn: conn} do
      auth0_id = unique_auth0_id()

      # Create a user with no admin role
      {:ok, _user} =
        Accounts.create_user(%{
          auth0_id: auth0_id,
          display_name: "Regular User",
          nickname: "regular"
        })

      # Create Auth0User without admin role
      auth0_user = %Auth0User{
        id: auth0_id,
        email: "user@test.com",
        name: "Regular User",
        nickname: "regular",
        picture: nil,
        roles: []
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, auth0_user)
        |> put_session(:db_display_name, "Test User")

      # Should redirect or show forbidden
      conn = get(conn, ~p"/admin/profile")
      # The plug may redirect or return a 403
      assert conn.status == 403 or conn.halted
    end
  end

  describe "Profile page - user without profile" do
    test "creates profile automatically when not found", %{conn: conn} do
      # Create Auth0User for a user that doesn't have a database profile
      auth0_id = "auth0|nonexistent-#{System.unique_integer([:positive])}"

      auth0_user = %Auth0User{
        id: auth0_id,
        email: "noprofile@test.com",
        name: "No Profile User",
        nickname: "noprofile",
        picture: nil,
        roles: ["admin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, auth0_user)
        |> put_session(:db_display_name, "Test User")

      {:ok, _view, html} = live(conn, ~p"/admin/profile")

      # Should show success message about profile creation
      assert html =~ "Profile created successfully"

      # Verify profile was actually created in database
      user = Accounts.get_user_by_auth0_id(auth0_id)
      assert user != nil
      assert user.nickname == "noprofile"
      assert user.display_name == "No Profile User"
    end
  end

  describe "Profile page - form interactions" do
    setup %{conn: conn} do
      auth0_id = unique_auth0_id()

      {:ok, user} =
        Accounts.create_user(%{
          auth0_id: auth0_id,
          display_name: "Test Admin",
          nickname: "testadmin"
        })

      auth0_user = %Auth0User{
        id: auth0_id,
        email: "admin@test.com",
        name: "Test Admin",
        nickname: "testadmin",
        picture: nil,
        roles: ["admin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, auth0_user)
        |> put_session(:db_display_name, "Test User")

      {:ok, conn: conn, user: user}
    end

    test "cancel button exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      assert has_element?(view, "button", "Cancel")
    end

    test "save button exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      # Uses standard "Save" label (consistent with other admin pages)
      assert has_element?(view, "button[type='submit']")
    end

    test "back link points to dashboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      assert has_element?(view, "a[href='/admin']")
    end
  end
end
