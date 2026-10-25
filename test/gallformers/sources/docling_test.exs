defmodule Gallformers.Sources.DoclingTest do
  @moduledoc """
  Reading a DoclingDocument the way `priv/import/validate.py` does
  (`resolve`, `items`, `item_text`), on the validator's `document` fixture.
  """
  use ExUnit.Case, async: true

  alias Gallformers.DoclingFixtures
  alias Gallformers.Sources.Docling

  setup do
    %{doc: DoclingFixtures.document()}
  end

  describe "resolve/2" do
    test "finds the item a reference points at", %{doc: doc} do
      assert %{"self_ref" => "#/texts/3"} = Docling.resolve(doc, "#/texts/3")
      assert %{"self_ref" => "#/tables/0"} = Docling.resolve(doc, "#/tables/0")
    end

    test "a missing item is nil", %{doc: doc} do
      assert Docling.resolve(doc, "#/texts/99") == nil
      assert Docling.resolve(doc, "#/charts/0") == nil
    end

    test "a malformed reference is nil", %{doc: doc} do
      for ref <- ["texts/1", "#/texts", "#/texts/x", "#/texts/-1", "#/texts/1/2", ""] do
        assert Docling.resolve(doc, ref) == nil, "expected nil for #{inspect(ref)}"
      end
    end
  end

  describe "item_text/1" do
    test "a text item's text", %{doc: doc} do
      assert Docling.item_text(Docling.resolve(doc, "#/texts/3")) ==
               "Torymus developed as an external parasitoid of the gall wasp larva."
    end

    test "a table is its rows, cells joined with ' | ', a spanning cell once", %{doc: doc} do
      assert Docling.item_text(Docling.resolve(doc, "#/tables/0")) ==
               "Species | Count | Note\nTorymus sp. | 14 | reared\nParasitoids"
    end

    test "a picture has no text of its own; its caption is a separate item", %{doc: doc} do
      assert Docling.item_text(Docling.resolve(doc, "#/pictures/0")) == ""
      assert Docling.item_text(Docling.resolve(doc, "#/texts/4")) == "Figure 1. A gall."
    end
  end

  describe "items/1" do
    test "body reading order first, walking into children", %{doc: doc} do
      assert Enum.map(Docling.items(doc), & &1["self_ref"]) == [
               "#/texts/0",
               "#/texts/1",
               "#/texts/2",
               "#/texts/3",
               "#/tables/0",
               "#/pictures/0",
               "#/texts/4"
             ]
    end

    test "groups are walked but not yielded; unreachable items come last", %{doc: doc} do
      doc =
        doc
        |> Map.put("body", %{"self_ref" => "#/body", "children" => [%{"$ref" => "#/groups/0"}]})
        |> Map.put("groups", [
          %{
            "self_ref" => "#/groups/0",
            "children" => [%{"$ref" => "#/texts/2"}, %{"$ref" => "#/texts/2"}]
          }
        ])
        |> Map.put("furniture", %{
          "self_ref" => "#/furniture",
          "children" => [%{"$ref" => "#/texts/0"}]
        })

      assert Enum.map(Docling.items(doc), & &1["self_ref"]) == [
               "#/texts/2",
               "#/texts/0",
               "#/texts/1",
               "#/texts/3",
               "#/texts/4",
               "#/tables/0",
               "#/pictures/0"
             ]
    end
  end

  describe "document_items/1" do
    test "one row per text, table and picture item, in reading order", %{doc: doc} do
      items = Docling.document_items(doc)

      assert Enum.map(items, & &1.position) == Enum.to_list(0..6)

      assert Enum.at(items, 1) == %{
               ref: "#/texts/1",
               label: "text",
               text:
                 "The large stem galls produced by the agamic generation of Andricus quercuscalifornicus are glob-\nular and pale tan when mature.",
               page_no: 1,
               position: 1
             }

      assert %{ref: "#/tables/0", label: "table", page_no: 2} = Enum.at(items, 4)
      assert %{ref: "#/pictures/0", text: "", page_no: 2} = Enum.at(items, 5)
    end

    test "an item without provenance has no page", %{doc: doc} do
      doc = update_in(doc, ["texts", Access.at(3)], &Map.delete(&1, "prov"))

      assert %{ref: "#/texts/3", page_no: nil} =
               Enum.find(Docling.document_items(doc), &(&1.ref == "#/texts/3"))
    end
  end
end
