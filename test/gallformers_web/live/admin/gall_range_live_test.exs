defmodule GallformersWeb.Admin.GallRangeLiveTest do
  @moduledoc """
  LiveView tests for the gall range review admin page.
  Disabled while the route is commented out — re-enable with the route.
  """
  use GallformersWeb.ConnCase
  @moduletag :skip
  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Galls

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

  describe "Gall Range Review page" do
    test "renders the page with unconfirmed galls", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gall-range")

      assert html =~ "Gall Range Review"
      assert html =~ "Needs Review"
    end

    test "shows gall names from seed data", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/gall-range")

      # Seed data has gall species at IDs 100, 101, 102
      assert html =~ "Andricus quercuscalifornicus"
      assert html =~ "Amphibolips confluenta"
    end

    test "toggle show_all includes confirmed galls", %{conn: conn} do
      # Confirm a gall first
      Galls.confirm_gall_range(100)

      {:ok, view, _html} = live(conn, ~p"/admin/gall-range")

      # Initially, gall 100 should not appear (it's confirmed)
      refute render(view) =~ "Confirmed"

      # Toggle show all
      view |> element("input[phx-click=toggle_show_all]") |> render_click()

      html = render(view)
      assert html =~ "Confirmed"
    end

    test "select and confirm a gall", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gall-range")

      # Select gall 100
      view |> element("input[phx-click=toggle_select][phx-value-id='100']") |> render_click()

      # Confirm selected
      view |> element("button", "Confirm Selected") |> render_click()

      # Verify flash message
      assert render(view) =~ "Confirmed range for 1 gall(s)"

      # Verify gall 100 is now confirmed in the database
      traits = Galls.get_gall_traits(100)
      assert traits.range_confirmed == true
    end

    test "select all and deselect all", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gall-range")

      # Click the header checkbox to select all
      view |> element("th input[type=checkbox]") |> render_click()

      html = render(view)
      assert html =~ "Confirm Selected"

      # Click deselect all
      view |> element("button", "Clear selection") |> render_click()

      html = render(view)
      refute html =~ "Confirm Selected"
    end

    test "shows error when confirming with nothing selected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gall-range")

      # The confirm button is only shown when something is selected,
      # so send the event directly
      view |> render_hook("confirm_selected", %{})

      assert render(view) =~ "No galls selected"
    end

    test "shows empty state when all confirmed", %{conn: conn} do
      # Confirm all seed galls
      galls = Galls.list_galls_for_range_review(unconfirmed_only: false)

      for gall <- galls do
        Galls.confirm_gall_range(gall.id)
      end

      {:ok, _view, html} = live(conn, ~p"/admin/gall-range")
      assert html =~ "All gall ranges confirmed!"
    end

    test "gall name links to gallhost page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gall-range")

      assert has_element?(view, "a[href*='/admin/gallhost?id=100']")
    end

    test "back link navigates to admin dashboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/gall-range")

      assert has_element?(view, "a[href='/admin']")
    end
  end

  describe "authentication" do
    test "redirects unauthenticated users", %{conn: _conn} do
      conn = Phoenix.ConnTest.build_conn()
      conn = get(conn, ~p"/admin/gall-range")

      assert redirected_to(conn) =~ "/"
    end
  end
end
