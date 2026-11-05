defmodule Gallformers.Catalog.PendingTermsTest do
  @moduledoc """
  Terms waiting on a question (`d213` Task A): a Source's Trait term on a
  Gall that has no Fact yet, stored on the Gall (shown on its page, not in
  the ID tool) until a curator's decision settles it, under a category or
  as text.

  Not async: the Catalog vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.PendingTraitTerm

  @now ~U[2026-11-01 00:00:00Z]
  @at ~U[2026-11-02 09:30:00Z]

  defp insert_returning!(table, row) do
    {1, [%{id: id}]} = Repo.insert_all(table, [row], returning: [:id])
    id
  end

  defp package_and_batch do
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

  setup do
    load_vocab!()

    %{
      gall: gall_fixture(),
      other_gall: gall_fixture(),
      source: source_fixture("Kinsey", "1920"),
      other_source: source_fixture("Weld", "1959"),
      origin: package_and_batch()
    }
  end

  defp put(ctx, attrs) do
    attrs =
      Map.merge(
        %{
          gall_id: ctx.gall.id,
          source_id: ctx.source.id,
          package_id: ctx.origin.package_id,
          batch_id: ctx.origin.batch_id,
          trait: "form",
          term: "Swelling",
          evidence: [%{"item" => "#/texts/4", "quote" => "a slight swelling of the twig"}]
        },
        attrs
      )

    Catalog.put_pending_term(test_actor(), attrs)
  end

  test "a term waiting on a question is stored on the Gall, audited", ctx do
    changes = Repo.aggregate(test_audit_changes(), :count)

    assert {:ok,
            %PendingTraitTerm{
              trait: "form",
              term: "Swelling",
              normalized_term: "swelling",
              evidence: [%{"quote" => "a slight swelling of the twig"}],
              settled_at: nil,
              settled_categories: []
            } = pending} = put(ctx, %{statement_ref: "f5"})

    assert Repo.aggregate(test_audit_changes(), :count) == changes + 1
    assert [listed] = Catalog.list_pending_terms(ctx.gall.id)
    assert listed.id == pending.id
    assert listed.statement_ref == "f5"
    assert Catalog.list_pending_terms(ctx.other_gall.id) == []
  end

  test "a Source's term on a Gall waits once: putting it again updates it", ctx do
    {:ok, first} = put(ctx, %{})

    {:ok, again} =
      put(ctx, %{term: "swelling ", evidence: [%{"item" => "#/texts/9", "quote" => "swollen"}]})

    assert again.id == first.id

    assert [%PendingTraitTerm{evidence: [%{"quote" => "swollen"}]}] =
             Catalog.list_pending_terms(ctx.gall.id)

    # Another Source's use waits on its own.
    {:ok, other} = put(ctx, %{source_id: ctx.other_source.id})
    assert other.id != first.id
    assert length(Catalog.list_pending_terms(ctx.gall.id)) == 2
  end

  test "takes a Trait (not generation) and a term", ctx do
    for {attrs, field} <- [
          {%{trait: "generation"}, :trait},
          {%{trait: "size"}, :trait},
          {%{term: "  "}, :term},
          {%{gall_id: nil}, :gall_id}
        ] do
      assert {:error, changeset} = put(ctx, attrs)
      assert Map.has_key?(errors_on(changeset), field), "#{inspect(attrs)}: #{field}"
    end
  end

  test "settling a term under a category settles its waiting uses, returning them", ctx do
    {:ok, a} = put(ctx, %{})
    {:ok, b} = put(ctx, %{gall_id: ctx.other_gall.id, source_id: ctx.other_source.id})
    {:ok, color} = put(ctx, %{trait: "color", term: "swelling"})

    assert {:ok, settled} =
             Catalog.settle_pending_terms(test_actor(), "form", "SWELLING", "stem club", at: @at)

    assert Enum.sort(Enum.map(settled, & &1.id)) == Enum.sort([a.id, b.id])

    assert Enum.uniq(Enum.map(settled, &{&1.settled_at, &1.settled_categories})) ==
             [{@at, ["stem club"]}]

    # Settled terms no longer wait; the other Trait's term still does.
    assert [%PendingTraitTerm{id: id}] = Catalog.list_pending_terms(ctx.gall.id)
    assert id == color.id

    assert [%PendingTraitTerm{settled_categories: ["stem club"]}, _color] =
             Catalog.list_pending_terms(ctx.gall.id, include_settled: true)
             |> Enum.sort_by(& &1.id)

    # Nothing is left to settle.
    assert {:ok, []} = Catalog.settle_pending_terms(test_actor(), "form", "swelling", "stem club")
  end

  test "settling only some Galls' or one Source's uses, or as text", ctx do
    {:ok, a} = put(ctx, %{})
    {:ok, b} = put(ctx, %{gall_id: ctx.other_gall.id})
    {:ok, c} = put(ctx, %{source_id: ctx.other_source.id})

    assert {:ok, [settled]} =
             Catalog.settle_pending_terms(test_actor(), "form", "swelling", "abrupt swelling",
               gall_ids: [ctx.other_gall.id]
             )

    assert settled.id == b.id

    assert {:ok, [settled]} =
             Catalog.settle_pending_terms(test_actor(), "form", "swelling", nil,
               source_id: ctx.other_source.id
             )

    assert settled.id == c.id
    assert settled.settled_categories == []
    assert %DateTime{} = settled.settled_at

    assert [%PendingTraitTerm{id: id}] = Catalog.list_pending_terms(ctx.gall.id)
    assert id == a.id
  end

  test "settles under each value a term names", ctx do
    {:ok, a} = put(ctx, %{trait: "color", term: "green-yellow"})

    assert {:ok, [%PendingTraitTerm{settled_categories: ["green", "yellow"]} = settled]} =
             Catalog.settle_pending_terms(test_actor(), "color", "green-yellow", [
               "green",
               "yellow"
             ])

    assert settled.id == a.id
    assert settled.settled_as == "category"
  end

  test "settles only under a value of the term's Trait", ctx do
    {:ok, _} = put(ctx, %{})

    assert {:error, {:not_a_value, "form", "globular"}} =
             Catalog.settle_pending_terms(test_actor(), "form", "swelling", "globular")

    assert {:error, {:not_a_value, "form", "globular"}} =
             Catalog.settle_pending_terms(test_actor(), "form", "swelling", [
               "stem club",
               "globular"
             ])

    assert [_] = Catalog.list_pending_terms(ctx.gall.id)
  end
end
