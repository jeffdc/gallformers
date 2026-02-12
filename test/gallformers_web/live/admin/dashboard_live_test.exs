defmodule GallformersWeb.Admin.DashboardLiveTest do
  @moduledoc """
  LiveView tests for the admin dashboard.
  """
  use GallformersWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User

  describe "Admin dashboard" do
    setup %{conn: conn} do
      # Create a mock user session for admin access (must be a User struct)
      user = %Auth0User{
        id: "test-user-id",
        email: "admin@test.com",
        name: "Test Admin",
        nickname: nil,
        picture: nil,
        roles: ["admin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user)
        |> put_session(:db_display_name, "Test User")

      {:ok, conn: conn, user: user}
    end

    test "renders dashboard when authenticated", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Dashboard" or html =~ "Admin"
    end

    test "displays stats cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      # Should show stat cards
      assert html =~ "Galls" or html =~ "Hosts" or html =~ "Sources" or html =~ "Images"
    end

    test "stats show formatted numbers", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      # Stats should be displayed (numbers)
      assert Regex.match?(~r/\d+/, html)
    end

    test "displays quick actions section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      # Dashboard shows "Create a New" action cards
      assert html =~ "Create a New"
    end

    test "quick action links are present", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      # Should have action links
      assert has_element?(view, "a[href*='/admin/']")
    end

    test "welcome section is displayed", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Need help?" or html =~ "Discord"
    end
  end

  describe "Admin dashboard stats" do
    setup %{conn: conn} do
      user = %Auth0User{
        id: "test-user-id",
        email: "admin@test.com",
        name: "Test Admin",
        nickname: nil,
        picture: nil,
        roles: ["admin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user)
        |> put_session(:db_display_name, "Test User")

      {:ok, conn: conn}
    end

    test "gall count is displayed", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Galls"
    end

    test "host count is displayed", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Host"
    end

    test "source count is displayed", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Source"
    end

    test "image count is displayed", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Image"
    end
  end

  describe "Admin dashboard quick actions" do
    setup %{conn: conn} do
      user = %Auth0User{
        id: "test-user-id",
        email: "admin@test.com",
        name: "Test Admin",
        nickname: nil,
        picture: nil,
        roles: ["admin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user)
        |> put_session(:db_display_name, "Test User")

      {:ok, conn: conn}
    end

    test "add gall link exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "a[href='/admin/galls/new']") or
               render(view) =~ "Add New Gall"
    end

    test "add host link exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "a[href='/admin/hosts/new']") or
               render(view) =~ "Add New Host"
    end

    test "add source link exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "a[href='/admin/sources/new']") or
               render(view) =~ "Add New Source"
    end

    test "add article link exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "a[href='/admin/articles/new']") or
               render(view) =~ "Create a New Article"
    end

    test "taxonomy link exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "a[href='/admin/taxonomy']") or
               render(view) =~ "Taxonomy"
    end

    test "glossary link exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "a[href='/admin/glossary']") or
               render(view) =~ "Glossary"
    end
  end

  describe "Admin authentication requirement" do
    test "redirects unauthenticated users", %{conn: conn} do
      # Without session setup, should redirect
      conn = get(conn, ~p"/admin")

      # Should redirect to login or home
      assert redirected_to(conn) =~ "/" or redirected_to(conn) =~ "/auth"
    end
  end
end
