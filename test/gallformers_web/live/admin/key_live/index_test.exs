defmodule GallformersWeb.Admin.KeyLive.IndexTest do
  @moduledoc """
  The keys admin list (`/admin/keys`, design system matter bc0d), on the
  admin list pattern: every key linked to its edit page, with its slug,
  version, couplet count and public page; New key. Deleting is on the edit
  page (its danger panel).

  Not async: admin access reads the site settings (persistent_term).
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Keys

  @couplets %{
    "1" => %{
      "leads" => [
        %{
          "text" => "Wings fully developed.",
          "destination" => %{"type" => "couplet", "number" => "2"}
        },
        %{"text" => "Wings reduced or absent.", "destination" => nil}
      ]
    },
    "2" => %{
      "leads" => [
        %{"text" => "Black.", "destination" => nil},
        %{"text" => "Brown.", "destination" => nil}
      ]
    }
  }

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn)

    {:ok, key} =
      Keys.create_key(%{
        title: "Key to fixture galls",
        subtitle: "On test oaks",
        version: "2026-11-06",
        couplets: @couplets
      })

    %{conn: conn, key: key}
  end

  test "every key, linked to its edit page, with its couplets and public page", %{
    conn: conn,
    key: key
  } do
    {:ok, view, _html} = live(conn, ~p"/admin/keys")

    assert has_element?(view, "h1", "Keys")
    assert has_element?(view, "a[href='/admin/keys/new']", "New key")

    assert has_element?(
             view,
             "#keys-#{key.id} a[href='/admin/keys/#{key.id}']",
             "Key to fixture galls"
           )

    assert has_element?(view, "#keys-#{key.id}", "On test oaks")
    assert has_element?(view, "#keys-#{key.id} [data-couplets]", "2")
    assert has_element?(view, "#keys-#{key.id} a[href='/keys/#{key.slug}']", "View")
  end

  test "no Delete in the list: it is on the edit page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/keys")

    refute has_element?(view, "#keys [phx-click=delete]")
  end
end
