defmodule GallformersWeb.Admin.KeyLive.FormContentImagesTest do
  @moduledoc """
  Tests for ContentImageManager integration in the key admin form.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Keys

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

  setup %{conn: conn} do
    {:ok, key} =
      Keys.create_key(%{
        title: "Content Images Test Key",
        slug: "content-images-test-key",
        version: "1.0",
        couplets: %{"1" => %{"leads" => [%{"text" => "lead A"}, %{"text" => "lead B"}]}}
      })

    {:ok, conn: setup_admin_session(conn), key: key}
  end

  describe "content image manager on key edit" do
    test "shows content image manager component", %{conn: conn, key: key} do
      {:ok, view, _html} = live(conn, ~p"/admin/keys/#{key.id}")

      assert has_element?(view, "[data-content-image-manager]")
    end

    test "does not show content image manager on new key", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/keys/new")

      refute has_element?(view, "[data-content-image-manager]")
    end
  end
end
