defmodule Gallformers.Catalog.TermUsageTest do
  @moduledoc """
  How many Galls use each Source term (matter `d213`, Task D): for the
  superadmin vocabulary page, the distinct Galls whose Trait attributions
  carry the term or that wait on it, by Trait and normalized term.

  Not async: the Catalog vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog

  setup :audit_test_metadata

  setup do
    {:ok, _counts} = Catalog.load_vocab(test_actor())
    :ok
  end

  @now ~U[2026-11-01 00:00:00Z]

  defp insert_returning!(table, row) do
    {1, [%{id: id}]} = Repo.insert_all(table, [row], returning: [:id])
    id
  end

  # The package and batch a waiting term came from.
  defp origin do
    n = System.unique_integer([:positive])

    package_id =
      insert_returning!("import_packages", %{
        key: "pkg-#{n}",
        s3_prefix: "import/pkg-#{n}/",
        submitter_name: "test",
        inserted_at: @now,
        updated_at: @now
      })

    batch_id =
      insert_returning!("import_batches", %{
        package_id: package_id,
        file: "gall.json",
        batch_type: "gall",
        mode: "add",
        producer_batch_id: "batch-#{n}",
        sha256: "0",
        content: %{},
        inserted_at: @now,
        updated_at: @now
      })

    %{package_id: package_id, batch_id: batch_id}
  end

  test "counts the distinct Galls carrying or waiting on each term" do
    one = gall_fixture(name: "Term gall one")
    two = gall_fixture(name: "Term gall two")
    first = source_fixture("First", "1990")
    second = source_fixture("Second", "1991")

    for {gall, source, term} <- [
          {one, first, "Ovoid"},
          {one, second, "ovoid"},
          {two, first, "ovoid "}
        ] do
      {:ok, _} =
        Catalog.assert_trait(
          test_actor(),
          %{gall_id: gall.id, trait: "shape", value: "globular"},
          confirm(source, %{term: term})
        )
    end

    {:ok, _} =
      Catalog.put_pending_term(
        test_actor(),
        Map.merge(origin(), %{
          gall_id: two.id,
          source_id: second.id,
          trait: "texture",
          term: "Lumpy",
          evidence: []
        })
      )

    counts = Catalog.term_gall_counts()
    assert counts[{"shape", "ovoid"}] == 2
    assert counts[{"texture", "lumpy"}] == 1
    refute Map.has_key?(counts, {"shape", "rough"})
  end
end
