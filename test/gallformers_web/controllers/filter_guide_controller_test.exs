defmodule GallformersWeb.FilterGuideControllerTest do
  use GallformersWeb.ConnCase

  test "GET /filterguide renders the filter guide page", %{conn: conn} do
    conn = get(conn, ~p"/filterguide")

    assert html_response(conn, 200) =~ "ID Tool Filter Guide"
    assert html_response(conn, 200) =~ "Alignment"
    assert html_response(conn, 200) =~ "Detachable"
  end

  test "GET /filterguide sets page metadata", %{conn: conn} do
    conn = get(conn, ~p"/filterguide")

    assert conn.assigns.page_title == "Filter Guide"
    assert conn.assigns.page_url == "/filterguide"
  end
end
