defmodule Gallformers.Import.PassagesTest do
  @moduledoc """
  The Source in context (`d213` Task 13): a quote's entry, heading to
  heading with the page furniture dropped; several quotes' passage; and the
  whole text for the reader panel, read from a package's `document.json`.
  """
  use ExUnit.Case, async: true

  alias Gallformers.Import.Passages

  # A Source in Ashmead's shape: front matter, a genus heading straight
  # above a species heading, an entry running over a page break (footer and
  # headers between), an empty block, and an entry under a `title`.
  defp document do
    texts = [
      text(0, "Front matter, before any heading.", "text", 1),
      text(1, "Genus ANDRICUS, Hartig.", "section_header", 1),
      text(2, "1. ANDRICUS FOO, new species.", "section_header", 1),
      text(3, "Gall.—A round gall on the twigs of the black oak.", "text", 1),
      text(4, "113", "page_footer", 1),
      text(5, "114", "page_header", 2),
      text(6, "CYNIPIDOUS GALLS—ASHMEAD.", "page_header", 2),
      text(7, "Type.—No. 1, U.S.N.M.", "text", 2),
      text(8, "  ", "text", 2),
      text(9, "-", "text", 2),
      text(10, "2. ANDRICUS BAR, new species.", "section_header", 2),
      text(11, "Gall.—A flat gall.", "text", 2),
      text(12, "Genus CYNIPS", "title", 3),
      text(13, "Gall.—A Cynips gall.", "text", 3)
    ]

    %{
      "schema_name" => "DoclingDocument",
      "body" => %{
        "self_ref" => "#/body",
        "children" => Enum.map(texts, &%{"$ref" => &1["self_ref"]})
      },
      "texts" => texts
    }
  end

  defp text(i, text, label, page) do
    %{
      "self_ref" => "#/texts/#{i}",
      "label" => label,
      "text" => text,
      "prov" => [%{"page_no" => page}]
    }
  end

  defp refs(blocks), do: Enum.map(blocks, & &1.ref)

  describe "entry/2" do
    test "runs from the nearest heading to the next, over a page break, furniture dropped" do
      assert Passages.entry(document(), "#/texts/3") == [
               %{
                 ref: "#/texts/2",
                 text: "1. ANDRICUS FOO, new species.",
                 page: 1,
                 heading?: true
               },
               %{
                 ref: "#/texts/3",
                 text: "Gall.—A round gall on the twigs of the black oak.",
                 page: 1,
                 heading?: false
               },
               %{ref: "#/texts/7", text: "Type.—No. 1, U.S.N.M.", page: 2, heading?: false}
             ]
    end

    test "the species heading under a genus heading starts the entry, not the genus" do
      assert refs(Passages.entry(document(), "#/texts/7")) == ~w(#/texts/2 #/texts/3 #/texts/7)
      # A heading is its own entry's start.
      assert refs(Passages.entry(document(), "#/texts/2")) == ~w(#/texts/2 #/texts/3 #/texts/7)
      # The genus heading, with nothing but a heading after it, stands alone.
      assert refs(Passages.entry(document(), "#/texts/1")) == ~w(#/texts/1)
    end

    test "an item before any heading runs from the start" do
      assert [%{ref: "#/texts/0", page: 1, heading?: false}] =
               Passages.entry(document(), "#/texts/0")
    end

    test "a title is a heading too" do
      assert refs(Passages.entry(document(), "#/texts/13")) == ~w(#/texts/12 #/texts/13)
    end

    test "a reference the document doesn't hold has no entry" do
      assert Passages.entry(document(), "#/texts/99") == []
      assert Passages.entry(document(), "nonsense") == []
    end
  end

  describe "passage/2" do
    test "is the entries of several quotes in document order, the cited blocks marked" do
      passage = Passages.passage(document(), ["#/texts/11", "#/texts/3"])

      assert Enum.map(passage, &{&1.ref, &1.cited?}) == [
               {"#/texts/2", false},
               {"#/texts/3", true},
               {"#/texts/7", false},
               {"#/texts/10", false},
               {"#/texts/11", true}
             ]
    end

    test "quotes in one entry give it once" do
      passage = Passages.passage(document(), ["#/texts/7", "#/texts/3", "#/texts/3"])

      assert Enum.map(passage, &{&1.ref, &1.cited?}) == [
               {"#/texts/2", false},
               {"#/texts/3", true},
               {"#/texts/7", true}
             ]
    end

    test "references the document doesn't hold are left out" do
      assert Passages.passage(document(), ["#/texts/99"]) == []
    end
  end

  describe "blocks/1" do
    test "is the whole text in order, the furniture and empty blocks dropped" do
      blocks = Passages.blocks(document())

      assert refs(blocks) == ~w(#/texts/0 #/texts/1 #/texts/2 #/texts/3 #/texts/7
                                #/texts/10 #/texts/11 #/texts/12 #/texts/13)

      assert Enum.filter(blocks, & &1.heading?) |> refs() ==
               ~w(#/texts/1 #/texts/2 #/texts/10 #/texts/12)
    end
  end
end
