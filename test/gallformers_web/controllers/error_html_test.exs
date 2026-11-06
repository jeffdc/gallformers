defmodule GallformersWeb.ErrorHTMLTest do
  use GallformersWeb.ConnCase

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  defp render(status, assigns \\ []),
    do: render_to_string(GallformersWeb.ErrorHTML, status, "html", assigns)

  defp with_referer(url),
    do: Plug.Conn.put_req_header(Phoenix.ConnTest.build_conn(), "referer", url)

  test "renders 404.html: not found, and not a gall either" do
    html = render("404")
    assert html =~ "404"
    assert html =~ "Page Not Found"
    assert html =~ "This Page Was Not Found"
    assert html =~ ~s(href="https://www.inaturalist.org/observations/58767231")
    assert html =~ ~s(href="/id")
  end

  test "renders 403.html" do
    html = render("403")
    assert html =~ "403"
    assert html =~ "Access Denied"
    refute html =~ ~s(href="/id")
  end

  test "renders 500.html" do
    html = render("500")
    assert html =~ "500"
    assert html =~ "Something went wrong"
  end

  test "each is a page of the design system: its stylesheet, the wordmark home, no inline styles" do
    for status <- ["403", "404", "500"] do
      html = render(status)
      assert html =~ ~s(href="/assets/css/app.css")
      assert html =~ ~s(aria-label="Gallformers home")
      refute html =~ "<style"
    end
  end

  test "Go Back links to the page the visitor came from, with no script" do
    for status <- ["403", "404", "500"] do
      html = render(status, conn: with_referer("https://gallformers.org/gall/821"))

      assert html =~ ~s(href="https://gallformers.org/gall/821"), status
      assert html =~ "Go Back"
      refute html =~ "javascript:"
    end
  end

  test "with no page to go back to, there is no Go Back" do
    for status <- ["403", "404", "500"] do
      html = render(status, conn: Phoenix.ConnTest.build_conn())
      refute html =~ "Go Back", status
      refute html =~ "javascript:"

      assert render(status) =~ "Go Home"
    end
  end

  test "a referer that isn't a web address gives no Go Back" do
    html = render("404", conn: with_referer("javascript:alert(1)"))

    refute html =~ "Go Back"
    refute html =~ "javascript:"
  end
end
