defmodule GallformersWeb.Plugs.EnforceReadOnlyTest do
  @moduledoc """
  Tests for the EnforceReadOnly plug.
  """
  # async: false — SiteSettings.set writes to persistent_term (global, not sandbox-isolated).
  # Running async would leak read_only: true to concurrent admin tests.
  use GallformersWeb.ConnCase, async: false

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.SiteSettings
  alias GallformersWeb.Plugs.EnforceReadOnly

  # Reset the persistent_term cache before each test so we start from a clean
  # state. The Ecto sandbox rolls back DB changes, but persistent_term is global.
  setup do
    cache_key = {Gallformers.SiteSettings, :cache}
    previous = :persistent_term.get(cache_key, %{})
    :persistent_term.put(cache_key, %{})
    on_exit(fn -> :persistent_term.put(cache_key, previous) end)
    :ok
  end

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
      SiteSettings.set("read_only", true)

      conn =
        conn
        |> admin_conn()
        |> EnforceReadOnly.call([])

      assert conn.halted
      assert conn.status == 503
      assert conn.resp_body =~ "Site Maintenance"
      assert conn.resp_body =~ "read-only mode"
    end

    test "exempts /admin/ops when read-only mode is on", %{conn: conn} do
      SiteSettings.set("read_only", true)

      conn =
        conn
        |> admin_conn()
        |> Map.put(:path_info, ["admin", "ops"])
        |> EnforceReadOnly.call([])

      refute conn.halted
    end

    test "exempts /admin/ops subpaths when read-only mode is on", %{conn: conn} do
      SiteSettings.set("read_only", true)

      conn =
        conn
        |> admin_conn()
        |> Map.put(:path_info, ["admin", "ops", "settings"])
        |> EnforceReadOnly.call([])

      refute conn.halted
    end
  end
end
