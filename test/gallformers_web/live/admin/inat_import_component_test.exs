defmodule GallformersWeb.Admin.InatImportComponentTest do
  @moduledoc """
  Tests for the iNaturalist import component on the Images admin page.
  """
  use GallformersWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User

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
      |> put_session(:db_display_name, "Test Admin")

    species =
      Gallformers.Repo.one!(from(s in Gallformers.Species.Species, limit: 1))

    {:ok, conn: conn, species: species}
  end

  describe "inat import component" do
    test "renders in upload section when species is selected", %{conn: conn, species: species} do
      {:ok, view, _html} = live(conn, ~p"/admin/images?species_id=#{species.id}")

      html = render(view)
      assert html =~ "Import from iNaturalist"
      assert has_element?(view, "[data-role=inat-url-input]")
      assert has_element?(view, "[data-role=inat-fetch-button]")
    end

    test "fetch button is disabled when input is empty", %{conn: conn, species: species} do
      {:ok, view, _html} = live(conn, ~p"/admin/images?species_id=#{species.id}")

      assert has_element?(view, "[data-role=inat-fetch-button][disabled]")
    end

    test "shows error for invalid input", %{conn: conn, species: species} do
      {:ok, view, _html} = live(conn, ~p"/admin/images?species_id=#{species.id}")

      view
      |> element("form[phx-submit=inat_fetch]")
      |> render_submit(%{url: "not-a-valid-url"})

      html = render(view)
      assert html =~ "valid iNaturalist observation URL"
    end

    test "does not render when no species is selected", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/images")

      refute html =~ "Import from iNaturalist"
    end
  end
end
