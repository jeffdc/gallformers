defmodule GallformersWeb.Admin.SectionLiveTest do
  @moduledoc """
  Tests for the admin section pages after consolidation under taxonomy.

  Sections are now created/edited via the taxonomy form. The section admin page
  shows a typeahead picker at `/admin/section` and species mapping at `/admin/section/:id`.
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

  defp create_section(_context) do
    {:ok, section} =
      Tree.create_taxonomy(%{
        name: "TestSection",
        type: "section",
        description: "Test Oaks",
        parent_id: 10
      })

    Gallformers.Taxonomy.update_section_species(section.id, [6])

    %{section: section}
  end

  describe "section picker (/admin/section)" do
    setup %{conn: conn} do
      Map.merge(create_section(%{}), %{conn: setup_admin_session(conn)})
    end

    test "shows typeahead for section selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/section")

      assert has_element?(view, "#section-picker")
    end

    test "does not show a table or list of sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/section")

      refute html =~ "<table"
    end

    test "does not show New Section button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/section")

      refute html =~ "New Section"
    end

    test "search returns matching sections", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/section")

      # Simulate the hook's search event with the correct payload shape
      render_hook(view, "search_section", %{"value" => "TestSection"})
      html = render(view)

      assert html =~ "TestSection"
    end

    test "selecting a section navigates to species mapping", %{conn: conn, section: section} do
      {:ok, view, _html} = live(conn, ~p"/admin/section")

      view |> element("#section-picker") |> render_hook("select_section", %{"id" => section.id})

      assert_redirect(view, ~p"/admin/section/#{section.id}")
    end
  end

  describe "species mapping (/admin/section/:id)" do
    setup %{conn: conn} do
      Map.merge(create_section(%{}), %{conn: setup_admin_session(conn)})
    end

    test "does not render name or description inputs", %{conn: conn, section: section} do
      {:ok, view, _html} = live(conn, ~p"/admin/section/#{section.id}")

      refute has_element?(view, ~s(input[name="taxonomy[name]"]))
      refute has_element?(view, ~s(input[name="taxonomy[description]"]))
    end

    test "does not render delete button", %{conn: conn, section: section} do
      {:ok, view, _html} = live(conn, ~p"/admin/section/#{section.id}")

      refute has_element?(view, "[phx-click='delete']")
    end

    test "has edit in taxonomy quick link", %{conn: conn, section: section} do
      {:ok, _view, html} = live(conn, ~p"/admin/section/#{section.id}")

      assert html =~ ~s(/admin/taxonomy/#{section.id})
      assert html =~ "Edit in taxonomy"
    end

    test "displays section name as read-only", %{conn: conn, section: section} do
      {:ok, _view, html} = live(conn, ~p"/admin/section/#{section.id}")

      assert html =~ section.name
    end

    test "shows species list", %{conn: conn, section: section} do
      {:ok, _view, html} = live(conn, ~p"/admin/section/#{section.id}")

      assert html =~ "Thymus alpinus"
    end

    test "species search works with keyup event payload", %{conn: conn, section: section} do
      {:ok, view, _html} = live(conn, ~p"/admin/section/#{section.id}")

      # phx-keyup sends %{"value" => ...}, not %{"query" => ...}
      html = render_keyup(view, "search_species", %{"value" => "Thymus"})

      assert html =~ "Thymus"
    end
  end
end
