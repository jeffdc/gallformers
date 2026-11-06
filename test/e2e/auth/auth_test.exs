defmodule GallformersWeb.E2E.AuthTest do
  @moduledoc """
  E2E tests for authentication-related UI behavior.

  The real Auth0 login/logout endpoints redirect to external pages, which the
  E2E harness should not follow. These tests verify the local app behavior that
  exposes those routes and the admin access mode used in E2E.
  """
  use GallformersWeb.E2ECase

  @moduletag :e2e
  @moduletag :e2e_auth

  describe "auth links" do
    test "home page shows login link when auth bypass is disabled", %{conn: conn} do
      Application.put_env(:gallformers, :dev_auth_bypass, false)
      on_exit(fn -> Application.put_env(:gallformers, :dev_auth_bypass, true) end)

      conn
      |> visit("/")
      |> assert_has("a[href='/auth/auth0']", text: "Log in")
    end

    test "home page shows logout link when auth bypass is enabled", %{conn: conn} do
      conn
      |> visit("/")
      |> assert_has("a[href='/auth/logout']", text: "Log out")
    end
  end

  describe "protected routes" do
    test "admin dashboard loads through the E2E auth bypass", %{conn: conn} do
      conn
      |> visit("/admin")
      |> assert_has("h2", text: "Quick Actions")
    end
  end
end
