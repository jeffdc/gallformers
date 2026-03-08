defmodule GallformersWeb.KeysControllerTest do
  use GallformersWeb.ConnCase

  test "GET /keys renders the keys index page", %{conn: conn} do
    conn = get(conn, ~p"/keys")

    assert html_response(conn, 200) =~ "Identification Keys"
    assert html_response(conn, 200) =~ "parasitoids, inquilines"
  end

  test "GET /keys sets page metadata", %{conn: conn} do
    conn = get(conn, ~p"/keys")

    assert conn.assigns.page_title == "Identification Keys"
    assert conn.assigns.page_url == "/keys"
  end
end
