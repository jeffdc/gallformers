defmodule GallformersWeb.UIComponentsTest do
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]
  import GallformersWeb.UIComponents

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp text(html, selector), do: html |> query(selector) |> LazyHTML.text() |> String.trim()

  describe "see_also" do
    test "names its links See also and searches each resource for the name" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.see_also name="Andricus weldi (agamic)" type={:gall} />
        """)

      assert text(html, "[data-part=label]") == "See also"

      assert html |> query("a") |> LazyHTML.attribute("href") |> hd() ==
               "https://www.inaturalist.org/search?q=Andricus%20weldi"
    end
  end

  describe "tooltip" do
    test "its text shows on hover or focus of what it explains, which it describes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.tooltip id="tip" text="Tan to light brown.">tan</.tooltip>
        """)

      assert text(html, "#tip [role=tooltip]") == "Tan to light brown."
      assert query(html, "#tip [aria-describedby=tip-text]") |> Enum.any?()
      assert query(html, "#tip-text[role=tooltip]") |> Enum.any?()
      assert html =~ "tan"
    end
  end

  # The dotted underline is fact_ref's alone (matter 87a1, question 13): a
  # glossary term is a plain link to its entry, its definition in a tooltip.
  describe "glossary_tooltip" do
    test "the term, in parentheses, links to its glossary entry; its definition's first sentence is the tooltip" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.glossary_tooltip
          term="sexual"
          glossary_word="sexgen"
          definition="The sexual generation has males and females. It forms in spring."
        />
        """)

      assert [link] = query(html, "a[href='/glossary#sexgen']") |> Enum.to_list()
      assert LazyHTML.text(link) == "sexual"
      assert text(html, "[role=tooltip]") == "The sexual generation has males and females."
      assert query(html, "[aria-describedby] a[href='/glossary#sexgen']") |> Enum.any?()

      # The parentheses sit right against the tooltip (an inline-flex: its
      # whitespace isn't shown).
      assert html =~ ~r/>\(<span id="glossary-sexgen" class="gf-tooltip\s*">/
      assert html =~ ~r/<\/span>\)<\/span>\s*$/

      refute html =~ "border-dotted"
    end

    test "with no definition, just the link" do
      assigns = %{}
      html = rendered_to_string(~H|<.glossary_tooltip term="agamic" />|)

      assert query(html, "a[href='/glossary#agamic']") |> Enum.any?()
      refute query(html, "[role=tooltip]") |> Enum.any?()
    end
  end
end
