defmodule GallformersWeb.PrivacyControllerTest do
  use GallformersWeb.ConnCase

  test "GET /privacy renders the privacy page", %{conn: conn} do
    conn = get(conn, ~p"/privacy")

    html = html_response(conn, 200)
    doc = LazyHTML.from_document(html)

    assert doc |> LazyHTML.query("h1") |> LazyHTML.text() |> String.trim() == "Privacy Policy"

    assert doc |> LazyHTML.query(~s{.gf-prose[data-size="lg"] h2}) |> LazyHTML.text() =~
             "Privacy-Protecting Analytics"
  end

  test "GET /privacy sets page metadata", %{conn: conn} do
    conn = get(conn, ~p"/privacy")

    assert conn.assigns.page_title == "Privacy"
    assert conn.assigns.page_url == "/privacy"
  end
end
