defmodule GallformersWeb.Admin.TaxonomyFormTest do
  @moduledoc """
  LiveView tests for the taxonomy admin form, focused on the parent field typeahead.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Taxonomy.Tree

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

  describe "section parent field uses typeahead" do
    setup %{conn: conn} do
      conn = setup_admin_session(conn)

      # Create a section to edit (seed data has FamilyAlpha id:20, GenusAlpha id:10)
      {:ok, section} =
        Tree.create_taxonomy(%{
          name: "TestSection",
          type: "section",
          parent_id: 10
        })

      {:ok, conn: conn, section: section}
    end

    test "renders typeahead for section parent instead of select dropdown", %{
      conn: conn,
      section: section
    } do
      {:ok, view, html} = live(conn, ~p"/admin/taxonomy/#{section.id}")

      # Should have the typeahead component, not a select dropdown
      assert has_element?(view, "#parent-picker")
      refute html =~ ~s(<select name="taxonomy[parent_id]")

      # Should show GenusAlpha as the selected parent
      assert html =~ "GenusAlpha"
    end

    test "section parent typeahead searches genera", %{conn: conn, section: section} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{section.id}")

      # Clear the current selection first
      view |> element("#parent-picker [aria-label=\"Clear selection\"]") |> render_click()

      # Search for a genus
      html =
        view
        |> element("#parent-picker")
        |> render_hook("search_parent", %{"value" => "GenusAlpha"})

      assert html =~ "GenusAlpha"
    end
  end
end
