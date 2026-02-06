defmodule GallformersWeb.AuthControllerTest do
  @moduledoc """
  Integration tests for the Auth controller login flow.

  Tests the user creation and update behavior during OAuth callbacks.
  Note: We don't test the actual Ueberauth OAuth flow - we trust the library.
  Instead, we test the callback handling and session management.
  """
  use GallformersWeb.ConnCase, async: false

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User

  # Helper to generate unique auth0 IDs
  defp unique_auth0_id, do: "auth0|test-#{System.unique_integer([:positive])}"

  describe "callback/2 - user creation on first login" do
    test "creates user record when user doesn't exist", %{conn: conn} do
      auth0_id = unique_auth0_id()

      # Simulate an Ueberauth success response
      auth = build_ueberauth_auth(auth0_id, "newuser@test.com", "New User", "newuser")

      conn =
        conn
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, auth)

      # User should not exist yet
      assert Accounts.get_user_by_auth0_id(auth0_id) == nil

      # Make callback request
      conn = get(conn, ~p"/auth/auth0/callback")

      # Should redirect to admin
      assert redirected_to(conn) =~ "/admin"

      # User should now exist in database
      user = Accounts.get_user_by_auth0_id(auth0_id)
      assert user != nil
      assert user.display_name == "New User"
      assert user.nickname == "newuser"
      assert user.show_on_about == false
    end

    test "stores Auth0User in session", %{conn: conn} do
      auth0_id = unique_auth0_id()
      auth = build_ueberauth_auth(auth0_id, "user@test.com", "Test User", "testuser")

      conn =
        conn
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/auth0/callback")

      # Check session has the user
      session_user = get_session(conn, :current_user)
      assert %Auth0User{} = session_user
      assert session_user.id == auth0_id
      assert session_user.email == "user@test.com"
    end

    test "sets welcome flash message", %{conn: conn} do
      auth0_id = unique_auth0_id()
      auth = build_ueberauth_auth(auth0_id, "user@test.com", "Welcome User", "welcomeuser")

      conn =
        conn
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/auth0/callback")

      # Should have welcome flash
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back"
    end
  end

  describe "callback/2 - user update on subsequent login" do
    test "updates nickname on subsequent login", %{conn: conn} do
      auth0_id = unique_auth0_id()

      # Create existing user with old nickname
      {:ok, _user} =
        Accounts.create_user(%{
          auth0_id: auth0_id,
          display_name: "Original Name",
          nickname: "oldnick"
        })

      # Simulate login with new nickname
      auth = build_ueberauth_auth(auth0_id, "user@test.com", "New Name", "newnick")

      conn =
        conn
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/auth0/callback")

      assert redirected_to(conn) =~ "/admin"

      # Nickname should be updated
      user = Accounts.get_user_by_auth0_id(auth0_id)
      assert user.nickname == "newnick"
    end

    test "preserves user-customized display_name", %{conn: conn} do
      auth0_id = unique_auth0_id()

      # Create existing user with custom display_name (different from nickname)
      {:ok, _user} =
        Accounts.create_user(%{
          auth0_id: auth0_id,
          display_name: "My Custom Display Name",
          nickname: "oldnick"
        })

      # Simulate login with different name from Auth0
      auth = build_ueberauth_auth(auth0_id, "user@test.com", "Auth0 Name", "newnick")

      conn =
        conn
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/auth0/callback")

      assert redirected_to(conn) =~ "/admin"

      # Custom display_name should be preserved
      user = Accounts.get_user_by_auth0_id(auth0_id)
      assert user.display_name == "My Custom Display Name"
      # But nickname should be updated
      assert user.nickname == "newnick"
    end
  end

  describe "callback/2 - failure handling" do
    test "handles authentication failure", %{conn: conn} do
      # Simulate an Ueberauth failure
      failure = %Ueberauth.Failure{
        provider: :auth0,
        strategy: Ueberauth.Strategy.Auth0,
        errors: [
          %Ueberauth.Failure.Error{
            message: "Invalid credentials",
            message_key: "invalid_credentials"
          }
        ]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> assign(:ueberauth_failure, failure)
        |> get(~p"/auth/auth0/callback")

      # Should redirect to home
      assert redirected_to(conn) == "/"
      # Should have error flash
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Authentication failed"
    end
  end

  describe "logout/2" do
    test "clears session and redirects to Auth0 logout", %{conn: conn} do
      # Setup a logged-in session
      auth0_user = %Auth0User{
        id: "auth0|123",
        email: "user@test.com",
        name: "Test User",
        nickname: "testuser",
        picture: nil,
        roles: ["admin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, auth0_user)
        |> get(~p"/auth/logout")

      # Should redirect to Auth0 logout URL
      location = redirected_to(conn, 302)
      assert location =~ "logout"

      # Session should be cleared
      # Note: The session is configured to drop, so we can't easily check it here
    end
  end

  # Helper to build a mock Ueberauth.Auth struct
  defp build_ueberauth_auth(auth0_id, email, name, nickname) do
    %Ueberauth.Auth{
      uid: auth0_id,
      provider: :auth0,
      strategy: Ueberauth.Strategy.Auth0,
      info: %Ueberauth.Auth.Info{
        email: email,
        name: name,
        nickname: nickname,
        image: nil
      },
      credentials: %Ueberauth.Auth.Credentials{
        token: "test-token",
        refresh_token: nil,
        expires: false,
        expires_at: nil
      },
      extra: %Ueberauth.Auth.Extra{
        raw_info: %{
          user: %{
            "sub" => auth0_id,
            "email" => email,
            "name" => name,
            "nickname" => nickname,
            "https://gallformers.org/roles" => ["admin"]
          }
        }
      }
    }
  end
end
