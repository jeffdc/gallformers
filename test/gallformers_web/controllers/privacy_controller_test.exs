defmodule GallformersWeb.PrivacyControllerTest do
  use GallformersWeb.ConnCase

  test "GET /privacy renders the privacy page", %{conn: conn} do
    conn = get(conn, ~p"/privacy")

    assert html_response(conn, 200) =~ "Privacy Policy"
    assert html_response(conn, 200) =~ "Privacy-Protecting Analytics"
  end

  test "GET /privacy sets page metadata", %{conn: conn} do
    conn = get(conn, ~p"/privacy")

    assert conn.assigns.page_title == "Privacy"
    assert conn.assigns.page_url == "/privacy"
  end
end
