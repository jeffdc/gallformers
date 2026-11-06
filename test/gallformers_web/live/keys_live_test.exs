defmodule GallformersWeb.KeysLiveTest do
  @moduledoc """
  The keys list (`/keys`): each key's title linked, its scope, couplet
  count and description.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  # Reads the seeds' oak parasite key.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  test "lists each key, linked, with its scope and couplet count", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/keys")

    assert has_element?(view, "h1", "Identification keys")
    assert has_element?(view, "h2 a[href='/keys/oak-parasite-key']", "parasitic wasps")
    assert has_element?(view, "li", "Hymenoptera: Cynipini · 4 couplets")
    assert page_title(view) =~ "Identification Keys"
  end
end
