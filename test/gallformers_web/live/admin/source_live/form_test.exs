defmodule GallformersWeb.Admin.SourceLive.FormTest do
  @moduledoc """
  LiveView tests for the SourceLive.Form admin page.

  Tests the source form admin functionality including:
  - Mount/render in new and edit modes
  - Form validation and submission
  - Navigation after create (should go to edit page, not list)
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Sources

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

  defp create_source! do
    {:ok, source} =
      Sources.create_source(%{
        title: "Destructive delete source",
        author: "Test Author",
        pubyear: "2026",
        link: "https://example.com/source",
        citation: "Test Author. Destructive delete source. 2026.",
        license: "CC-BY",
        licenselink: "https://creativecommons.org/licenses/by/4.0/"
      })

    source
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
      assert html =~ "Editing"
      assert html =~ "Test Source Title"
      assert html =~ "Test Author"
    end
  end

  describe "dangerous delete confirmation" do
    setup %{conn: conn} do
      {:ok, conn: setup_admin_session(conn)}
    end

    test "edit view requires the exact source title before deletion", %{conn: conn} do
      source = create_source!()
      {:ok, view, _html} = live(conn, ~p"/admin/sources/#{source.id}")

      render_click(view, "delete")

      assert has_element?(view, "#dangerous-delete-modal", source.title)
      assert Sources.get_source(source.id) != nil

      html = render_submit(view, "confirm_delete", %{"confirmation" => "wrong title"})

      assert html =~ "Title does not match"
      assert Sources.get_source(source.id) != nil

      render_submit(view, "confirm_delete", %{"confirmation" => source.title})

      assert_redirect(view, "/admin/sources")
      refute Sources.get_source(source.id)
    end

    test "index view requires the exact source title before deletion", %{conn: conn} do
      source = create_source!()
      {:ok, view, _html} = live(conn, ~p"/admin/sources")

      render_click(view, "delete", %{"id" => Integer.to_string(source.id)})

      assert has_element?(view, "#dangerous-delete-modal", source.title)
      assert Sources.get_source(source.id) != nil

      html = render_submit(view, "confirm_delete", %{"confirmation" => "wrong title"})

      assert html =~ "Title does not match"
      assert Sources.get_source(source.id) != nil

      render_submit(view, "confirm_delete", %{"confirmation" => source.title})

      refute Sources.get_source(source.id)
    end
  end
end
