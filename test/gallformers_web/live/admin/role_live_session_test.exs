defmodule GallformersWeb.Admin.RoleLiveSessionTest do
  @moduledoc """
  Live navigation into the role-restricted admin LiveViews.

  Plugs only run on HTTP requests, so live navigation from one admin LiveView
  to another skips the `:superadmin` / `:operator` pipelines. The
  role-restricted screens sit in live sessions of their own, so navigating
  into them from an admin screen falls back to a full HTTP request.
  """
  # async: false because admin access is gated by SiteSettings.read_only?/0,
  # which reads from persistent_term-backed global state.
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  # Cross-session navigation logs a "full page reload" warning.
  @moduletag :capture_log

  alias Gallformers.Accounts.Auth0User

  @superadmin_paths ["/admin/users", "/admin/filter-terms", "/admin/filter-terms/new"]
  @operator_paths ["/admin/ops"]

  defp conn_for(conn, roles) do
    user = %Auth0User{
      id: "auth0|role-live-session-#{System.unique_integer([:positive])}",
      email: "user@test.com",
      name: "Test User",
      nickname: "test",
      picture: nil,
      roles: roles
    }

    conn
    |> init_test_session(%{})
    |> put_session(:current_user, user)
    |> put_session(:db_display_name, "Test User")
  end

  # The on_mount hook is what checks the role when a LiveView mounts over the
  # socket; make sure every role-restricted route carries it.
  describe "role-restricted routes" do
    for {path, hook} <-
          Enum.map(@superadmin_paths, &{&1, :require_superadmin}) ++
            Enum.map(@operator_paths, &{&1, :require_operator}) do
      test "#{path} mounts through the #{hook} on_mount hook" do
        %{phoenix_live_view: {_view, _action, _opts, live_session}} =
          Phoenix.Router.route_info(GallformersWeb.Router, "GET", unquote(path), "localhost")

        hook_ids = Enum.map(live_session.extra.on_mount, & &1.id)
        assert {GallformersWeb.Live.UserAuth, unquote(hook)} in hook_ids
      end
    end
  end

  describe "an admin without the role" do
    setup %{conn: conn}, do: {:ok, conn: conn_for(conn, ["admin"])}

    for path <- @superadmin_paths ++ @operator_paths do
      test "can't live-navigate from the dashboard into #{path}", %{conn: conn} do
        {:ok, view, _html} = live(conn, ~p"/admin")

        # A full page load instead of a live mount: the request goes through
        # the role plugs.
        assert {:error, {:redirect, %{to: to}}} = live_redirect(view, to: unquote(path))
        assert URI.parse(to).path == unquote(path)
      end

      test "gets a 403 for #{path} over HTTP", %{conn: conn} do
        assert conn |> get(unquote(path)) |> html_response(403)
      end
    end
  end

  describe "a superadmin" do
    setup %{conn: conn}, do: {:ok, conn: conn_for(conn, ["superadmin"])}

    for path <- @superadmin_paths do
      test "reaches #{path} from the dashboard through a full page load", %{conn: conn} do
        {:ok, view, _html} = live(conn, ~p"/admin")

        assert {:ok, conn} =
                 view
                 |> live_redirect(to: unquote(path))
                 |> follow_redirect(conn)

        assert {:ok, _view, _html} = live(conn)
      end
    end

    test "live-navigates between the superadmin screens", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert {:ok, _view, html} = live_redirect(view, to: "/admin/filter-terms")
      assert html =~ "Filter Terms"
    end
  end

  describe "an operator" do
    setup %{conn: conn}, do: {:ok, conn: conn_for(conn, ["admin", "operator"])}

    test "reaches /admin/ops from the dashboard through a full page load", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert {:ok, conn} =
               view
               |> live_redirect(to: "/admin/ops")
               |> follow_redirect(conn)

      assert {:ok, _view, html} = live(conn)
      assert html =~ "Site Operations"
    end
  end
end
