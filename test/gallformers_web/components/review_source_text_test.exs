defmodule GallformersWeb.ReviewSourceTextTest do
  @moduledoc """
  The Source in context on the review pages (matter `d213`, Task 22): a
  quote's passage (`review_passage/1`), its pages and headings, the cited
  block marked; and the reader panel (`review_reader/1`), the whole text
  with the question's quotes marked and what the find box matches.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]

  alias GallformersWeb.ReviewComponents

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp has?(html, selector), do: html |> query(selector) |> Enum.any?()
  defp count(html, selector), do: html |> query(selector) |> Enum.count()
  defp text(html, selector), do: html |> query(selector) |> LazyHTML.text()

  defp pages(html, selector),
    do: html |> query(selector) |> Enum.map(&String.trim(LazyHTML.text(&1)))

  @entry [
    %{ref: "#/texts/1", text: "Andricus foliatus n. sp.", page: 120, heading?: true},
    %{ref: "#/texts/2", text: "Gall on the twigs of the black oak.", page: 120, heading?: false},
    %{ref: "#/texts/3", text: "Collected in Virginia.", page: 121, heading?: false},
    %{ref: "#/texts/4", text: "Andricus pattoni n. sp.", page: 121, heading?: true},
    %{ref: "#/texts/5", text: "On the black oak too.", page: 121, heading?: false}
  ]

  defp cite(blocks, refs), do: Enum.map(blocks, &Map.put(&1, :cited?, &1.ref in refs))

  describe "review_passage" do
    test "the entry's blocks in order, the cited one marked, headings bold" do
      html =
        render_component(&ReviewComponents.review_passage/1,
          blocks: @entry |> Enum.take(3) |> cite(["#/texts/2"])
        )

      assert text(html, "[data-cited]") =~ "Gall on the twigs of the black oak."
      assert count(html, "[data-cited]") == 1
      assert text(html, "[data-heading]") =~ "Andricus foliatus n. sp."
      assert has?(html, "[data-heading].font-semibold")

      blocks = html |> query("[data-role=block]") |> Enum.map(&LazyHTML.text/1)
      assert length(blocks) == 3
      assert Enum.at(blocks, 0) =~ "Andricus foliatus"
      assert Enum.at(blocks, 2) =~ "Collected in Virginia."
    end

    test "gives the page where it changes" do
      html =
        render_component(&ReviewComponents.review_passage/1,
          blocks: @entry |> Enum.take(3) |> cite(["#/texts/2"])
        )

      assert pages(html, "[data-role=page]") == ["p. 120", "p. 121"]
    end

    test "a block without a page gives none" do
      html =
        render_component(&ReviewComponents.review_passage/1,
          blocks: [%{ref: "#/texts/1", text: "Text", page: nil, heading?: false, cited?: true}]
        )

      refute has?(html, "[data-role=page]")
    end

    test "says when the Source's text doesn't hold the passage" do
      html = render_component(&ReviewComponents.review_passage/1, blocks: [])
      assert html =~ "The passage isn’t in the Source’s text."
    end
  end

  describe "review_quote with a passage" do
    test "puts the passage behind Show the passage" do
      assigns = %{blocks: @entry |> Enum.take(3) |> cite(["#/texts/2"])}

      html =
        rendered_to_string(~H"""
        <ReviewComponents.review_quote text="the twigs of the black oak" where="Andricus foliatus">
          <:passage><ReviewComponents.review_passage blocks={@blocks} /></:passage>
        </ReviewComponents.review_quote>
        """)

      assert text(html, "details[data-role=passage] summary") =~ "Show the passage"
      assert text(html, "details[data-role=passage] [data-cited]") =~ "black oak"
    end

    test "has no passage control without one" do
      html = render_component(&ReviewComponents.review_quote/1, text: "the black oak")
      refute has?(html, "[data-role=passage]")
    end
  end

  describe "review_reader" do
    defp reader(opts) do
      render_component(
        &ReviewComponents.review_reader/1,
        Keyword.merge(
          [
            id: "reader",
            title: "Ashmead 1897",
            question: "Which plant does Ashmead 1897 mean by “the black oak”?",
            blocks: @entry,
            cited: ["#/texts/2", "#/texts/5"],
            find: "",
            on_find: "reader_find",
            on_close: "reader_close"
          ],
          opts
        )
      )
    end

    test "the whole text with the question's quotes marked, pages and headings" do
      html = reader([])

      assert has?(html, "aside#reader[aria-label]")
      assert text(html, "#reader [data-role=title]") =~ "Ashmead 1897"
      assert text(html, "#reader [data-role=question]") =~ "the black oak"
      assert count(html, "#reader-body [data-role=block]") == 5
      assert count(html, "#reader-body [data-cited]") == 2
      assert text(html, "#reader-body [data-cited]") =~ "On the black oak too."
      assert count(html, "#reader-body [data-heading]") == 2

      assert pages(html, "#reader-body [data-role=page]") == [
               "p. 120",
               "p. 121"
             ]

      refute has?(html, "#reader-body mark")
      assert has?(html, "#reader-body[phx-hook=SourceReader]")
    end

    test "the find box marks every match, ignoring case, and counts the passages" do
      html = reader(find: "BLACK oak")

      assert html |> query("#reader-body mark") |> Enum.map(&LazyHTML.text/1) ==
               ["black oak", "black oak"]

      assert text(html, "#reader-hits") =~ "2 passages"
      assert has?(html, "#reader-find input[name=find][value='BLACK oak']")
      assert has?(html, "#reader-find[phx-change=reader_find]")
    end

    test "a find with no match says so; text with markup characters stays text" do
      html =
        reader(
          find: "<b>",
          blocks: [%{ref: "#/texts/9", text: "a <b> c", page: 1, heading?: false}]
        )

      assert text(html, "#reader-body mark") == "<b>"
      assert text(html, "#reader-hits") =~ "1 passage"
      refute text(html, "#reader-hits") =~ "passages"

      none = reader(find: "white oak")
      assert text(none, "#reader-hits") =~ "No passage"
    end

    test "Close sends on_close" do
      assert has?(reader([]), "#reader button[phx-click=reader_close]")
    end
  end
end
