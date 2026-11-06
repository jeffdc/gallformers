defmodule GallformersWeb.ArticlesControllerTest do
  @moduledoc """
  The Articles list (`/articles`): Topics tabs (`?tag=`), each article's
  title, author, date, topics and preview.
  """
  use GallformersWeb.ConnCase

  alias Gallformers.Articles

  defp query(html, selector), do: html |> LazyHTML.from_document() |> LazyHTML.query(selector)
  defp text(html, selector), do: html |> query(selector) |> LazyHTML.text() |> String.trim()
  defp count(html, selector), do: html |> query(selector) |> Enum.count()

  # `inserted_at` (the list's order) is set after creating.
  defp create_article(attrs) do
    {inserted_at, attrs} = Map.pop(attrs, :inserted_at)

    {:ok, article} =
      Articles.create_article(
        Map.merge(
          %{
            title: "Rearing Galls",
            content: "Keep the **gall** cool.",
            author: "A. Kranz",
            is_published: true
          },
          attrs
        )
      )

    if inserted_at,
      do: Gallformers.Repo.update!(Ecto.Changeset.change(article, inserted_at: inserted_at)),
      else: article
  end

  test "lists the published articles, each linked with its preview", %{conn: conn} do
    article =
      create_article(%{slug: "rearing", tags: ["guide"], description: "How to rear inducers."})

    create_article(%{slug: "draft", title: "Draft piece", is_published: false})

    html = conn |> get(~p"/articles") |> html_response(200)

    assert text(html, "h1") == "Articles"
    assert count(html, ~s{a[href="/articles/#{article.slug}"] h2}) == 1
    assert html =~ "How to rear inducers."
    assert html =~ "A. Kranz"
    refute html =~ "Draft piece"
  end

  test "the newest article is featured; a topic shows only cards", %{conn: conn} do
    create_article(%{
      slug: "older",
      title: "Older piece",
      tags: ["guide"],
      inserted_at: ~N[2099-01-01 00:00:00]
    })

    create_article(%{
      slug: "newer",
      title: "Newer piece",
      tags: ["guide"],
      inserted_at: ~N[2099-06-01 00:00:00]
    })

    html = conn |> get(~p"/articles") |> html_response(200)
    assert text(html, "a[data-layout=featured] h2") == "Newer piece"
    assert count(html, ~s{a[data-layout=card][href="/articles/older"]}) == 1

    html = conn |> get(~p"/articles?tag=guide") |> html_response(200)
    assert count(html, "a[data-layout=featured]") == 0
    assert count(html, ~s{a[data-layout=card][href="/articles/newer"]}) == 1
    assert count(html, ~s{a[data-layout=card][href="/articles/older"]}) == 1
  end

  test "a card is tinted by its first topic", %{conn: conn} do
    create_article(%{slug: "faq", title: "FAQ", tags: ["faq", "taxonomy"]})
    create_article(%{slug: "untagged", title: "Untagged", inserted_at: ~N[2020-01-01 00:00:00]})

    html = conn |> get(~p"/articles") |> html_response(200)

    assert html
           |> query(~s{a[href="/articles/faq"] [data-part=band]})
           |> LazyHTML.attribute("data-tone") == ["autumn"]

    assert html
           |> query(~s{a[href="/articles/untagged"] [data-part=band]})
           |> LazyHTML.attribute("data-tone") == ["plain"]
  end

  test "a preview drops Markdown's list markers", %{conn: conn} do
    create_article(%{
      slug: "patrons",
      content: "Oak tier:\n\n- Madeleine Doney\n- Joshua Newbend"
    })

    html = conn |> get(~p"/articles") |> html_response(200)

    assert text(html, ~s{a[href="/articles/patrons"] [data-part=preview]}) ==
             "Oak tier: Madeleine Doney Joshua Newbend"
  end

  test "More to read links the keys, the glossary and the filter guide", %{conn: conn} do
    html = conn |> get(~p"/articles") |> html_response(200)

    for href <- ~w(/keys /glossary /filterguide) do
      assert count(html, ~s{#more-to-read a[href="#{href}"]}) == 1
    end
  end

  test "Topics chips filter by tag, marking the current one", %{conn: conn} do
    create_article(%{slug: "rearing", tags: ["guide"]})
    create_article(%{slug: "faq", title: "FAQ", tags: ["faq"]})

    html = conn |> get(~p"/articles?tag=guide") |> html_response(200)

    assert text(html, ~s{nav[aria-label="Topics"] a[aria-current="page"]}) =~ "guide"
    assert count(html, ~s{nav[aria-label="Topics"] a[href="/articles"]}) == 1
    assert count(html, ~s{a[href="/articles/rearing"]}) == 1
    assert count(html, ~s{a[href="/articles/faq"]}) == 0
  end

  test "a topic with no articles says so", %{conn: conn} do
    html = conn |> get(~p"/articles?tag=nonexistent") |> html_response(200)
    assert text(html, "[data-part=title]") == "No articles about nonexistent"
  end

  test "sets page metadata", %{conn: conn} do
    conn = get(conn, ~p"/articles")

    assert conn.assigns.page_title == "Articles"
    assert conn.assigns.page_url == "/articles"
  end

  test "an admin gets an edit link for each article", %{conn: conn} do
    article = create_article(%{slug: "rearing"})
    {admin_conn, _user} = GallformersWeb.AdminLiveHelpers.log_in_admin(conn)

    html = admin_conn |> get(~p"/articles") |> html_response(200)

    assert count(html, ~s{a[href="/admin/articles/#{article.id}"][title="Edit in admin"]}) == 1
  end
end
