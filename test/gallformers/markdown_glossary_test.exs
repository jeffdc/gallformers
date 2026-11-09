defmodule Gallformers.MarkdownGlossaryTest do
  @moduledoc """
  Glossary terms in rendered Markdown (matter `87a1`, question 13): the
  dotted underline is `fact_ref`'s alone, so a glossary term is a plain
  link to its entry, its definition's first sentence in a tooltip.

  Not async: the glossary's word cache is one ETS table for every test.
  """
  use Gallformers.DataCase, async: false

  alias Gallformers.Markdown

  describe "glossary terms as links" do
    setup do
      {:ok, _} =
        Gallformers.Glossaries.create_glossary(%{
          word: "zqxemergence",
          definition: "When the zqxinducer leaves the gall. It may chew a hole.",
          urls: "https://example.com/glossary"
        })

      {:ok, _} =
        Gallformers.Glossaries.create_glossary(%{
          word: "zqxinducer",
          definition: "What makes the gall.",
          urls: "https://example.com/glossary"
        })

      Markdown.refresh_cache()
      :ok
    end

    test "each a link to its entry, its definition's first sentence a tooltip" do
      {:ok, html} = Markdown.render("At zqxemergence the zqxinducer leaves.")
      doc = LazyHTML.from_fragment(html)

      assert [link] = doc |> LazyHTML.query("a[href='/glossary#zqxemergence']") |> Enum.to_list()
      assert LazyHTML.text(link) == "zqxemergence"
      refute LazyHTML.attribute(link, "class") |> Enum.any?(&(&1 =~ "glossary-link"))

      [tip] = doc |> LazyHTML.query("[role=tooltip]") |> Enum.take(1)
      assert LazyHTML.text(tip) == "When the zqxinducer leaves the gall."
      [id] = LazyHTML.attribute(tip, "id")
      assert doc |> LazyHTML.query("[aria-describedby='#{id}']") |> Enum.any?()
    end

    test "a definition's own glossary words aren't linked inside its tooltip" do
      {:ok, html} = Markdown.render("At zqxemergence.")

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("[role=tooltip] a")
             |> Enum.count() ==
               0
    end

    test "the same text rendered twice on a page has tooltips of its own" do
      {:ok, one} = Markdown.render("At zqxemergence.")
      {:ok, two} = Markdown.render("At zqxemergence.")

      ids = fn html ->
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[role=tooltip]")
        |> LazyHTML.attribute("id")
      end

      assert [a] = ids.(one)
      assert [b] = ids.(two)
      assert a != b
    end
  end
end
