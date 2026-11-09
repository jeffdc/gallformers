defmodule Gallformers.Import.FactHistoryTest do
  @moduledoc """
  A Fact's history (matter `87a1`, "A Fact's history in the inspector"):
  each change to it, newest first, in plain words, from the audit trail:
  a Source stating it or saying it isn't so, a reading of a Source fixed,
  the Fact withdrawn or current again; and the statements the audit trail
  has no record of (the old site's data), last.

  Not async: the Gallformers Source is unique.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog
  alias Gallformers.Import
  alias Gallformers.Sources

  setup :audit_test_metadata

  setup do
    load_vocab!()
    gallformers = gallformers_source()
    weld = source_fixture("Weld", "1959")
    gall = gall_fixture()
    oak = plant_fixture()

    %{gallformers: gallformers, weld: weld, gall: gall, oak: oak}
  end

  defp host!(ctx, attribution) do
    {:ok, %{fact: fact}} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: ctx.oak.id, object_gall_id: ctx.gall.id},
        attribution
      )

    fact
  end

  defp words(fact), do: fact.id |> Import.fact_history() |> Enum.map(&{&1.what, &1.who})

  test "a Source stating it, Gallformers saying it isn't so, the Fact withdrawn: newest first",
       ctx do
    fact = host!(ctx, confirm(ctx.weld))
    host!(ctx, deny(ctx.gallformers, %{stated: "2026-11-08", statement_text: "Not on oaks."}))

    weld = Sources.short_name(ctx.weld) || ctx.weld.title

    assert [
             {"Withdrawn", nil},
             {"Gallformers said it isn't so", "test"},
             {^weld <> " stated it", "test"}
           ] = words(fact) |> Enum.reject(&match?({"Added", _}, &1))
  end

  test "the statements the audit trail has no record of are the original data, undated, last",
       ctx do
    legacy = Sources.get_legacy_data_source()
    fact = host!(ctx, confirm(legacy, %{stated: nil}))
    host!(ctx, confirm(ctx.weld))

    Repo.query!(
      "DELETE FROM carbonite_default.changes WHERE table_name = 'attributions' AND (data->>'source_id')::bigint = $1",
      [legacy.id]
    )

    assert %{what: "In Gallformers' original data", at: nil, who: nil} =
             List.last(Import.fact_history(fact.id))
  end

  test "what the catalog migration loaded is the original data, undated, with no one named",
       ctx do
    legacy = Sources.get_legacy_data_source()
    fact = host!(ctx, confirm(legacy, %{stated: nil}))

    Repo.query!(
      ~s|UPDATE carbonite_default.transactions SET meta = jsonb_set(jsonb_set(meta, '{operation}', '"catalog_migration.legacy_facts"'), '{actor,name}', '"catalog_migration"')|
    )

    assert [%{what: "In Gallformers' original data", at: nil, who: nil}] =
             Import.fact_history(fact.id)
  end

  test "a Source's statement taken away by fixing our reading of it", ctx do
    wasp =
      Gallformers.TaxaFixtures.taxon_fixture(name: "Andricus historicus", kingdom: "Animalia")

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: ctx.gall.id},
        confirm(ctx.weld)
      )

    fact = host!(ctx, confirm(ctx.weld))

    declared = fn ref, t, rank ->
      %{
        "ref" => ref,
        "name_as_written" => Gallformers.Taxa.accepted_name(t),
        "rank" => rank,
        "gallformers_taxon_id" => t.id
      }
    end

    fix = %{
      "format" => "gallformers-import",
      "format_version" => 3,
      "vocabulary_version" => "2026-10-11",
      "batch_type" => "gall",
      "mode" => "add",
      "produced_at" => "2026-11-08T14:00:00Z",
      "producer" => %{"name" => "gallformers-curation", "version" => "1"},
      "source" => %{"reading_of" => %{"gallformers_source_id" => ctx.weld.id}},
      "taxa" => [declared.("t1", wasp, "species"), declared.("t2", ctx.oak, "species")],
      "galls" => [
        %{
          "ref" => "g1",
          "name_as_written" => ctx.gall.name,
          "gallformers_gall_id" => ctx.gall.id,
          "identified_by" => %{"inducer" => "t1"}
        }
      ],
      "facts" => [
        %{
          "id" => "f1",
          "stance" => "confirm",
          "kind" => "relationship",
          "type" => "host_of",
          "subject" => "t2",
          "object" => "g1",
          "unstated" => true,
          "evidence" => []
        }
      ]
    }

    assert {:ok, _package} = Import.submit_reading_fix(test_actor(), %{"gall.json" => fix})

    weld = Sources.short_name(ctx.weld) || ctx.weld.title
    assert {weld <> ": our reading fixed, it doesn't say this", "test"} in words(fact)
  end
end
