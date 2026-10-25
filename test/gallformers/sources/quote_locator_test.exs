defmodule Gallformers.Sources.QuoteLocatorTest do
  @moduledoc """
  Locating a quote in an item's text, matching as `priv/import/validate.py`'s
  `quote_in` does, and returning the span in the ORIGINAL text. The document
  cases are the validator's (`priv/import/tests/test_document_checks.py`, on
  the `document` fixture in `conftest.py`).
  """
  use ExUnit.Case, async: true

  alias Gallformers.DoclingFixtures
  alias Gallformers.Sources.Docling
  alias Gallformers.Sources.QuoteLocator

  # Slices by codepoint, independently of QuoteLocator.slice/2.
  defp cut(text, {start, length}) do
    text |> String.codepoints() |> Enum.slice(start, length) |> Enum.join()
  end

  defp located(text, quote) do
    assert {:ok, span} = QuoteLocator.locate(text, quote)
    cut(text, span)
  end

  defp item_text(ref), do: Docling.item_text(Docling.resolve(DoclingFixtures.document(), ref))

  describe "the validator's document cases" do
    test "the clean batch's quotes are found where they are" do
      assert located(
               item_text("#/texts/1"),
               "produced by the agamic generation of Andricus quercuscalifornicus"
             ) == "produced by the agamic generation of Andricus quercuscalifornicus"

      assert located(item_text("#/texts/2"), "Common on Q. lobata throughout the hills") ==
               "Common on Q. lobata throughout the hills"
    end

    test "a quote across a hyphenated line break and extra whitespace" do
      text = item_text("#/texts/1")

      assert {:ok, {start, length}} = QuoteLocator.locate(text, "are globular  and pale tan")
      assert cut(text, {start, length}) == "are glob-\nular and pale tan"
      assert start == 87
      assert length == 27
    end

    test "a table row quote" do
      assert located(item_text("#/tables/0"), "Torymus sp. | 14 | reared") ==
               "Torymus sp. | 14 | reared"
    end

    test "a spanning cell counts once" do
      text = item_text("#/tables/0")

      assert located(text, "Parasitoids") == "Parasitoids"
      assert located(text, "reared Parasitoids") == "reared\nParasitoids"
      assert QuoteLocator.locate(text, "Parasitoids | Parasitoids") == :error
    end

    test "a quote from another item is not found in this one" do
      quote = "external parasitoid of the gall wasp larva"

      assert QuoteLocator.locate(item_text("#/texts/2"), quote) == :error
      assert located(item_text("#/texts/3"), quote) == quote
    end

    test "a quote the Source doesn't contain" do
      assert QuoteLocator.locate(item_text("#/texts/2"), "Rare on Q. lobata") == :error
    end

    test "an item with no text holds no quote" do
      assert item_text("#/pictures/0") == ""
      assert QuoteLocator.locate(item_text("#/pictures/0"), "A gall") == :error
    end
  end

  describe "normalisation" do
    test "a compatibility character spans its source character" do
      text = "a deﬁnite gall"

      assert located(text, "definite") == "deﬁnite"
      # A match starting inside the ligature's expansion takes the whole ligature.
      assert located(text, "inite gall") == "ﬁnite gall"
    end

    test "a composed quote matches decomposed text" do
      text = "Andricus café gall"

      assert located(text, "café gall") == "café gall"
    end

    test "soft hyphens are ignored" do
      assert located("glob­ular and pale", "globular and") == "glob­ular and"
    end

    test "any whitespace run matches one space" do
      text = "pale tan\t\twhen\r\nmature"

      assert located(text, "pale tan when mature") == text
      assert located(text, "  tan   when ") == "tan\t\twhen"
    end

    test "the quote's own line-break hyphen is joined too" do
      assert located("are globular and pale", "are glob- ular") == "are globular"
    end

    test "a hyphen that is not at a line break is kept" do
      text = "the two-chambered gall"

      assert located(text, "two-chambered") == "two-chambered"
      assert QuoteLocator.locate(text, "twochambered") == :error
    end

    test "offsets count codepoints, not bytes or graphemes" do
      text = "Çá́ — glob-\nular"

      assert {:ok, {start, length}} = QuoteLocator.locate(text, "globular")
      assert {start, length} == {7, 10}
      assert cut(text, {start, length}) == "glob-\nular"
    end

    test "the first occurrence is returned" do
      assert QuoteLocator.locate("the oak and the oak", "oak") == {:ok, {4, 3}}
    end

    test "a blank quote is never found" do
      assert QuoteLocator.locate("some text", "   ") == :error
      assert QuoteLocator.locate("some text", "") == :error
    end
  end

  describe "slice/2" do
    test "cuts the original text by codepoint span" do
      text = "Çá́ — glob-\nular"

      assert QuoteLocator.slice(text, {7, 10}) == "glob-\nular"
    end
  end
end
