defmodule GallformersWeb.PageComponentsTest do
  @moduledoc """
  The design system's page structure: page_header, section, panel, rail
  (docs/design-system/components.md).
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]
  import GallformersWeb.PageComponents

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> query(selector) |> Enum.count()
  defp text(html, selector), do: html |> query(selector) |> LazyHTML.text() |> String.trim()

  describe "prose" do
    test "renders Markdown, at a size and in a face" do
      assigns = %{markdown: "## Field notes\n\nA *detachable* gall."}

      html =
        rendered_to_string(~H"""
        <.prose markdown={@markdown} size={:lg} font={:serif} />
        """)

      assert query(html, ".gf-prose") |> LazyHTML.attribute("data-size") == ["lg"]
      assert query(html, ".gf-prose") |> LazyHTML.attribute("data-font") == ["serif"]
      assert text(html, ".gf-prose h2") == "Field notes"
      assert text(html, ".gf-prose em") == "detachable"
    end

    test "wraps its own markup at the default size and face" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.prose class="mt-4">
          <h2>How it works</h2>
        </.prose>
        """)

      assert query(html, ".gf-prose.mt-4") |> LazyHTML.attribute("data-size") == ["base"]
      assert query(html, ".gf-prose") |> LazyHTML.attribute("data-font") == ["sans"]
      assert text(html, ".gf-prose h2") == "How it works"
    end

    test "no Markdown renders an empty block" do
      assigns = %{}
      html = rendered_to_string(~H|<.prose markdown={nil} />|)
      assert text(html, ".gf-prose") == ""
    end
  end

  describe "chip_nav" do
    test "links as chips, the current one marked as the page" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.chip_nav label="Topics">
          <:chip href="/articles" current>All</:chip>
          <:chip href="/articles?tag=faq" count={1}>faq</:chip>
        </.chip_nav>
        """)

      assert query(html, "nav") |> LazyHTML.attribute("aria-label") == ["Topics"]
      assert count(html, "nav a") == 2
      assert text(html, "a[aria-current=page]") == "All"
      assert text(html, "a[href='/articles?tag=faq'] [data-part=count]") == "1"
    end
  end

  describe "link_tile" do
    test "an icon, a name and a line, as one link" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.link_tile href="/keys" icon="ph-tree-structure" name="Identification keys">
          4 step-by-step keys
        </.link_tile>
        """)

      assert query(html, "a") |> LazyHTML.attribute("href") == ["/keys"]
      assert count(html, "a .ph-tree-structure") == 1
      assert text(html, "[data-part=name]") == "Identification keys"
      assert text(html, "[data-part=line]") == "4 step-by-step keys"
    end
  end

  describe "tab_nav" do
    test "links, the current one marked as the page" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.tab_nav label="Browse by">
          <:tab navigate="/galls" current>By what causes them</:tab>
          <:tab navigate="/hosts">By host plant</:tab>
        </.tab_nav>
        """)

      assert query(html, "nav") |> LazyHTML.attribute("aria-label") == ["Browse by"]
      assert count(html, "nav a") == 2
      assert text(html, "a[aria-current=page]") == "By what causes them"
      assert query(html, "a[aria-current=page]") |> LazyHTML.attribute("href") == ["/galls"]
    end
  end

  describe "page_header" do
    test "holds the page's one h1, with crumbs, chips, meta and actions" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.page_header>
          <:crumb navigate="/family/Cynipidae">Cynipidae</:crumb>
          <:crumb navigate="/genus/Callirhytis" italic>Callirhytis</:crumb>
          <:title name>Callirhytis quercuscornigera (agamic)</:title>
          <:chip variant={:warn}>In progress</:chip>
          <:meta label="Season">Spring, Summer</:meta>
          <:action><a href="/edit">Edit</a></:action>
        </.page_header>
        """)

      assert count(html, "h1") == 1
      assert text(html, "h1") =~ "Callirhytis quercuscornigera (agamic)"
      # A scientific name is set in the text face, italic
      assert count(html, "h1.font-sans.italic") == 1

      assert count(html, ~s(nav[aria-label="Breadcrumb"] a)) == 2
      assert count(html, ~s(nav[aria-label="Breadcrumb"] a em)) == 1

      assert text(html, "[data-part=chips]") =~ "In progress"
      assert text(html, "[data-part=meta]") =~ "Season"
      assert text(html, "[data-part=meta]") =~ "Spring, Summer"
      assert count(html, "[data-part=actions] a[href='/edit']") == 1
    end

    test "the description runs to the lead measure, wider than running text" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.page_header>
          <:title>Site analytics</:title>
          <:description>How Gallformers is used, counted without tracking anyone.</:description>
        </.page_header>
        """)

      assert count(html, "p[data-part=description].max-w-lead") == 1
    end

    test "a plain title is set in the brand face, with no breadcrumb" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.page_header>
          <:title>Sources</:title>
        </.page_header>
        """)

      assert count(html, "h1.font-brand") == 1
      assert count(html, "nav") == 0
    end
  end

  describe "section" do
    test "a heading on a rule, with its count and aside" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.section id="hosts" title="Hosts" count={14}>
          <:aside>Oldest first</:aside>
          <p>body</p>
        </.section>
        """)

      assert count(html, "section#hosts > header h2") == 1
      assert text(html, "h2") == "Hosts"
      assert text(html, "[data-part=count]") == "14"
      assert text(html, "[data-part=aside]") == "Oldest first"
      assert text(html, "section > div p") == "body"
    end

    test "nests as h3 at level 3" do
      assigns = %{}
      html = rendered_to_string(~H|<.section title="Traits" level={3}>x</.section>|)
      assert count(html, "h3") == 1
      assert count(html, "h2") == 0
    end
  end

  describe "panel" do
    test "each variant marks itself and takes a title" do
      for variant <- [:plain, :info, :danger] do
        assigns = %{variant: variant}

        html =
          rendered_to_string(~H"""
          <.panel variant={@variant} title="Delete">content</.panel>
          """)

        assert count(html, "[data-variant=#{variant}]") == 1
        assert text(html, "h3") == "Delete"
      end
    end
  end

  describe "rail" do
    test "is an aside of the chosen width" do
      assigns = %{}
      html = rendered_to_string(~H|<.rail width={:narrow}>x</.rail>|)
      assert count(html, "aside[data-width=narrow]") == 1
    end
  end
end
