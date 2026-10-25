defmodule Gallformers.DoclingFixtures do
  @moduledoc """
  The validator's `document` fixture (`priv/import/tests/conftest.py`), ported:
  a small DoclingDocument with the shapes Docling produces (texts, a table
  with a spanning cell, a picture whose caption is a text item).
  """

  @doc "The fixture document as a decoded JSON map."
  def document do
    texts = [
      text(0, "58 Journal of Examples", "page_header", "furniture"),
      text(
        1,
        "The large stem galls produced by the agamic generation of Andricus quercuscalifornicus are glob-\nular and pale tan when mature."
      ),
      text(
        2,
        "Common on Q. lobata throughout the hills; earlier records from Q. douglasii are misidentifications."
      ),
      text(3, "Torymus developed as an external parasitoid of the gall wasp larva."),
      text(4, "Figure 1. A gall.")
    ]

    header = [cell("Species", 0, 0), cell("Count", 0, 1), cell("Note", 0, 2)]
    row = [cell("Torymus sp.", 1, 0), cell("14", 1, 1), cell("reared", 1, 2)]
    spanning = cell("Parasitoids", 2, 0, 3)

    %{
      "schema_name" => "DoclingDocument",
      "body" => %{
        "self_ref" => "#/body",
        "children" =>
          Enum.map(0..3, &%{"$ref" => "#/texts/#{&1}"}) ++
            [%{"$ref" => "#/tables/0"}, %{"$ref" => "#/pictures/0"}]
      },
      "furniture" => %{"self_ref" => "#/furniture", "children" => []},
      "groups" => [],
      "texts" => texts,
      "tables" => [
        %{
          "self_ref" => "#/tables/0",
          "label" => "table",
          "content_layer" => "body",
          "prov" => prov(2),
          "children" => [],
          "data" => %{"grid" => [header, row, [spanning, spanning, spanning]]}
        }
      ],
      "pictures" => [
        %{
          "self_ref" => "#/pictures/0",
          "label" => "picture",
          "content_layer" => "body",
          "prov" => prov(2),
          "children" => [%{"$ref" => "#/texts/4"}],
          "captions" => [%{"$ref" => "#/texts/4"}]
        }
      ]
    }
  end

  @doc "The fixture document encoded as `document.json` bytes."
  def document_json(doc \\ document()), do: Jason.encode!(doc)

  defp prov(page), do: [%{"page_no" => page, "bbox" => %{}, "charspan" => [0, 0]}]

  defp text(i, text, label \\ "text", layer \\ "body", page \\ 1) do
    %{
      "self_ref" => "#/texts/#{i}",
      "label" => label,
      "content_layer" => layer,
      "text" => text,
      "prov" => prov(page),
      "children" => []
    }
  end

  defp cell(text, row, col, col_end \\ nil) do
    %{
      "text" => text,
      "start_row_offset_idx" => row,
      "end_row_offset_idx" => row + 1,
      "start_col_offset_idx" => col,
      "end_col_offset_idx" => col_end || col + 1
    }
  end
end
