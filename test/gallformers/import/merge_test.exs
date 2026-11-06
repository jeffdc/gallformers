defmodule Gallformers.Import.MergeTest do
  @moduledoc """
  Merging a Gall or a plant recorded twice (matter `ec2c`, "Deletes": "What
  a Gall merge does", "Plant merges"): the curator picks the survivor; the
  absorbed record's Facts move to it with their attributions, the same
  Fact on both combines its Sources, single-valued disagreements follow
  recency and same-date ties become curator questions; the absorbed name
  becomes an alias or synonym and its ID (and code) redirect. A preview
  shows it all first, writing nothing. Audited and replayed.

  Not async: the tests load the vocabularies and use the Gallformers Source.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Facts
  alias Gallformers.Facts.Fact
  alias Gallformers.Images
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.Replay
  alias Gallformers.Ranges
  alias Gallformers.Sources
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    load_vocab!()

    %{
      legacy: Sources.get_legacy_data_source(),
      gallformers: Sources.get_gallformers_source(),
      weld: source_fixture("Weld", "1959"),
      kinsey: source_fixture("Kinsey", "1930")
    }
  end

  defp uniq, do: System.unique_integer([:positive])

  defp trait!(gall, value, source, trait \\ "detachable", extra \\ %{}) do
    {:ok, %{fact: fact}} =
      Catalog.assert_trait(
        test_actor(),
        %{gall_id: gall.id, trait: trait, value: value},
        Map.merge(confirm(source), extra)
      )

    fact
  end

  defp host!(plant, gall, source) do
    {:ok, %{fact: fact}} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: plant.id, object_gall_id: gall.id},
        confirm(source)
      )

    fact
  end

  defp image!(owner) do
    {:ok, image} =
      Images.create_image(
        Map.merge(Images.Image.owner_attrs(owner), %{
          path: "gall/#{uniq()}/original.jpg",
          creator: "Tester",
          license: "CC0"
        })
      )

    image
  end

  defp gall_fact(gall, key) do
    {:ok, id} = Catalog.find_gall_fact(gall.id, key)
    id && Repo.get!(Fact, id)
  end

  defp sources_of(nil), do: []

  defp sources_of(fact),
    do: fact.id |> Facts.list_attributions() |> Enum.map(& &1.source_id) |> Enum.sort()

  describe "merging Galls" do
    setup ctx do
      oak = plant_fixture()
      absorbed = gall_fixture(gallformers_code: "ABS#{uniq()}")
      survivor = gall_fixture(gallformers_code: "SUR#{uniq()}")
      Map.merge(ctx, %{oak: oak, absorbed: absorbed, survivor: survivor})
    end

    test "Facts move with their attributions; the same Fact combines its Sources", ctx do
      host!(ctx.oak, ctx.absorbed, ctx.weld)
      host!(ctx.oak, ctx.survivor, ctx.kinsey)
      trait!(ctx.absorbed, "red", ctx.weld, "color")
      image!({:gall, ctx.absorbed.id})
      image!({:gall, ctx.survivor.id})

      assert {:ok, result} =
               Import.record_merge(test_actor(), {:gall, ctx.absorbed.id, ctx.survivor.id})

      assert result.absorbed.id == ctx.absorbed.id
      assert result.survivor.id == ctx.survivor.id
      assert Catalog.get_gall(ctx.absorbed.id) == nil

      host = gall_fact(ctx.survivor, {:host, ctx.oak.id})
      assert sources_of(host) == Enum.sort([ctx.weld.id, ctx.kinsey.id])

      assert sources_of(gall_fact(ctx.survivor, {:trait, "color", "red"})) == [ctx.weld.id]
      assert length(Images.list_images_for_gall(ctx.survivor.id)) == 2

      # The absorbed name is an alias; its ID and code redirect.
      assert gall_fact(ctx.survivor, {:alias, ctx.absorbed.name})
      assert Catalog.gall_redirect(ctx.absorbed.id) == ctx.survivor.id
      assert Catalog.gall_redirect(ctx.absorbed.gallformers_code) == ctx.survivor.id
      assert Catalog.get_gall!(ctx.survivor.id).gallformers_code == ctx.survivor.gallformers_code

      assert [entry] = for(e <- Import.list_replay_entries(), e.kind == :merge, do: e)

      assert entry.key == %{
               "type" => "gall",
               "absorbed" => %{"id" => ctx.absorbed.id},
               "survivor" => %{"id" => ctx.survivor.id}
             }
    end

    test "the preview shows it all and writes nothing", ctx do
      host!(ctx.oak, ctx.absorbed, ctx.weld)
      host!(ctx.oak, ctx.survivor, ctx.kinsey)
      image!({:gall, ctx.absorbed.id})

      assert {:ok, preview} =
               Import.merge_preview({:gall, ctx.absorbed.id, ctx.survivor.id}, test_actor())

      assert [%{outcome: :combined, sources: [%{id: weld_id, outcome: :moved}]}] =
               Enum.filter(preview.facts, &(&1.kind == "gall_relationship"))

      assert weld_id == ctx.weld.id
      assert preview.alias == ctx.absorbed.name
      assert preview.redirects == %{id: ctx.absorbed.id, code: ctx.absorbed.gallformers_code}
      assert preview.images == 1
      assert preview.blockers == []

      assert %Gall{} = Catalog.get_gall(ctx.absorbed.id)
      assert Catalog.gall_redirect(ctx.absorbed.id) == nil
      assert Import.list_replay_entries() |> Enum.filter(&(&1.kind == :merge)) == []
    end

    test "a single-valued disagreement follows recency", ctx do
      trait!(ctx.survivor, "integral", ctx.kinsey)
      trait!(ctx.absorbed, "detachable", ctx.weld)

      assert {:ok, _} =
               Import.record_merge(test_actor(), {:gall, ctx.absorbed.id, ctx.survivor.id})

      # Weld 1959 is newer than Kinsey 1930.
      assert gall_fact(ctx.survivor, {:trait, "detachable", "detachable"}).standing == :current
      assert gall_fact(ctx.survivor, {:trait, "detachable", "integral"}).standing != :current
    end

    test "a same-date tie becomes a curator question", ctx do
      other = source_fixture("Other", "1959")
      trait!(ctx.survivor, "integral", other)
      trait!(ctx.absorbed, "detachable", ctx.weld)

      assert {:ok, result} =
               Import.record_merge(test_actor(), {:gall, ctx.absorbed.id, ctx.survivor.id})

      assert [item_id] = result.queued
      item = Repo.get!(QueueItem, item_id)
      assert item.kind == :same_date_conflict
      assert item.package_id == nil
      assert item.subject["gall_id"] == ctx.survivor.id

      assert item.statement_ref =~ "merge:"
      assert item.subject["fact_ids"] |> length() == 2

      # Deciding it is logged and replayable like any decision.
      assert {:ok, _} = Import.decide_queue_item(test_actor(), item, %{})

      assert [entry] = for(e <- Import.list_replay_entries(), e.kind == :queue_decision, do: e)

      assert entry.key == %{
               "kind" => "same_date_conflict",
               "merge" => true,
               "gall" => %{"id" => ctx.survivor.id},
               "statement_ref" => item.statement_ref
             }

      # Decided already: replaying the decision is skipped.
      assert {:ok, 1} = Replay.run([entry], actor: test_actor())
    end

    test "Galls pointing at the absorbed one are re-pointed", ctx do
      other = gall_fixture()

      {:ok, %{fact: _}} =
        Catalog.assert_relationship(
          test_actor(),
          %{
            type: "alternate_generation_of",
            subject_gall_id: other.id,
            object_gall_id: ctx.absorbed.id
          },
          confirm(ctx.weld)
        )

      assert {:ok, result} =
               Import.record_merge(test_actor(), {:gall, ctx.absorbed.id, ctx.survivor.id})

      assert [%{gall_id: other_id}] = result.repointed
      assert other_id == other.id

      {:ok, fact_id} =
        Catalog.find_fact(:relationship, %{
          type: "alternate_generation_of",
          subject_gall_id: other.id,
          object_gall_id: ctx.survivor.id
        })

      assert sources_of(Repo.get!(Fact, fact_id)) == [ctx.weld.id]
    end

    test "both Gallformers notes: the absorbed one is appended as a new version", ctx do
      gf = ctx.gallformers
      {:ok, _} = Sources.store_note(test_actor(), gf, ctx.survivor.id, "Survivor note.")
      {:ok, _} = Sources.store_note(test_actor(), gf, ctx.absorbed.id, "Absorbed note.")

      assert {:ok, %{note: :appended}} =
               Import.record_merge(test_actor(), {:gall, ctx.absorbed.id, ctx.survivor.id})

      [newest | _] = Sources.list_gall_notes(ctx.survivor.id)
      [item] = Sources.list_document_items(newest)
      assert item.text =~ "Survivor note."
      assert item.text =~ "From the merged #{ctx.absorbed.name} gall"
      assert item.text =~ "Absorbed note."
    end

    test "an open question naming the absorbed Gall blocks it", ctx do
      Repo.insert!(%QueueItem{
        kind: :gall_rename,
        subject: %{"gall_id" => -1, "x" => %{"gall_id" => ctx.absorbed.id}},
        proposal: %{}
      })

      assert {:error, {:blocked, [%{kind: :open_question}]}} =
               Import.record_merge(test_actor(), {:gall, ctx.absorbed.id, ctx.survivor.id})

      assert %Gall{} = Catalog.get_gall(ctx.absorbed.id)
    end

    test "errors", ctx do
      assert Import.record_merge(test_actor(), {:gall, ctx.absorbed.id, ctx.absorbed.id}) ==
               {:error, :same_record}

      assert Import.merge_preview({:gall, -1, ctx.survivor.id}, test_actor()) ==
               {:error, :not_found}
    end

    test "replays", ctx do
      host!(ctx.oak, ctx.absorbed, ctx.legacy)
      Repo.query!("DELETE FROM replay_log")

      assert {:ok, _} =
               Import.record_merge(test_actor(), {:gall, ctx.absorbed.id, ctx.survivor.id})

      # Done already: skipped.
      assert {:ok, 1} = Replay.run(Import.list_replay_entries(), actor: test_actor())
    end
  end

  describe "merging plants" do
    setup ctx do
      genus = plant_fixture(rank: :genus, name: "Mergea#{uniq()}")
      g = Taxa.accepted_name(genus)
      absorbed = plant_fixture(name: "#{g} alba", parent: genus)
      survivor = plant_fixture(name: "#{g} albida", parent: genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), absorbed, "#{g} candida")
      gall = gall_fixture()
      Map.merge(ctx, %{absorbed: absorbed, survivor: survivor, gall: gall, genus_name: g})
    end

    test "synonyms combine, Host Facts move, the range stays the survivor's", ctx do
      host!(ctx.absorbed, ctx.gall, ctx.weld)
      host_range_fixture(ctx.absorbed, [{"US-CA", "exact"}])
      host_range_fixture(ctx.survivor, [{"MX-JAL", "exact"}])

      assert {:ok, preview} =
               Import.merge_preview({:plant, ctx.absorbed.id, ctx.survivor.id}, test_actor())

      assert "#{ctx.genus_name} alba" in preview.synonyms
      assert "#{ctx.genus_name} candida" in preview.synonyms

      assert {:ok, _} =
               Import.record_merge(test_actor(), {:plant, ctx.absorbed.id, ctx.survivor.id})

      assert Taxa.get_taxon(ctx.absorbed.id) == nil
      names = Enum.map(Taxa.list_synonyms(ctx.survivor), & &1.name)
      assert "#{ctx.genus_name} alba" in names
      assert "#{ctx.genus_name} candida" in names

      assert sources_of(gall_fact(ctx.gall, {:host, ctx.survivor.id})) == [ctx.weld.id]

      assert [%{place_id: place}] = Ranges.get_places_for_taxon_with_precision(ctx.survivor.id)
      assert place == place_id("MX-JAL")

      assert Taxa.taxon_redirect(ctx.absorbed.id) == ctx.survivor.id

      assert [%{key: %{"type" => "plant"}}] =
               for(e <- Import.list_replay_entries(), e.kind == :merge, do: e)
    end

    test "a Gall named for the absorbed plant is named for the survivor", ctx do
      named =
        gall_fixture(name_override: "Named #{uniq()}", host_qualifier_taxon_id: ctx.absorbed.id)

      assert {:ok, %{galls_requalified: [id]}} =
               Import.record_merge(test_actor(), {:plant, ctx.absorbed.id, ctx.survivor.id})

      assert id == named.id
      assert Catalog.get_gall!(named.id).host_qualifier_taxon_id == ctx.survivor.id
    end

    test "only plants merge" do
      a = taxon_fixture(name: "Insecta one #{uniq()}")
      b = taxon_fixture(name: "Insecta two #{uniq()}")
      assert Import.merge_preview({:plant, a.id, b.id}, test_actor()) == {:error, :not_a_plant}
    end
  end
end
