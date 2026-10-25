defmodule Gallformers.Sources.DocumentsTest do
  @moduledoc """
  Storing a Source's document (`document.json`, a DoclingDocument): the
  private-bucket object, the `source_documents` row and its `document_items`.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.DoclingFixtures
  alias Gallformers.Sources
  alias Gallformers.Sources.DocumentItem
  alias Gallformers.Sources.QuoteLocator
  alias Gallformers.Sources.SourceDocument
  alias Gallformers.Storage.Private

  defp source_fixture(title) do
    {:ok, source} =
      Sources.create_source(%{
        title: title,
        author: "Weld, L. H.",
        pubyear: "1957",
        link: "https://example.com/#{System.unique_integer([:positive])}",
        citation: "#{title}. 1957.",
        license: "Public Domain / Copyright Expired"
      })

    source
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp changes_for(table) do
    Repo.all(
      from c in Carbonite.Change,
        where: c.table_name == ^table,
        preload: :transaction
    )
  end

  describe "store_document/3" do
    test "stores the bytes privately and records the document and its items" do
      source = source_fixture("Cynipid galls of the Pacific slope")
      json = DoclingFixtures.document_json()

      assert {:ok, %SourceDocument{} = doc} = Sources.store_document(test_actor(), source, json)

      assert doc.source_id == source.id
      assert doc.kind == :docling
      assert doc.sha256 == sha256(json)
      assert doc.gall_id == nil
      assert doc.version_date == nil
      assert Private.get(doc.s3_key) == {:ok, json}

      items = Sources.list_document_items(doc)

      assert Enum.map(items, & &1.ref) == [
               "#/texts/0",
               "#/texts/1",
               "#/texts/2",
               "#/texts/3",
               "#/tables/0",
               "#/pictures/0",
               "#/texts/4"
             ]

      assert %DocumentItem{
               label: "table",
               text: "Species | Count | Note\nTorymus sp. | 14 | reared\nParasitoids",
               page_no: 2,
               position: 4
             } = Enum.at(items, 4)
    end

    test "is idempotent by sha256 for the same Source" do
      source = source_fixture("Stored twice")
      json = DoclingFixtures.document_json()

      {:ok, first} = Sources.store_document(test_actor(), source, json)
      {:ok, second} = Sources.store_document(test_actor(), source, json)

      assert second.id == first.id
      assert Repo.aggregate(where(SourceDocument, source_id: ^source.id), :count) == 1
      assert length(Sources.list_document_items(first)) == 7
    end

    test "the same bytes for another Source are that Source's own document" do
      json = DoclingFixtures.document_json()
      {:ok, a} = Sources.store_document(test_actor(), source_fixture("Source A"), json)
      {:ok, b} = Sources.store_document(test_actor(), source_fixture("Source B"), json)

      assert a.id != b.id
      assert a.sha256 == b.sha256
    end

    test "a different document for the same Source is stored beside the first" do
      source = source_fixture("Re-extracted")
      {:ok, first} = Sources.store_document(test_actor(), source, DoclingFixtures.document_json())

      changed =
        DoclingFixtures.document()
        |> put_in(["texts", Access.at(4), "text"], "Figure 1. A large gall.")
        |> DoclingFixtures.document_json()

      {:ok, second} = Sources.store_document(test_actor(), source, changed)

      assert second.id != first.id
      assert Sources.get_document_item(second, "#/texts/4").text == "Figure 1. A large gall."
    end

    test "rejects bytes that are not a DoclingDocument, storing nothing" do
      source = source_fixture("Not a document")

      assert Sources.store_document(test_actor(), source, "not json") == {:error, :invalid_json}

      assert Sources.store_document(test_actor(), source, ~s({"schema_name": "Other"})) ==
               {:error, :not_a_docling_document}

      assert Repo.aggregate(where(SourceDocument, source_id: ^source.id), :count) == 0
    end

    test "audits the document row but not its items" do
      source = source_fixture("Audited")
      {:ok, doc} = Sources.store_document(test_actor(), source, DoclingFixtures.document_json())

      assert [change] = changes_for("source_documents")
      assert change.op == :insert
      assert change.table_pk == [to_string(doc.id)]
      assert change.transaction.meta["operation"] == "sources.store_document"
      assert change.transaction.meta["actor"] == %{"type" => "system", "name" => "test"}

      assert changes_for("document_items") == []
    end
  end

  describe "get_document_item/2" do
    setup do
      source = source_fixture("Items")
      {:ok, doc} = Sources.store_document(test_actor(), source, DoclingFixtures.document_json())
      %{doc: doc}
    end

    test "finds an item by reference", %{doc: doc} do
      assert %DocumentItem{text: "Figure 1. A gall.", page_no: 1} =
               Sources.get_document_item(doc, "#/texts/4")
    end

    test "a missing item is nil", %{doc: doc} do
      assert Sources.get_document_item(doc, "#/texts/99") == nil
    end

    test "a picture is stored with no text", %{doc: doc} do
      assert %DocumentItem{label: "picture", text: ""} =
               Sources.get_document_item(doc, "#/pictures/0")
    end
  end

  describe "locate_quote/2" do
    setup do
      source = source_fixture("Quotes")
      {:ok, doc} = Sources.store_document(test_actor(), source, DoclingFixtures.document_json())
      %{doc: doc}
    end

    test "locates a quote in a stored item by the item's ID", %{doc: doc} do
      item = Sources.get_document_item(doc, "#/texts/1")

      assert {:ok, {start, length}} = Sources.locate_quote(item.id, "globular and pale tan")
      assert QuoteLocator.slice(item.text, {start, length}) == "glob-\nular and pale tan"
    end

    test "a quote that is not in the item is not found", %{doc: doc} do
      item = Sources.get_document_item(doc, "#/texts/1")
      assert Sources.locate_quote(item.id, "spherical and red") == {:error, :quote_not_found}
    end

    test "a missing item is not found" do
      assert Sources.locate_quote(-1, "anything") == {:error, :item_not_found}
    end
  end

  describe "SourceDocument.changeset/2" do
    test "a note needs its Gall; a legacy note has no version date" do
      changeset =
        SourceDocument.changeset(%SourceDocument{}, %{
          source_id: 1,
          kind: :note,
          s3_key: "notes/1/x.md",
          sha256: String.duplicate("a", 64)
        })

      assert errors_on(changeset) == %{gall_id: ["can't be blank"]}
    end

    test "a Docling document has neither" do
      changeset =
        SourceDocument.changeset(%SourceDocument{}, %{
          source_id: 1,
          kind: :docling,
          s3_key: "sources/1/x.json",
          sha256: String.duplicate("a", 64),
          gall_id: 7,
          version_date: ~D[2024-01-01]
        })

      assert %{gall_id: ["must be blank for a document"], version_date: [_]} =
               errors_on(changeset)
    end

    test "sha256 is 64 lowercase hex characters" do
      changeset =
        SourceDocument.changeset(%SourceDocument{}, %{
          source_id: 1,
          kind: :docling,
          s3_key: "sources/1/x.json",
          sha256: "ABC"
        })

      assert %{sha256: [_]} = errors_on(changeset)
    end
  end
end
