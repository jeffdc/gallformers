defmodule GallformersWeb.Admin.KeyLive.FormTest do
  @moduledoc """
  Tests for saving key metadata from the admin form.

  `authors` and `couplets` have no inputs of their own in the form, so they are
  only persisted if the save handler merges them in from the JSON textarea.
  """
  use GallformersWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Keys

  @couplets %{
    "1" => %{
      "leads" => [
        %{"text" => "Wings fully developed.", "destination" => nil},
        %{"text" => "Wings reduced or absent.", "destination" => nil}
      ]
    }
  }

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

  defp key_json(attrs) do
    Map.merge(
      %{
        "title" => "Key to parasitic wasps",
        "slug" => "key-to-parasitic-wasps",
        "version" => "2026-02-05",
        "couplets" => @couplets
      },
      attrs
    )
    |> Jason.encode!()
  end

  setup %{conn: conn} do
    {:ok, conn: setup_admin_session(conn)}
  end

  describe "authors" do
    test "are persisted when editing an existing key", %{conn: conn} do
      {:ok, key} =
        Keys.create_key(%{
          title: "Key to parasitic wasps",
          slug: "key-to-parasitic-wasps",
          version: "2026-02-01",
          couplets: @couplets
        })

      assert key.authors == []

      json = key_json(%{"authors" => ["Louis Nastasi"]})

      {:ok, view, _html} = live(conn, ~p"/admin/keys/#{key.id}")

      capture_log(fn ->
        render_hook(view, "json_changed", %{"value" => json})
        view |> form("#key-form") |> render_submit()
      end)

      assert Keys.get_key!(key.id).authors == ["Louis Nastasi"]
    end

    test "are persisted when creating a new key", %{conn: conn} do
      json = key_json(%{"authors" => ["Louis Nastasi"]})

      {:ok, view, _html} = live(conn, ~p"/admin/keys/new")

      capture_log(fn ->
        render_hook(view, "json_changed", %{"value" => json})
        view |> form("#key-form") |> render_submit()
      end)

      assert {:ok, %{authors: ["Louis Nastasi"]}} = Keys.get_key("key-to-parasitic-wasps")
    end

    test "survive a save that does not touch the JSON textarea", %{conn: conn} do
      {:ok, key} =
        Keys.create_key(%{
          title: "Key to parasitic wasps",
          slug: "key-to-parasitic-wasps",
          version: "2026-02-01",
          authors: ["Louis Nastasi"],
          couplets: @couplets
        })

      {:ok, view, _html} = live(conn, ~p"/admin/keys/#{key.id}")

      capture_log(fn ->
        view |> form("#key-form", key: %{subtitle: "Hymenoptera: Cynipini"}) |> render_submit()
      end)

      reloaded = Keys.get_key!(key.id)
      assert reloaded.authors == ["Louis Nastasi"]
      assert reloaded.subtitle == "Hymenoptera: Cynipini"
    end

    test "are cleared when removed from the JSON", %{conn: conn} do
      {:ok, key} =
        Keys.create_key(%{
          title: "Key to parasitic wasps",
          slug: "key-to-parasitic-wasps",
          version: "2026-02-01",
          authors: ["Louis Nastasi"],
          couplets: @couplets
        })

      {:ok, view, _html} = live(conn, ~p"/admin/keys/#{key.id}")

      json = key_json(%{"authors" => []})

      capture_log(fn ->
        render_hook(view, "json_changed", %{"value" => json})
        view |> form("#key-form") |> render_submit()
      end)

      assert Keys.get_key!(key.id).authors == []
    end
  end

  describe "couplets" do
    test "are still persisted from the JSON textarea", %{conn: conn} do
      {:ok, key} =
        Keys.create_key(%{
          title: "Key to parasitic wasps",
          slug: "key-to-parasitic-wasps",
          version: "2026-02-01",
          couplets: @couplets
        })

      updated_couplets =
        Map.put(@couplets, "2", %{
          "leads" => [
            %{"text" => "Metafemur toothed.", "destination" => nil},
            %{"text" => "Metafemur not toothed.", "destination" => nil}
          ]
        })

      json = key_json(%{"couplets" => updated_couplets})

      {:ok, view, _html} = live(conn, ~p"/admin/keys/#{key.id}")

      capture_log(fn ->
        render_hook(view, "json_changed", %{"value" => json})
        view |> form("#key-form") |> render_submit()
      end)

      assert map_size(Keys.get_key!(key.id).couplets) == 2
    end
  end
end
