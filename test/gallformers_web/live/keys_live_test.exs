defmodule GallformersWeb.KeysLiveTest do
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "Keys index page" do
    test "page loads successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/keys")
      assert html =~ "Identification Keys"
    end

    test "displays available keys", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/keys")
      assert html =~ "parasitic wasps"
    end

    test "links to individual key pages", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/keys")
      assert html =~ "/keys/oak-parasite-key"
    end
  end
end
