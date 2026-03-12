defmodule GallformersWeb.Admin.OpsLiveTest do
  @moduledoc """
  LiveView tests for the operator ops admin page.
  """
  # async: false because tests modify SiteSettings via persistent_term (global state).
  # Running async would poison concurrent admin tests with read_only mode.
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User

  setup do
    :persistent_term.put({Gallformers.SiteSettings, :cache}, %{})
    on_exit(fn -> :persistent_term.put({Gallformers.SiteSettings, :cache}, %{}) end)
  end

  defp operator_conn(conn) do
    user = %Auth0User{
      id: "auth0|operator-test",
      email: "operator@test.com",
      name: "Operator User",
      nickname: "operator",
      picture: nil,
      roles: ["operator"]
    }

    conn
    |> init_test_session(%{})
    |> put_session(:current_user, user)
    |> put_session(:db_display_name, "Operator User")
  end

  describe "Ops page - operator access" do
    test "operator can access the page", %{conn: conn} do
      {:ok, _view, html} = live(operator_conn(conn), ~p"/admin/ops")

      assert html =~ "Site Operations"
    end

    test "shows banner enabled toggle", %{conn: conn} do
      {:ok, view, _html} = live(operator_conn(conn), ~p"/admin/ops")

      assert has_element?(view, "#banner-enabled")
    end

    test "shows banner text input", %{conn: conn} do
      {:ok, view, _html} = live(operator_conn(conn), ~p"/admin/ops")

      assert has_element?(view, "#banner-text")
    end

    test "shows read-only toggle", %{conn: conn} do
      {:ok, view, _html} = live(operator_conn(conn), ~p"/admin/ops")

      assert has_element?(view, "#read-only")
    end

    test "shows current settings state", %{conn: conn} do
      Gallformers.SiteSettings.set("banner_enabled", true)
      Gallformers.SiteSettings.set("banner_text", "Maintenance in progress")

      {:ok, _view, html} = live(operator_conn(conn), ~p"/admin/ops")

      assert html =~ "Maintenance in progress"
    end

    test "toggling banner_enabled updates the setting", %{conn: conn} do
      {:ok, view, _html} = live(operator_conn(conn), ~p"/admin/ops")

      # Toggle banner on
      view
      |> element("#banner-enabled")
      |> render_click()

      assert Gallformers.SiteSettings.banner_enabled?() == true
    end

    test "toggling banner_enabled off updates the setting", %{conn: conn} do
      Gallformers.SiteSettings.set("banner_enabled", true)

      {:ok, view, _html} = live(operator_conn(conn), ~p"/admin/ops")

      # Toggle banner off (the hidden input sends "false" when unchecked)
      view
      |> element("#banner-enabled")
      |> render_click()

      assert Gallformers.SiteSettings.banner_enabled?() == false
    end

    test "setting banner text updates the setting", %{conn: conn} do
      {:ok, view, _html} = live(operator_conn(conn), ~p"/admin/ops")

      view
      |> form("#banner-text-form", %{"banner_text" => "Planned outage tonight"})
      |> render_submit()

      assert Gallformers.SiteSettings.banner_text() == "Planned outage tonight"
    end

    test "toggling read_only updates the setting", %{conn: conn} do
      {:ok, view, _html} = live(operator_conn(conn), ~p"/admin/ops")

      view
      |> element("#read-only")
      |> render_click()

      assert Gallformers.SiteSettings.read_only?() == true

      # Reset immediately to avoid poisoning concurrent async tests via persistent_term
      :persistent_term.put({Gallformers.SiteSettings, :cache}, %{})
    end
  end

  describe "Ops page - access control" do
    test "redirects unauthenticated users", %{conn: conn} do
      conn = get(conn, ~p"/admin/ops")

      assert redirected_to(conn) =~ "/auth"
    end

    test "returns 403 for regular admin users", %{conn: conn} do
      admin = %Auth0User{
        id: "auth0|admin-test",
        email: "admin@test.com",
        name: "Admin User",
        nickname: "admin",
        picture: nil,
        roles: ["admin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, admin)
        |> put_session(:db_display_name, "Admin User")

      conn = get(conn, ~p"/admin/ops")
      assert conn.status == 403
    end
  end
end
