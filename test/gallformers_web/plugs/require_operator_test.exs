defmodule GallformersWeb.Plugs.RequireOperatorTest do
  @moduledoc """
  Tests for the RequireOperator plug.
  """
  use GallformersWeb.ConnCase, async: true

  alias Gallformers.Accounts.Auth0User
  alias GallformersWeb.Plugs.RequireOperator

  describe "RequireOperator plug" do
    test "redirects unauthenticated user to login", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> RequireOperator.call([])

      assert conn.halted
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "log in"
      assert redirected_to(conn) == "/auth/auth0"
    end

    test "returns 403 for authenticated non-operator user", %{conn: conn} do
      user = %Auth0User{
        id: "auth0|regular",
        email: "admin@test.com",
        name: "Admin User",
        nickname: "admin",
        picture: nil,
        roles: ["admin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user)
        |> put_session(:db_display_name, "Admin User")
        |> RequireOperator.call([])

      assert conn.halted
      assert conn.status == 403
    end

    test "passes through for authenticated operator user", %{conn: conn} do
      user = %Auth0User{
        id: "auth0|operator",
        email: "operator@test.com",
        name: "Operator User",
        nickname: "operator",
        picture: nil,
        roles: ["operator"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user)
        |> put_session(:db_display_name, "Operator User")
        |> RequireOperator.call([])

      refute conn.halted
      assert conn.assigns[:current_user] == user
    end
  end
end
