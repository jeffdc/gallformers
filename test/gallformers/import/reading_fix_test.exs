defmodule Gallformers.Import.ReadingFixTest do
  @moduledoc """
  Fixing how Gallformers read a Source (matter `87a1`, task 9): a gall batch
  of a Source Gallformers holds (`source.reading_of`), taken in through the
  one ingestion path as a package of that Source. A Fact marked `unstated`
  takes the Source's statement of it away; one that `replaces` it is what
  the Source does say, at the Source's date, its quotes naming the stored
  Source's items. Other Sources' statements stay.

  Not async: the Gallformers Source is unique and the vocabularies are
  loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.DoclingFixtures
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.Batch
  alias Gallformers.Import.Package
  alias Gallformers.Sources
  alias Gallformers.Taxa

  setup :audit_test_metadata

  @misread "Common on Q. lobata throughout the hills"

  setup do
    load_vocab!()
    _gallformers = gallformers_source()
    andricus = Taxa.get_by_legacy_id(:taxonomy, 33)
    wasp = taxon_fixture(name: "Andricus quercuscalifornicus", parent: andricus)
    gall = gall_fixture(name: "Andricus quercuscalifornicus (agamic)", generation: "agamic")
    douglasii = plant_fixture()
    lobata = plant_fixture()
    weld = source_fixture("Weld", "1959")
    kinsey = source_fixture("Kinsey", "1920")

    {:ok, document} = Sources.store_document(test_actor(), weld, DoclingFixtures.document_json())
    item = Sources.get_document_item(document, "#/texts/2")

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
        confirm(kinsey)
      )

    for {source, evidence} <- [
          {weld, [%{document_item_id: item.id, quote: @misread}]},
          {kinsey, []}
        ] do
      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "host_of", subject_taxon_id: douglasii.id, object_gall_id: gall.id},
          confirm(source, %{evidence: evidence})
        )
    end

    %{
      wasp: wasp,
      gall: gall,
      douglasii: douglasii,
      lobata: lobata,
      weld: weld,
      kinsey: kinsey,
      item: item
    }
  end

  # A reading fix of Weld: it doesn't state Host `douglasii` (f1); with
  # `replaces?`, it states Host `lobata` instead (f2), its quote the stored
  # item's.
  defp reading_fix(ctx, replaces? \\ true) do
    quote_evidence = %{"quote" => @misread, "gallformers_document_item_id" => ctx.item.id}

    host = fn id, ref, extra ->
      Map.merge(
        %{
          "id" => id,
          "stance" => "confirm",
          "kind" => "relationship",
          "type" => "host_of",
          "subject" => ref,
          "object" => "g1",
          "evidence" => [quote_evidence]
        },
        extra
      )
    end

    %{
      "format" => "gallformers-import",
      "format_version" => 4,
      "vocabulary_version" => "2026-10-11",
      "batch_type" => "gall",
      "mode" => "add",
      "produced_at" => "2026-11-08T14:00:00Z",
      "producer" => %{"name" => "gallformers-curation", "version" => "1"},
      "source" => %{"reading_of" => %{"gallformers_source_id" => ctx.weld.id}},
      "taxa" => [
        declared("t1", ctx.wasp),
        declared("t2", ctx.douglasii),
        declared("t3", ctx.lobata)
      ],
      "galls" => [
        %{
          "ref" => "g1",
          "name_as_written" => ctx.gall.name,
          "gallformers_gall_id" => ctx.gall.id,
          "identified_by" => %{
            "inducer" => "t1",
            "generation" => %{"value" => "agamic", "as_written" => "agamic"}
          }
        }
      ],
      "facts" =>
        [host.("f1", "t2", %{"unstated" => true})] ++
          if(replaces?, do: [host.("f2", "t3", %{"replaces" => "f1"})], else: [])
    }
  end

  defp declared(ref, taxon) do
    %{
      "ref" => ref,
      "name_as_written" => Taxa.accepted_name(taxon),
      "rank" => "species",
      "gallformers_taxon_id" => taxon.id
    }
  end

  defp host_sources(gall, plant) do
    case Catalog.find_gall_fact(gall.id, {:host, plant.id}) do
      {:ok, nil} -> []
      {:ok, fact_id} -> fact_id |> Facts.list_attributions() |> Enum.map(& &1.source_id)
    end
  end

  test "a misread Host moves to what the Source says, under its authority at its date", ctx do
    assert {:ok, %Package{status: :approved} = package} =
             Import.submit_reading_fix(test_actor(), %{"gall.json" => reading_fix(ctx)})

    assert package.source_id == ctx.weld.id
    assert [%Batch{status: :applied, mode: :add}] = Import.list_batches(package)

    assert host_sources(ctx.gall, ctx.douglasii) == [ctx.kinsey.id]
    assert host_sources(ctx.gall, ctx.lobata) == [ctx.weld.id]

    {:ok, fact_id} = Catalog.find_gall_fact(ctx.gall.id, {:host, ctx.lobata.id})
    assert [weld] = Facts.list_attributions(fact_id)
    assert weld.stated_on == ~D[1959-01-01]
    assert weld.stance == :confirm
    assert [%{quote: @misread, document_item_id: item_id}] = weld.evidence
    assert item_id == ctx.item.id
  end

  test "an unstated Fact alone takes the Source's statement away", ctx do
    assert {:ok, %Package{status: :approved}} =
             Import.submit_reading_fix(test_actor(), %{"gall.json" => reading_fix(ctx, false)})

    assert host_sources(ctx.gall, ctx.douglasii) == [ctx.kinsey.id]
    assert host_sources(ctx.gall, ctx.lobata) == []
  end

  test "a misread Trait value moves to the value the Source gives", ctx do
    item_id = ctx.item.id

    {:ok, _} =
      Catalog.assert_trait(
        test_actor(),
        %{gall_id: ctx.gall.id, trait: "color", value: "red"},
        confirm(ctx.weld, %{evidence: [%{document_item_id: item_id, quote: @misread}]})
      )

    trait = fn id, value, extra ->
      Map.merge(
        %{
          "id" => id,
          "stance" => "confirm",
          "kind" => "trait",
          "gall" => "g1",
          "trait" => "color",
          "value" => %{"value" => value, "as_written" => value},
          "evidence" => [%{"quote" => @misread, "gallformers_document_item_id" => item_id}]
        },
        extra
      )
    end

    fix =
      reading_fix(ctx, false)
      |> Map.put("format_version", 3)
      |> Map.put("facts", [
        trait.("f1", "red", %{"unstated" => true}),
        trait.("f2", "brown", %{"replaces" => "f1"})
      ])

    assert {:ok, %Package{status: :approved}} =
             Import.submit_reading_fix(test_actor(), %{"gall.json" => fix})

    sources = fn value ->
      case Catalog.find_gall_fact(ctx.gall.id, {:trait, "color", value}) do
        {:ok, nil} -> []
        {:ok, id} -> id |> Facts.list_attributions() |> Enum.map(& &1.source_id)
      end
    end

    assert sources.("red") == []
    assert sources.("brown") == [ctx.weld.id]
  end

  test "only reading fixes are taken", ctx do
    gallformers = Map.put(reading_fix(ctx, false), "source", %{"gallformers" => true})

    assert {:error, :not_a_reading_fix} =
             Import.submit_reading_fix(test_actor(), %{"gall.json" => gallformers})

    assert {:error, :not_a_reading_fix} = Import.submit_reading_fix(test_actor(), %{})
    assert %{total: 0} = Import.list_packages()
  end

  # A taxonomic statement misread (matter 87a1): the paper places Aphis
  # rubifolii under Amphorophora, not Aphis.
  describe "a taxonomic reading fix" do
    setup ctx do
      legacy = Sources.get_legacy_data_source()
      family = taxon_fixture(rank: :family, name: "Aphididae", kingdom: "Animalia")
      aphis = taxon_fixture(rank: :genus, name: "Aphis", kingdom: "Animalia", parent: family)

      other =
        taxon_fixture(rank: :genus, name: "Amphorophora", kingdom: "Animalia", parent: family)

      species = taxon_fixture(name: "Aphis rubifolii", kingdom: "Animalia", parent: aphis)

      for taxon <- [family, aphis, other, species] do
        taxon = Taxa.get_taxon!(taxon.id)
        key = %{taxon_id: taxon.id, parent_id: taxon.parent_id}
        {:ok, _} = Taxa.assert_placement(test_actor(), key, confirm(legacy, %{stated: nil}))
      end

      {:ok, %{attribution: attribution}} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: species.id, parent_id: aphis.id},
          confirm(ctx.weld, %{evidence: [%{document_item_id: ctx.item.id, quote: @misread}]})
        )

      {:ok, _} = Import.TaxonomicDecisions.decide(test_actor(), :accept, attribution.id)
      %{species: species, aphis: aphis, other: other}
    end

    defp taxonomy_fix(ctx, accept?) do
      act = fn id, parent, extra ->
        Map.merge(
          %{
            "id" => id,
            "stance" => "confirm",
            "kind" => "placement",
            "taxon" => "t1",
            "parent" => parent,
            "evidence" => [%{"quote" => @misread, "gallformers_document_item_id" => ctx.item.id}]
          },
          extra
        )
      end

      reading_of = %{"gallformers_source_id" => ctx.weld.id}

      reading_fix(ctx)
      |> Map.drop(["galls", "facts"])
      |> Map.merge(%{
        "batch_type" => "taxonomy",
        "source" => %{
          "reading_of" => if(accept?, do: Map.put(reading_of, "accept", true), else: reading_of)
        },
        "taxa" => [
          declared("t1", ctx.species),
          declared("t2", ctx.aphis) |> Map.put("rank", "genus"),
          declared("t3", ctx.other) |> Map.put("rank", "genus")
        ],
        "acts" => [
          act.("a1", "t2", %{"unstated" => true}),
          act.("a2", "t3", %{"replaces" => "a1"})
        ]
      })
    end

    defp placed_by(species, parent, source) do
      {:ok, id} = Taxa.find_act_fact(:placement, %{taxon_id: species.id, parent_id: parent.id})
      id && Facts.get_attribution(id, source.id)
    end

    test "accepted in the same step: the Source's placement moves, and the tree follows", ctx do
      assert {:ok, %Package{status: :approved}} =
               Import.submit_reading_fix(test_actor(), %{
                 "taxonomy.json" => taxonomy_fix(ctx, true)
               })

      assert placed_by(ctx.species, ctx.aphis, ctx.weld) == nil
      assert %{accepted_at: %DateTime{}} = placed_by(ctx.species, ctx.other, ctx.weld)
      assert Taxa.get_taxon!(ctx.species.id).parent_id == ctx.other.id
    end

    test "not accepted: the moved statement awaits a curator", ctx do
      assert {:ok, %Package{}} =
               Import.submit_reading_fix(test_actor(), %{
                 "taxonomy.json" => taxonomy_fix(ctx, false)
               })

      assert %{accepted_at: nil} = placed_by(ctx.species, ctx.other, ctx.weld)
      assert Taxa.get_taxon!(ctx.species.id).parent_id == ctx.aphis.id
    end
  end

  test "a Source with no quotes is fixed with none: the legacy data's Host goes", ctx do
    legacy = Sources.get_legacy_data_source()

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: ctx.douglasii.id, object_gall_id: ctx.gall.id},
        confirm(legacy, %{stated: nil})
      )

    fix =
      reading_fix(ctx, false)
      |> put_in(["source", "reading_of", "gallformers_source_id"], legacy.id)
      |> update_in(["facts"], fn facts -> Enum.map(facts, &Map.put(&1, "evidence", [])) end)

    assert {:ok, %Package{status: :approved}} =
             Import.submit_reading_fix(test_actor(), %{"gall.json" => fix})

    assert Enum.sort(host_sources(ctx.gall, ctx.douglasii)) ==
             Enum.sort([ctx.weld.id, ctx.kinsey.id])
  end
end
