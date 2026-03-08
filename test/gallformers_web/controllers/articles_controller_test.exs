defmodule GallformersWeb.ArticlesControllerTest do
  use GallformersWeb.ConnCase

  test "GET /articles renders the articles index", %{conn: conn} do
    conn = get(conn, ~p"/articles")

    assert html_response(conn, 200) =~ "Gallformers Articles"
    assert html_response(conn, 200) =~ "In-depth articles on gall biology"
  end

  test "GET /articles sets page metadata", %{conn: conn} do
    conn = get(conn, ~p"/articles")

    assert conn.assigns.page_title == "Articles"
    assert conn.assigns.page_url == "/articles"
  end

  test "GET /articles with tag param filters articles", %{conn: conn} do
    conn = get(conn, ~p"/articles?tag=biology")

    assert html_response(conn, 200) =~ "Gallformers Articles"
    assert conn.assigns.selected_tag == "biology"
  end

  test "GET /articles without tag param shows all articles", %{conn: conn} do
    conn = get(conn, ~p"/articles")

    assert conn.assigns.selected_tag == nil
  end

  test "GET /articles with nonexistent tag shows empty state", %{conn: conn} do
    conn = get(conn, ~p"/articles?tag=nonexistent")

    assert html_response(conn, 200) =~ "No articles found with tag"
  end
end
