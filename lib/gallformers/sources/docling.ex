defmodule Gallformers.Sources.Docling do
  @moduledoc """
  Reads a DoclingDocument (a Source's `document.json`, decoded to a map) the
  same way the import contract's validator does: `resolve/2`, `items/1` and
  `item_text/1` mirror `resolve`, `items` and `item_text` in
  `priv/import/validate.py`. Keep them in step: a quote the validator accepts
  must be found here too.
  """

  @item_arrays ["texts", "tables", "pictures"]

  @typedoc "A decoded DoclingDocument."
  @type document :: map()

  @typedoc "One content item of a DoclingDocument (a text, table or picture)."
  @type item :: map()

  @typedoc "What Gallformers stores of each content item."
  @type document_item :: %{
          ref: String.t(),
          label: String.t() | nil,
          text: String.t(),
          page_no: pos_integer() | nil,
          position: non_neg_integer()
        }

  @doc """
  The item a reference like `"#/texts/42"` points at, or nil when the
  reference is malformed or points past the end of its array.
  """
  @spec resolve(document(), String.t()) :: map() | nil
  def resolve(doc, ref) when is_map(doc) and is_binary(ref) do
    with ["#", array, index] <- String.split(ref, "/"),
         true <- index =~ ~r/\A[0-9]+\z/,
         list when is_list(list) <- Map.get(doc, array) do
      Enum.at(list, String.to_integer(index))
    else
      _ -> nil
    end
  end

  @doc """
  Every text, table and picture item: the body's reading order first (walking
  into groups and other children), then the furniture's, then any item
  reachable from neither, in array order. Each item appears once.
  """
  @spec items(document()) :: [item()]
  def items(doc) when is_map(doc) do
    state = {[], MapSet.new()}
    state = walk(doc, Map.get(doc, "body") || %{}, state)
    state = walk(doc, Map.get(doc, "furniture") || %{}, state)

    {found, _seen} =
      for array <- @item_arrays,
          item <- Map.get(doc, array) || [],
          reduce: state do
        {found, seen} = acc ->
          ref = item["self_ref"]
          if MapSet.member?(seen, ref), do: acc, else: {[item | found], MapSet.put(seen, ref)}
      end

    Enum.reverse(found)
  end

  @doc """
  An item's text. A table's text is its rows, one per line, each row's cells
  joined with `" | "`; a cell spanning several columns is counted once. An
  item without text (a picture) has `""`.
  """
  @spec item_text(item()) :: String.t()
  def item_text(%{"data" => data}) when is_map(data) do
    Enum.map_join(data["grid"] || [], "\n", fn row ->
      row
      |> Enum.with_index()
      |> Enum.filter(fn {cell, col} -> cell["start_col_offset_idx"] == col end)
      |> Enum.map_join(" | ", fn {cell, _col} -> cell["text"] end)
    end)
  end

  def item_text(item) when is_map(item), do: item["text"] || ""

  @doc """
  The page an item starts on, from its first provenance entry: the PDF page
  number (`page_no`), not the page number printed in the Source. Nil when the
  item has no provenance.
  """
  @spec page_no(item()) :: pos_integer() | nil
  def page_no(%{"prov" => [%{"page_no" => page_no} | _]}) when is_integer(page_no), do: page_no
  def page_no(_item), do: nil

  @doc """
  What Gallformers stores of each item in `items/1` order: its reference,
  label, text, page and position in that order.
  """
  @spec document_items(document()) :: [document_item()]
  def document_items(doc) do
    doc
    |> items()
    |> Enum.with_index()
    |> Enum.map(fn {item, position} ->
      %{
        ref: item["self_ref"],
        label: item["label"],
        text: item_text(item),
        page_no: page_no(item),
        position: position
      }
    end)
  end

  defp walk(doc, node, state) do
    Enum.reduce(node["children"] || [], state, fn child, acc ->
      visit(doc, resolve(doc, child["$ref"] || ""), acc)
    end)
  end

  defp visit(_doc, nil, state), do: state

  defp visit(doc, item, {found, seen} = state) do
    if MapSet.member?(seen, item["self_ref"]) do
      state
    else
      found = if content_item?(item), do: [item | found], else: found
      walk(doc, item, {found, MapSet.put(seen, item["self_ref"])})
    end
  end

  defp content_item?(%{"self_ref" => ref}) do
    case String.split(ref, "/") do
      [_, array | _] -> array in @item_arrays
      _ -> false
    end
  end
end
