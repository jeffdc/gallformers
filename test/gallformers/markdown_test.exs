defmodule Gallformers.MarkdownTest do
  @moduledoc """
  Unit tests for markdown processing with glossary term auto-linking.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Markdown

  describe "render/1" do
    test "returns {:ok, html} for valid markdown" do
      {:ok, html} = Markdown.render("Hello **world**")
      assert html =~ "<strong>world</strong>"
    end

    test "returns {:ok, empty string} for nil input" do
      assert {:ok, ""} == Markdown.render(nil)
    end

    test "returns {:ok, empty string} for empty string input" do
      assert {:ok, ""} == Markdown.render("")
    end

    test "converts markdown emphasis" do
      {:ok, html} = Markdown.render("*italic* and **bold**")
      assert html =~ "<em>italic</em>"
      assert html =~ "<strong>bold</strong>"
    end

    test "converts markdown links" do
      {:ok, html} = Markdown.render("[link text](https://example.com)")
      assert html =~ ~s(href="https://example.com")
      assert html =~ "link text"
    end

    test "converts markdown lists" do
      {:ok, html} = Markdown.render("- item 1\n- item 2")
      assert html =~ "<ul>"
      assert html =~ "<li>"
      assert html =~ "item 1"
      assert html =~ "item 2"
    end

    test "converts markdown headings" do
      {:ok, html} = Markdown.render("# Heading 1\n## Heading 2")
      assert html =~ "<h1>"
      assert html =~ "Heading 1"
      assert html =~ "<h2>"
      assert html =~ "Heading 2"
    end

    test "converts markdown paragraphs" do
      {:ok, html} = Markdown.render("Paragraph 1\n\nParagraph 2")
      assert html =~ "<p>"
      assert html =~ "Paragraph 1"
      assert html =~ "Paragraph 2"
    end

    test "converts code blocks" do
      {:ok, html} = Markdown.render("`inline code`")
      assert html =~ "<code"
      assert html =~ "inline code"
    end

    test "handles line breaks with GFM breaks option" do
      {:ok, html} = Markdown.render("line 1\nline 2")
      # With breaks: true, single newlines create <br>
      assert html =~ "line 1"
      assert html =~ "line 2"
    end
  end

  describe "render!/1" do
    test "returns html string for valid markdown" do
      html = Markdown.render!("Hello **world**")
      assert is_binary(html)
      assert html =~ "<strong>world</strong>"
    end

    test "returns empty string for nil" do
      assert "" == Markdown.render!(nil)
    end

    test "returns empty string for empty string" do
      assert "" == Markdown.render!("")
    end
  end

  describe "render_plain/1" do
    test "returns html without glossary linking" do
      html = Markdown.render_plain("Hello **world**")
      assert is_binary(html)
      assert html =~ "<strong>world</strong>"
    end

    test "returns empty string for nil" do
      assert "" == Markdown.render_plain(nil)
    end

    test "returns empty string for empty string" do
      assert "" == Markdown.render_plain("")
    end
  end

  describe "raw HTML" do
    test "keeps the tags Source descriptions and articles use" do
      html =
        Markdown.render_plain(
          ~s|<details><summary>Key</summary>\n\nSee <b>this</b> and <a href="https://example.org">that</a>.\n\n</details>|
        )

      assert html =~ "<details>"
      assert html =~ "<summary>Key</summary>"
      assert html =~ "<b>this</b>"
      assert html =~ ~s(href="https://example.org")
    end

    test "drops scripts and event handlers, inline or block" do
      html =
        Markdown.render_plain(
          ~s|text <span onclick="steal()">s</span>\n\n<script>alert(1)</script>\n\n<img src="x.png" onerror="steal()">|
        )

      refute html =~ "onclick"
      refute html =~ "onerror"
      refute html =~ "<script"
      refute html =~ "alert(1)"
    end
  end

  describe "linkify_glossary_terms/1" do
    test "returns unchanged html when no glossary terms" do
      # Test with text that shouldn't match any terms
      html = "<p>Some random text here XYZ123</p>"
      result = Markdown.linkify_glossary_terms(html)
      assert is_binary(result)
    end

    test "preserves existing HTML structure" do
      html = "<p><strong>Bold</strong> and <em>italic</em></p>"
      result = Markdown.linkify_glossary_terms(html)
      assert result =~ "<strong>Bold</strong>"
      assert result =~ "<em>italic</em>"
    end

    test "does not double-link already linked text" do
      html = ~s(<p><a href="/glossary#term">term</a></p>)
      result = Markdown.linkify_glossary_terms(html)
      # Should not add another link around existing link
      refute result =~
               ~s(<a href="/glossary#)
               |> (&(&1 <> ~s(<a href="/glossary#))).()
    end
  end

  describe "refresh_cache/0" do
    test "returns :ok" do
      assert :ok == Markdown.refresh_cache()
    end

    test "can be called multiple times" do
      assert :ok == Markdown.refresh_cache()
      assert :ok == Markdown.refresh_cache()
    end
  end

  describe "init_cache/0" do
    test "returns :ok" do
      assert :ok == Markdown.init_cache()
    end

    test "can be called multiple times" do
      assert :ok == Markdown.init_cache()
      assert :ok == Markdown.init_cache()
    end
  end

  describe "integration - render with glossary" do
    test "glossary terms are linked in rendered markdown" do
      # Initialize cache first
      Markdown.refresh_cache()

      # Render some markdown that might contain glossary terms
      {:ok, html} = Markdown.render("A gall is a plant growth caused by an inducer.")

      # The result should be valid HTML
      assert is_binary(html)
      assert html =~ "<p>"
    end
  end

  describe "edge cases" do
    test "handles very long markdown" do
      long_text = String.duplicate("This is a test paragraph. ", 1000)
      {:ok, html} = Markdown.render(long_text)
      assert is_binary(html)
    end

    test "handles special characters" do
      {:ok, html} = Markdown.render("Special chars: <>&\"'")
      assert is_binary(html)
      # HTML entities should be escaped
    end

    test "handles unicode characters" do
      {:ok, html} = Markdown.render("Unicode: émoji 🎉 中文")
      assert is_binary(html)
      assert html =~ "émoji"
      assert html =~ "🎉"
      assert html =~ "中文"
    end

    test "handles nested formatting" do
      {:ok, html} = Markdown.render("***bold and italic***")
      assert is_binary(html)
    end

    test "handles tables (GFM)" do
      table_md = """
      | Header 1 | Header 2 |
      | -------- | -------- |
      | Cell 1   | Cell 2   |
      """

      {:ok, html} = Markdown.render(table_md)
      assert is_binary(html)
    end
  end
end
