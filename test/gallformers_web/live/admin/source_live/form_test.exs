defmodule GallformersWeb.Admin.SourceLive.FormTest do
  @moduledoc """
  LiveView tests for the SourceLive.Form admin page.

  Tests the source form admin functionality including:
  - Mount/render in new and edit modes
  - Form validation and submission
  - Navigation after create (should go to edit page, not list)
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User

  # Helper to set up admin session
  defp setup_admin_session(conn) do
    user = %Auth0User{
      id: "test-admin-id",
      email: "admin@test.com",
      name: "Test Admin",
      nickname: nil,
      picture: nil,
      roles: ["admin"]
    }

    conn
    |> init_test_session(%{})
    |> put_session(:current_user, user)
    |> put_session(:db_display_name, "Test User")
  end

  describe "Create source navigation" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "creating a source navigates to edit page with new source data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sources/new")

      # Submit the form with valid source data
      result =
        view
        |> form("#source-form",
          source: %{
            title: "Test Source Title",
            author: "Test Author",
            pubyear: "2023",
            link: "https://example.com/test",
            license: "CC-BY",
            citation: "Test Author. \"Test Source Title.\" 2023.",
            datacomplete: "false"
          }
        )
        |> render_submit()

      # Follow the redirect
      {:ok, _redirected_view, html} = follow_redirect(result, conn)

      # Should show the edit page with the new source data (not the list page)
      # Current buggy behavior: shows "Sources" list page
      # Expected behavior: shows "Edit Source" page with the source data
      assert html =~ "Edit Source"
      assert html =~ "Test Source Title"
      assert html =~ "Test Author"
    end
  end
end
