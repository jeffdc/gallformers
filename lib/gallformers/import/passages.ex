defmodule Gallformers.Import.Passages do
  @moduledoc """
  The Source in context (`d213`): what the review pages show around a
  quote, read from a package's `document.json` (a DoclingDocument, decoded;
  `Gallformers.Import.ReviewContext.document/1` reads it from the bucket).

    * `entry/2` — the Source's entry a quoted item sits in: from the nearest
      heading at or above it (a `section_header` or `title` block; the item
      itself when it is one) to just before the next heading, or from the
      start of the text for an item before any heading ("Show the passage").
      A genus line straight above a species heading is not part of the
      species' entry: the nearest heading wins.
    * `passage/2` — the entries of several quoted items, each once, in
      document order, the quoted blocks marked `cited?`.
    * `blocks/1` — the whole text, for the reader panel ("Read the Source").

  Blocks are in the document's reading order (`Gallformers.Sources.Docling`,
  as the validator reads it). Page headers and footers are dropped, so an
  entry running over a page break reads on, its blocks' pages changing; so
  are blocks with no letter or digit (empty, or OCR debris such as a lone
  "-"). Each block is `%{ref, text, page, heading?}`: its reference
  (`"#/texts/42"`), its text, the PDF page it starts on (nil without
  provenance) and whether it is a heading.

  Pure: nothing here reads the database or the bucket.
  """

  alias Gallformers.Sources.Docling

  @headings ["section_header", "title"]
  @furniture ["page_header", "page_footer"]

  @type block :: %{
          ref: String.t(),
          text: String.t(),
          page: pos_integer() | nil,
          heading?: boolean()
        }

  @type passage_block :: %{
          ref: String.t(),
          text: String.t(),
          page: pos_integer() | nil,
          heading?: boolean(),
          cited?: boolean()
        }

  @doc """
  The entry quoted item `ref` sits in, as blocks; `[]` when the document
  holds no such item.
  """
  @spec entry(Docling.document(), String.t()) :: [block()]
  def entry(doc, ref) when is_map(doc) and is_binary(ref) do
    items = items(doc)

    case range(items, ref) do
      nil -> []
      range -> range |> Enum.map(&elem(items, &1)) |> shown()
    end
  end

  @doc """
  The entries quoted items `refs` sit in, each once, in document order,
  each block marked `cited?` when it is one of `refs`. References the
  document doesn't hold are left out.
  """
  @spec passage(Docling.document(), [String.t()]) :: [passage_block()]
  def passage(doc, refs) when is_map(doc) and is_list(refs) do
    items = items(doc)
    cited = MapSet.new(refs)

    refs
    |> Enum.map(&range(items, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(&Enum.to_list/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&elem(items, &1))
    |> shown()
    |> Enum.map(&Map.put(&1, :cited?, MapSet.member?(cited, &1.ref)))
  end

  @doc "The whole text, as blocks, for the reader panel."
  @spec blocks(Docling.document()) :: [block()]
  def blocks(doc) when is_map(doc), do: doc |> items() |> Tuple.to_list() |> shown()

  # Every item in reading order, with its label, as a tuple to index.
  defp items(doc) do
    doc
    |> Docling.items()
    |> Enum.map(fn item ->
      %{
        ref: item["self_ref"],
        label: item["label"],
        text: Docling.item_text(item),
        page: Docling.page_no(item)
      }
    end)
    |> List.to_tuple()
  end

  # The index range of the entry item `ref` sits in, or nil.
  defp range(items, ref) do
    size = tuple_size(items)

    case Enum.find(0..(size - 1)//1, &(elem(items, &1).ref == ref)) do
      nil ->
        nil

      index ->
        first = Enum.find(index..0//-1, 0, &heading?(elem(items, &1)))
        next = Enum.find((index + 1)..(size - 1)//1, size, &heading?(elem(items, &1)))
        first..(next - 1)//1
    end
  end

  defp heading?(%{label: label}), do: label in @headings

  defp shown(items) do
    for item <- items, item.label not in @furniture, item.text =~ ~r/[[:alnum:]]/u do
      %{ref: item.ref, text: item.text, page: item.page, heading?: heading?(item)}
    end
  end
end
