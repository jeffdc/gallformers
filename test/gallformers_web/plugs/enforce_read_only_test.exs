defmodule GallformersWeb.Plugs.EnforceReadOnlyTest do
  @moduledoc """
  Tests for the EnforceReadOnly plug.
  """
  # async: false — tests write to persistent_term (global, not sandbox-isolated).
  # Running async would leak read_only: true to concurrent admin tests.
  use GallformersWeb.ConnCase, async: false

  alias Gallformers.Accounts.Auth0User
  alias GallformersWeb.Plugs.EnforceReadOnly

  # Tests write read_only directly to persistent_term rather than via
  # SiteSettings.set/2, which also writes the DB and broadcasts. ConnCase
  # clears the cache before and after each sync test.

  defp admin_conn(conn) do
    user = %Auth0User{
      id: "auth0|admin",
      email: "admin@test.com",
      name: "Admin User",
      nickname: "admin",
      picture: nil,
      roles: ["admin"]
    }

    conn
    |> init_test_session(%{})
    |> put_session(:current_user, user)
    |> put_session(:db_display_name, "Admin User")
    |> Map.put(:path_info, ["admin", "galls"])
  end

  describe "EnforceReadOnly plug" do
    test "passes through when read-only mode is off", %{conn: conn} do
      conn =
        conn
        |> admin_conn()
        |> EnforceReadOnly.call([])

      refute conn.halted
    end

    test "halts with 503 when read-only mode is on", %{conn: conn} do
      :persistent_term.put({Gallformers.SiteSettings, :cache}, %{"read_only" => true})

      conn =
        conn
        |> admin_conn()
        |> EnforceReadOnly.call([])

      assert conn.halted != nil
      assert conn.status == 503
      assert conn.resp_body =~ "Site Maintenance"
      assert conn.resp_body =~ "read-only mode"
    end

    test "exempts /admin/ops when read-only mode is on", %{conn: conn} do
      :persistent_term.put({Gallformers.SiteSettings, :cache}, %{"read_only" => true})

      conn =
        conn
        |> admin_conn()
        |> Map.put(:path_info, ["admin", "ops"])
        |> EnforceReadOnly.call([])

      refute conn.halted
    end

    test "exempts /admin/ops subpaths when read-only mode is on", %{conn: conn} do
      :persistent_term.put({Gallformers.SiteSettings, :cache}, %{"read_only" => true})

      conn =
        conn
        |> admin_conn()
        |> Map.put(:path_info, ["admin", "ops", "settings"])
        |> EnforceReadOnly.call([])

      refute conn.halted
    end
  end
end
