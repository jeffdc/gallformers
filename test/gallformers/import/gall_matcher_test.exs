defmodule Gallformers.Import.GallMatcherTest do
  @moduledoc """
  Matching a batch's Galls to Gall entries (`9449` Task 12; producer guide
  background, *What Gallformers does on import* step 4): by `identified_by`
  (Inducer, generation, Host, plant part) against the Galls' current
  Inducer, Hosts, generation and plant parts; undescribed Galls by genus,
  Host and the descriptive words of the entry's name. One candidate of an
  undescribed Gall is proposed, several offered; nothing ambiguous is
  resolved.

  Not async: the tests load the vocabularies (`Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Import.GallMatcher
  alias Gallformers.Import.Proposals
  alias Gallformers.Import.Queue
  alias Gallformers.Import.QueueItem
  alias Gallformers.Repo

  setup :audit_test_metadata

  setup do
    load_vocab!()
    %{source: source_fixture("Weld", "1959")}
  end

  defp inducer!(taxon, gall, source) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: taxon.id, object_gall_id: gall.id},
        confirm(source)
      )
  end

  defp host!(plant, gall, source) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: plant.id, object_gall_id: gall.id},
        confirm(source)
      )
  end

  defp plant_part!(gall, value, source) do
    {:ok, _} =
      Catalog.assert_trait(
        test_actor(),
        %{gall_id: gall.id, trait: "plant_part", value: value},
        confirm(source)
      )
  end

  # A resolved taxon statement, as the Resolver gives it.
  defp resolved(ref, taxon, rank \\ "species", host? \\ false) do
    %{
      kind: :taxon,
      ref: ref,
      resolution: :resolved,
      method: "exact",
      taxon_id: taxon.id,
      candidate_ids: [],
      flags: [],
      detail: %{"rank" => rank, "host" => host?, "name_as_written" => "x"}
    }
  end

  defp statement(ref, resolution, name, rank \\ "species") do
    %{
      kind: :taxon,
      ref: ref,
      resolution: resolution,
      method: nil,
      taxon_id: nil,
      candidate_ids: [],
      flags: [],
      detail: %{"rank" => rank, "name_as_written" => name}
    }
  end

  defp gall(ref, identified_by, extra \\ %{}) do
    Map.merge(
      %{"ref" => ref, "name_as_written" => "the gall", "identified_by" => identified_by},
      extra
    )
  end

  defp generation(value), do: %{"value" => value, "as_written" => value}

  defp match(galls, taxa, facts \\ []) do
    %{"batch_type" => "gall", "galls" => galls, "facts" => facts}
    |> GallMatcher.match_galls(taxa)
    |> by_ref()
  end

  defp by_ref(statements), do: Map.new(statements, &{&1.ref, &1})

  describe "described Galls" do
    setup %{source: source} do
      wasp = taxon_fixture(name: "Andricus quercuscalifornicus", kingdom: "Animalia")
      agamic = gall_fixture(name: "Andricus quercuscalifornicus (agamic)", generation: "agamic")
      sexual = gall_fixture(name: "Andricus quercuscalifornicus (sexgen)", generation: "sexual")
      inducer!(wasp, agamic, source)
      inducer!(wasp, sexual, source)
      %{wasp: wasp, agamic: agamic, sexual: sexual}
    end

    test "the generation tells two Galls of one Inducer apart", ctx do
      taxa = [resolved("t1", ctx.wasp)]

      %{"g1" => s} =
        match([gall("g1", %{"inducer" => "t1", "generation" => generation("agamic")})], taxa)

      assert s.kind == :gall
      assert s.resolution == :resolved
      assert s.method == "identified_by"
      assert s.gall_id == ctx.agamic.id

      %{"g1" => s} =
        match([gall("g1", %{"inducer" => "t1", "generation" => generation("sexual")})], taxa)

      assert s.gall_id == ctx.sexual.id
    end

    test "a generation the Source never names is ambiguous, with the candidates and a reason",
         ctx do
      %{"g1" => s} = match([gall("g1", %{"inducer" => "t1"})], [resolved("t1", ctx.wasp)])

      assert s.resolution == :ambiguous
      assert s.gall_id == nil
      assert Enum.sort(s.candidate_ids) == Enum.sort([ctx.agamic.id, ctx.sexual.id])
      assert s.detail["reason"] =~ "generation"
    end

    test "an Inducer with no Galls: new when the Source says so, else unresolved", ctx do
      other = taxon_fixture(name: "Andricus nogalls", kingdom: "Animalia")
      taxa = [resolved("t1", other)]

      %{"g1" => s} = match([gall("g1", %{"inducer" => "t1"}, %{"new" => true})], taxa)
      assert s.resolution == :new

      %{"g1" => s} = match([gall("g1", %{"inducer" => "t1"})], taxa)
      assert s.resolution == :unresolved
      assert ctx.wasp.id != other.id
    end

    test "two of the batch's Galls matching one entry are both a curator's decision", ctx do
      # Equal identifying fields (Jeff, 2026-10-28: an admin decides; no tiers yet).
      ident = %{"inducer" => "t1", "generation" => generation("agamic")}

      matches =
        match(
          [
            gall("g1", ident, %{"name_as_written" => "the terminal stem gall"}),
            gall("g2", ident, %{"name_as_written" => "the cryptic stem gall"})
          ],
          [resolved("t1", ctx.wasp)]
        )

      for ref <- ["g1", "g2"] do
        s = matches[ref]
        assert s.resolution == :ambiguous
        assert s.gall_id == nil
        assert s.candidate_ids == [ctx.agamic.id]
        assert s.detail["reason"] =~ "another of this batch's Galls"
      end
    end

    test "an unresolved Inducer leaves the Gall unresolved" do
      %{"g1" => s} =
        match([gall("g1", %{"inducer" => "t1"})], [statement("t1", :unresolved, "Nonesuch")])

      assert s.resolution == :unresolved
    end

    test "a lone Gall of a generation the Source never names is proposed, not resolved, " <>
           "when its Inducer alternates generations",
         %{source: source} do
      tribe = taxon_fixture(name: "Cynipini", rank: :tribe, kingdom: "Animalia")
      genus = taxon_fixture(name: "Acraspis", rank: :genus, kingdom: "Animalia", parent: tribe)
      wasp = taxon_fixture(name: "Acraspis lonely", kingdom: "Animalia", parent: genus)
      sexual = gall_fixture(name: "Acraspis lonely (sexgen)", generation: "sexual")
      inducer!(wasp, sexual, source)

      %{"g1" => s} = match([gall("g1", %{"inducer" => "t1"})], [resolved("t1", wasp)])
      assert s.resolution == :resolved

      heterogony = Enum.find(Catalog.list_generation_groups(), &(&1.name == "heterogony"))
      Repo.insert_all("generation_group_taxa", [%{group_id: heterogony.id, taxon_id: tribe.id}])

      %{"g1" => s} = match([gall("g1", %{"inducer" => "t1"})], [resolved("t1", wasp)])
      assert s.resolution == :ambiguous
      assert s.gall_id == nil
      assert s.candidate_ids == [sexual.id]
      assert s.detail["proposed"] == sexual.id
      assert s.detail["reason"] =~ "generation"

      # Named, the generation settles it.
      %{"g1" => s} =
        match(
          [gall("g1", %{"inducer" => "t1", "generation" => generation("sexual")})],
          [resolved("t1", wasp)]
        )

      assert s.resolution == :resolved
      assert s.gall_id == sexual.id
    end
  end

  describe "Galls waiting on their Inducer" do
    setup %{source: source} do
      wasp = taxon_fixture(name: "Andricus waiting", kingdom: "Animalia")
      entry = gall_fixture(name: "Andricus waiting gall")
      inducer!(wasp, entry, source)
      %{wasp: wasp, entry: entry}
    end

    test "an unresolved, ambiguous or held-valid Inducer: flagged, not queued on its own" do
      ambiguous = %{statement("t1", :ambiguous, "Andricus dup") | candidate_ids: [1, 2]}

      held_valid = %{
        statement("t1", :unresolved, "Cynips held")
        | candidate_ids: [3],
          flags: ["synonym_held_valid"]
      }

      for inducer <- [statement("t1", :unresolved, "Nonesuch"), ambiguous, held_valid] do
        statements =
          [gall("g1", %{"inducer" => "t1"})]
          |> match([inducer])
          |> Map.values()

        [s] = statements
        assert s.resolution == :unresolved
        assert "waits_on_inducer" in s.flags
        assert s.detail["waits_on"] == "t1"
        assert GallMatcher.queue_items(statements) == []
      end
    end

    test "a decided Inducer: the Gall is matched", ctx do
      decided = %{resolved("t1", ctx.wasp) | method: "decision"}
      %{"g1" => s} = match([gall("g1", %{"inducer" => "t1"})], [decided])

      assert s.resolution == :resolved
      assert s.gall_id == ctx.entry.id
      refute "waits_on_inducer" in s.flags
    end

    test "a skipped Inducer: the Gall is queued on its own" do
      skipped = %{statement("t1", :unresolved, "Nonesuch") | flags: ["skipped"]}
      statements = [gall("g1", %{"inducer" => "t1"})] |> match([skipped]) |> Map.values()

      [s] = statements
      assert s.resolution == :unresolved
      refute "waits_on_inducer" in s.flags
      assert s.detail["reason"] =~ "skipped"

      assert [%{kind: :unresolved_name, statement_ref: "g1"}] =
               GallMatcher.queue_items(statements)
    end
  end

  describe "generation pairs" do
    setup %{source: source} do
      aphid = taxon_fixture(name: "Pachypappa pairedi", kingdom: "Animalia")
      entry = gall_fixture(name: "Pachypappa pairedi")
      inducer!(aphid, entry, source)

      galls = [
        gall("g2", %{"inducer" => "t1", "generation" => generation("fundatrix")}, %{
          "name_as_written" => "Gall formed by stem mother"
        }),
        gall("g3", %{"inducer" => "t1", "generation" => generation("apterae")}, %{
          "name_as_written" => "Gall formed by apterae"
        })
      ]

      %{aphid: aphid, entry: entry, galls: galls}
    end

    test "two Galls of different generations matching one entry with none are one item", ctx do
      matches = match(ctx.galls, [resolved("t1", ctx.aphid)])

      for ref <- ["g2", "g3"] do
        assert matches[ref].resolution == :ambiguous
        assert matches[ref].candidate_ids == [ctx.entry.id]
      end

      assert matches["g2"].detail["pair"]["ref"] == "g3"
      assert matches["g2"].detail["pair"]["generation"] == "apterae"
      assert matches["g3"].detail["pair"]["ref"] == "g2"
      assert "paired_with_gall" in matches["g3"].flags
      refute "paired_with_gall" in matches["g2"].flags

      assert [item] = GallMatcher.queue_items(Map.values(matches))
      assert item.kind == :ambiguous_match
      assert item.statement_ref == "g2"
      assert item.proposal["candidate_ids"] == [ctx.entry.id]
      assert item.proposal["pair"]["ref"] == "g3"
      assert item.reason =~ "the other is new"
    end

    test "deciding one of a pair settles the other", ctx do
      matches = match(ctx.galls, [resolved("t1", ctx.aphid)])

      decide = fn decision ->
        for s <- Map.values(matches),
            do: if(s.ref == "g2", do: Queue.apply_decision(s, decision), else: s)
      end

      settled = decide.(%{"gall_id" => ctx.entry.id}) |> GallMatcher.settle_pairs() |> by_ref()
      assert settled["g2"].resolution == :resolved
      assert settled["g3"].resolution == :new

      settled = decide.(%{"new" => true}) |> GallMatcher.settle_pairs() |> by_ref()
      assert settled["g2"].resolution == :new
      assert settled["g3"].resolution == :resolved
      assert settled["g3"].gall_id == ctx.entry.id

      # g2's own item is decided (the resolve step leaves it out); g3 is queued.
      settled = decide.(%{"skip" => true}) |> GallMatcher.settle_pairs()
      assert "g3" in Enum.map(GallMatcher.queue_items(settled), & &1.statement_ref)

      refute settled
             |> by_ref()
             |> Map.fetch!("g3")
             |> Map.fetch!(:detail)
             |> Map.has_key?("pair")

      # Undecided, nothing changes.
      assert matches |> Map.values() |> GallMatcher.settle_pairs() |> by_ref() == matches
    end

    test "Galls with equal identifying fields are not a pair", ctx do
      ident = %{"inducer" => "t1", "generation" => generation("fundatrix")}
      matches = match([gall("g2", ident), gall("g3", ident)], [resolved("t1", ctx.aphid)])

      refute Map.has_key?(matches["g2"].detail, "pair")
      assert length(GallMatcher.queue_items(Map.values(matches))) == 2
    end
  end

  describe "Host and plant part" do
    test "break a tie between Galls of one Inducer", %{source: source} do
      wasp = taxon_fixture(name: "Antistrophus rufus", kingdom: "Animalia")
      plant = plant_fixture(name: "Silphium laciniatum")
      other_plant = plant_fixture(name: "Silphium perfoliatum")
      collar = gall_fixture(name: "Antistrophus rufus collar gall")
      spindle = gall_fixture(name: "Antistrophus rufus spindle gall")
      elsewhere = gall_fixture(name: "Antistrophus rufus other-host gall")

      for g <- [collar, spindle, elsewhere], do: inducer!(wasp, g, source)
      host!(plant, collar, source)
      host!(plant, spindle, source)
      host!(other_plant, elsewhere, source)
      plant_part!(collar, "stem", source)
      plant_part!(spindle, "leaf midrib", source)

      taxa = [resolved("t1", wasp), resolved("t2", plant, "species", true)]

      %{"g1" => s} =
        match(
          [
            gall("g1", %{
              "inducer" => "t1",
              "host" => "t2",
              "plant_part" => %{"value" => "stem", "as_written" => "collar of the stem"}
            })
          ],
          taxa
        )

      assert s.resolution == :resolved
      assert s.gall_id == collar.id

      # The Host alone narrows to the two on that plant.
      %{"g1" => s} = match([gall("g1", %{"inducer" => "t1", "host" => "t2"})], taxa)
      assert s.resolution == :ambiguous
      assert Enum.sort(s.candidate_ids) == Enum.sort([collar.id, spindle.id])
    end
  end

  describe "undescribed Galls" do
    setup %{source: source} do
      genus = taxon_fixture(name: "Andricus", rank: :genus, kingdom: "Animalia")
      lobata = plant_fixture(name: "Quercus lobata")
      spindle = gall_fixture(name: "Andricus q-lobata-spindle-gall")
      bullet = gall_fixture(name: "Andricus q-lobata-bullet-gall")
      inducer!(genus, spindle, source)
      inducer!(genus, bullet, source)
      host!(lobata, spindle, source)
      host!(lobata, bullet, source)
      %{genus: genus, lobata: lobata, spindle: spindle, bullet: bullet}
    end

    defp undescribed(_ctx, name, extra \\ %{}) do
      gall(
        "g2",
        %{"inducer" => "t5", "host" => "t2"},
        Map.merge(%{"name_as_written" => name}, extra)
      )
    end

    defp taxa(ctx),
      do: [resolved("t5", ctx.genus, "genus"), resolved("t2", ctx.lobata, "species", true)]

    test "one candidate by genus, Host and descriptive words is the best match, never firm",
         ctx do
      statements =
        [undescribed(ctx, "a small spindle-shaped gall on the leaf midrib")]
        |> match(taxa(ctx))
        |> Map.values()

      [s] = statements
      assert s.resolution == :ambiguous
      assert s.method == "undescribed"
      assert s.gall_id == nil
      assert s.candidate_ids == [ctx.spindle.id]
      assert s.detail["best"] == ctx.spindle.id
      refute Map.has_key?(s.detail, "proposed")

      [item] = GallMatcher.queue_items(statements)
      assert item.kind == :undescribed_gall
      assert item.proposal["best"] == ctx.spindle.id
      refute Map.has_key?(item.proposal, "proposed")
    end

    test "the batch's Traits count as descriptive words", ctx do
      facts = [
        %{
          "id" => "f1",
          "kind" => "trait",
          "gall" => "g2",
          "trait" => "shape",
          "stance" => "confirm",
          "value" => %{"value" => "spindle", "as_written" => "fusiform"}
        }
      ]

      %{"g2" => s} = match([undescribed(ctx, "a small gall")], taxa(ctx), facts)
      assert s.candidate_ids == [ctx.spindle.id]
    end

    test "several candidates are all offered", ctx do
      %{"g2" => s} = match([undescribed(ctx, "a small gall on the leaf")], taxa(ctx))

      assert s.resolution == :ambiguous
      assert Enum.sort(s.candidate_ids) == Enum.sort([ctx.spindle.id, ctx.bullet.id])
      assert s.detail["proposed"] == nil
    end

    test "a Host-only Gall matches on its Host", ctx do
      g = gall("g2", %{"host" => "t2"}, %{"name_as_written" => "a bullet gall"})
      %{"g2" => s} = match([g], [resolved("t2", ctx.lobata, "species", true)])

      assert s.resolution == :ambiguous
      assert s.candidate_ids == [ctx.bullet.id]
    end

    test "a described Gall on the Host is not an undescribed candidate", ctx do
      wasp = taxon_fixture(name: "Andricus described", kingdom: "Animalia")
      described = gall_fixture(name: "Andricus described spindle gall")
      inducer!(wasp, described, ctx.source)
      host!(ctx.lobata, described, ctx.source)

      %{"g2" => s} = match([undescribed(ctx, "spindle gall")], taxa(ctx))
      assert s.candidate_ids == [ctx.spindle.id]
    end

    test "with no candidate: new when the Source says so, else unresolved", ctx do
      other = plant_fixture(name: "Quercus garryana")
      taxa = [resolved("t5", ctx.genus, "genus"), resolved("t2", other, "species", true)]

      %{"g2" => s} = match([undescribed(ctx, "spindle gall", %{"new" => true})], taxa)
      assert s.resolution == :new

      %{"g2" => s} = match([undescribed(ctx, "spindle gall")], taxa)
      assert s.resolution == :unresolved
    end

    test "a formerly undescribed Gall finds its entry through its Host and the Inducer's genus",
         ctx do
      {:ok, species} =
        Gallformers.Taxa.create_taxon(test_actor(), %{
          name: "Andricus fusiformis",
          rank: :species,
          origin: :curated,
          parent_id: ctx.genus.id
        })

      g =
        gall("g2", %{"inducer" => "t1", "host" => "t2"}, %{
          "name_as_written" => "the spindle gall, its wasp described here",
          "formerly_undescribed" => true
        })

      %{"g2" => s} =
        match([g], [resolved("t1", species), resolved("t2", ctx.lobata, "species", true)])

      assert s.resolution == :ambiguous
      assert s.candidate_ids == [ctx.spindle.id]
    end

    test "two of the batch's Galls proposing one entry are both offered, not proposed", ctx do
      galls = [
        undescribed(ctx, "a spindle gall"),
        gall("g3", %{"inducer" => "t5", "host" => "t2"}, %{
          "name_as_written" => "another spindle gall"
        })
      ]

      results = match(galls, taxa(ctx))

      for ref <- ["g2", "g3"] do
        assert results[ref].candidate_ids == [ctx.spindle.id]
        assert results[ref].detail["proposed"] == nil
        assert results[ref].detail["best"] == nil
        assert results[ref].detail["reason"] =~ "another of this batch's Galls"
      end
    end
  end

  describe "the undescribed scope" do
    setup %{source: source} do
      family = taxon_fixture(name: "Cynipidae", rank: :family, kingdom: "Animalia")
      aulacideini = taxon_fixture(name: "Aulacideini", rank: :tribe, parent: family)
      cynipini = taxon_fixture(name: "Cynipini", rank: :tribe, parent: family)
      genus = taxon_fixture(name: "Antistrophus", rank: :genus, parent: aulacideini)
      plant = plant_fixture(name: "Silphium perfoliatum")

      entries =
        for {key, inducer} <- [
              genus: genus,
              tribe: aulacideini,
              family: family,
              cousin: cynipini,
              none: nil
            ],
            into: %{} do
          entry = gall_fixture(name: "Gall s-perfoliatum-#{key}")
          if inducer, do: inducer!(inducer, entry, source)
          host!(plant, entry, source)
          {key, entry}
        end

      %{genus: genus, tribe: aulacideini, plant: plant, entries: entries}
    end

    defp scoped(ctx, inducer, rank) do
      %{"g1" => s} =
        match(
          [gall("g1", %{"inducer" => "t1", "host" => "t2"}, %{"name_as_written" => "a gall"})],
          [resolved("t1", inducer, rank), resolved("t2", ctx.plant, "species", true)]
        )

      ctx.entries
      |> Enum.filter(fn {_key, entry} -> entry.id in s.candidate_ids end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()
    end

    test "a genus: entries of the genus, above it up to its family, or of no Inducer", ctx do
      assert scoped(ctx, ctx.genus, "genus") == [:family, :genus, :none, :tribe]
    end

    test "a higher rank: the taxon, its descendants, its ancestors up to the family", ctx do
      assert scoped(ctx, ctx.tribe, "tribe") == [:family, :genus, :none, :tribe]
    end

    test "an Inducer that only shares an ancestor is not a candidate", ctx do
      refute :cousin in scoped(ctx, ctx.genus, "genus")
    end
  end

  describe "undescribed tie-breakers" do
    setup %{source: source} do
      genus = taxon_fixture(name: "Antistrophus", rank: :genus, kingdom: "Animalia")
      plant = plant_fixture(name: "Silphium asteriscus")

      [flower, stem, cryptic, swelling, unknown_part] =
        for name <- [
              "Antistrophus s-asteriscus-flower-gall",
              "Antistrophus s-asteriscus-stem-cluster-gall",
              "Antistrophus s-asteriscus-cryptic-stem-gall",
              "Antistrophus s-asteriscus-stem-swelling",
              "Antistrophus s-asteriscus-mystery-gall"
            ] do
          entry = gall_fixture(name: name)
          inducer!(genus, entry, source)
          host!(plant, entry, source)
          entry
        end

      plant_part!(flower, "flower", source)
      plant_part!(stem, "stem", source)
      plant_part!(cryptic, "stem", source)
      plant_part!(swelling, "stem", source)

      %{
        genus: genus,
        plant: plant,
        flower: flower,
        stem: stem,
        cryptic: cryptic,
        swelling: swelling,
        unknown_part: unknown_part
      }
    end

    defp tie_taxa(ctx),
      do: [resolved("t1", ctx.genus, "genus"), resolved("t2", ctx.plant, "species", true)]

    defp part_gall(ref, name, part, extra \\ %{}) do
      gall(
        ref,
        %{
          "inducer" => "t1",
          "host" => "t2",
          "plant_part" => %{"value" => part, "as_written" => part}
        },
        Map.merge(%{"name_as_written" => name}, extra)
      )
    end

    test "the plant part filters candidates; an entry with none recorded stays", ctx do
      %{"g1" => s} = match([part_gall("g1", "small galls", "flower")], tie_taxa(ctx))

      assert Enum.sort(s.candidate_ids) == Enum.sort([ctx.flower.id, ctx.unknown_part.id])
    end

    test "leaf parts count as one part", ctx do
      leaf = gall_fixture(name: "Antistrophus s-asteriscus-leaf-blister")
      inducer!(ctx.genus, leaf, ctx.source)
      host!(ctx.plant, leaf, ctx.source)
      plant_part!(leaf, "leaf midrib", ctx.source)

      %{"g1" => s} = match([part_gall("g1", "small galls", "lower leaf")], tie_taxa(ctx))
      assert Enum.sort(s.candidate_ids) == Enum.sort([leaf.id, ctx.unknown_part.id])
    end

    test "a candidate proposed for a sibling Gall is dropped", ctx do
      galls = [
        part_gall("g19", "cryptic stem galls", "stem"),
        part_gall("g27", "terminal stem swelling galls, cryptic", "stem")
      ]

      results = match(galls, tie_taxa(ctx))

      assert results["g19"].detail["best"] == ctx.cryptic.id
      assert results["g27"].detail["best"] == ctx.swelling.id
      refute ctx.cryptic.id in results["g27"].candidate_ids
      assert results["g27"].detail["reason"] =~ "g19"
    end

    test "with no candidate: new is proposed", ctx do
      other = plant_fixture(name: "Silphium dentatum")
      taxa = [resolved("t1", ctx.genus, "genus"), resolved("t2", other, "species", true)]
      statements = [part_gall("g20", "cryptic stem galls", "stem")] |> match(taxa) |> Map.values()

      [s] = statements
      assert s.resolution == :unresolved
      assert s.detail["proposed"] == "new"
      assert [%{proposal: %{"proposed" => "new"}}] = GallMatcher.queue_items(statements)
    end

    test "the Galls of a taxon that emerged from it are offered", ctx do
      wasp = taxon_fixture(name: "Acraspis emergens", kingdom: "Animalia")
      oak = plant_fixture(name: "Quercus emergens")
      agamic = gall_fixture(name: "Acraspis emergens (agamic)", generation: "agamic")
      sexual = gall_fixture(name: "Acraspis emergens (sexgen)", generation: "sexual")
      inducer!(wasp, agamic, ctx.source)
      inducer!(wasp, sexual, ctx.source)

      facts = [
        %{
          "id" => "f64",
          "kind" => "relationship",
          "type" => "emerged_from",
          "stance" => "confirm",
          "subject" => "t8",
          "object" => "g9"
        }
      ]

      g = gall("g9", %{"host" => "t2"}, %{"name_as_written" => "galls on an oak leaf"})

      %{"g9" => s} =
        match([g], [resolved("t8", wasp), resolved("t2", oak, "species", true)], facts)

      assert s.resolution == :ambiguous
      assert s.method == "emerged_from"
      assert Enum.sort(s.candidate_ids) == Enum.sort([agamic.id, sexual.id])
      assert s.detail["reason"] =~ "emerged"
    end
  end

  describe "undescribed Galls on other plants of the Host's genus (c8c3 item 5)" do
    # Nastasi & Davis 2022: the Source's "S. dentatum" is the species, while Gallformers
    # holds its toothed rosinweed gall on Silphium asteriscus var. dentatum (whose synonym
    # Silphium dentatum is). The Source names the Gall by its Host's common name, the entry
    # is coded by the Host's epithet.
    setup %{source: source} do
      wasp = taxon_fixture(name: "Antistrophus", rank: :genus, kingdom: "Animalia")
      silphium = plant_fixture(name: "Silphium", rank: :genus)
      dentatum = plant_fixture(name: "Silphium dentatum", parent: silphium)

      variety =
        plant_fixture(name: "Silphium asteriscus var. dentatum", rank: :variety, parent: silphium)

      laciniatum = plant_fixture(name: "Silphium laciniatum", parent: silphium)

      entry = fn name, plant, part ->
        gall = gall_fixture(name: name)
        inducer!(wasp, gall, source)
        host!(plant, gall, source)
        plant_part!(gall, part, source)
        gall
      end

      toothed = entry.("Antistrophus s-dentatum-cryptic-stem-gall", variety, "stem")
      leafy = entry.("Antistrophus s-laciniatum-cryptic-leaf-gall", laciniatum, "leaf")
      stem = entry.("Antistrophus s-laciniatum-stem-swelling", laciniatum, "stem")
      :ok = Catalog.refresh_gall_index([toothed.id, leafy.id, stem.id])

      %{
        wasp: wasp,
        silphium: silphium,
        dentatum: dentatum,
        toothed: toothed,
        leafy: leafy,
        stem: stem
      }
    end

    defp host_as_written(ref, taxon, written),
      do: put_in(resolved(ref, taxon, "species", true), [:detail, "name_as_written"], written)

    defp toothed_gall(name, part \\ "stem") do
      gall(
        "g20",
        %{
          "inducer" => "t14",
          "host" => "t35",
          "plant_part" => %{"value" => part, "as_written" => part}
        },
        %{"name_as_written" => name}
      )
    end

    defp genus_taxa(ctx),
      do: [
        resolved("t14", ctx.wasp, "genus"),
        host_as_written("t35", ctx.dentatum, "S. dentatum")
      ]

    test "the one whose Host has the Source's epithet is the best match, never new", ctx do
      statements =
        [toothed_gall("Toothed rosinweed cryptic stem gall (Antistrophus sp.)")]
        |> match(genus_taxa(ctx))
        |> Map.values()

      [s] = statements
      assert s.resolution == :ambiguous
      assert s.method == "undescribed"
      assert s.candidate_ids == [ctx.toothed.id]
      assert s.detail["best"] == ctx.toothed.id
      refute Map.has_key?(s.detail, "proposed")
      assert s.detail["reason"] =~ "other Silphium plants"

      assert [%{kind: :undescribed_gall, proposal: %{"best" => best}}] =
               GallMatcher.queue_items(statements)

      assert best == ctx.toothed.id
    end

    test "with no epithet in common, the entries sharing descriptive words are offered", ctx do
      other = plant_fixture(name: "Silphium terebinthinaceum", parent: ctx.silphium)

      taxa = [
        resolved("t14", ctx.wasp, "genus"),
        host_as_written("t35", other, "S. terebinthinaceum")
      ]

      %{"g20" => s} = match([toothed_gall("Prairie dock stem swelling")], taxa)

      assert s.resolution == :ambiguous
      assert s.candidate_ids == [ctx.stem.id]
      assert s.detail["best"] == ctx.stem.id
    end

    test "nothing alike on the genus's plants: no proposal while it holds such Galls", ctx do
      %{"g20" => s} = match([toothed_gall("Prairie dock gall")], genus_taxa(ctx) |> no_epithet())

      assert s.resolution == :unresolved
      assert s.candidate_ids == []
      refute Map.has_key?(s.detail, "proposed")

      assert s.detail["reason"] =~
               "2 undescribed Galls of its Inducer's genus on other Silphium plants"
    end

    test "an entry on another plant part is no candidate, and new is proposed", ctx do
      %{"g20" => s} =
        match([toothed_gall("Toothed rosinweed flower gall", "flower")], genus_taxa(ctx))

      assert s.resolution == :unresolved
      assert s.detail["proposed"] == "new"
    end

    defp no_epithet([inducer, host]),
      do: [inducer, put_in(host, [:detail, "name_as_written"], "toothed rosinweed")]
  end

  describe "undescribed Galls waiting on their Host (c8c3 item 5)" do
    # Nastasi & Davis 2022's "Horkelia stem gall": its Host "Horkelia congesta congesta"
    # resolved to nothing, so no entry on it could match, and new was proposed.
    defp horkelia(host) do
      g = gall("g46", %{"host" => "t79"}, %{"name_as_written" => "Horkelia stem gall"})
      match([g], [host])
    end

    test "with its Host not resolved, it waits on the Host's question, with none of its own" do
      %{"g46" => s} = horkelia(statement("t79", :unresolved, "Horkelia congesta congesta"))

      assert s.resolution == :unresolved
      assert "waits_on_host" in s.flags
      assert s.detail["waits_on"] == "t79"
      refute Map.has_key?(s.detail, "proposed")
      assert GallMatcher.queue_items([s]) == []
    end

    test "once its Host is left out, it is matched on its own" do
      host = %{statement("t79", :unresolved, "Horkelia congesta congesta") | flags: ["skipped"]}
      %{"g46" => s} = horkelia(host)

      refute "waits_on_host" in s.flags
      assert s.detail["proposed"] == "new"
    end
  end

  describe "comparison with the Source: conflicts and firmness" do
    # `d213` Task 4: a different coarse plant part or form cancels firm; an
    # undescribed match is never firm; candidates rank by agreeing fields.

    defp trait!(gall, trait, value, source) do
      {:ok, _} =
        Catalog.assert_trait(
          test_actor(),
          %{gall_id: gall.id, trait: trait, value: value},
          confirm(source)
        )
    end

    defp trait_fact(ref, trait, value) do
      %{
        "id" => "f#{System.unique_integer([:positive])}",
        "kind" => "trait",
        "gall" => ref,
        "trait" => trait,
        "stance" => "confirm",
        "term" => value,
        "category" => %{"value" => value}
      }
    end

    defp part(value), do: %{"value" => value, "as_written" => value}

    defp heterogony!(taxon) do
      heterogony = Enum.find(Catalog.list_generation_groups(), &(&1.name == "heterogony"))
      Repo.insert_all("generation_group_taxa", [%{group_id: heterogony.id, taxon_id: taxon.id}])
    end

    defp item_for(statements, ref) do
      item = statements |> GallMatcher.queue_items() |> Enum.find(&(&1.statement_ref == ref))
      {item, Proposals.proposed(struct!(QueueItem, item))}
    end

    test "stem vs fruit: the lone Gall of an alternating Inducer is not proposed " <>
           "(C. q. juglans)",
         %{source: source} do
      tribe = taxon_fixture(name: "Cynipini", rank: :tribe, kingdom: "Animalia")
      genus = taxon_fixture(name: "Amphibolips", rank: :genus, kingdom: "Animalia", parent: tribe)
      wasp = taxon_fixture(name: "Amphibolips quercusjuglans", kingdom: "Animalia", parent: genus)
      agamic = gall_fixture(name: "Amphibolips quercusjuglans (agamic)", generation: "agamic")
      inducer!(wasp, agamic, source)
      plant_part!(agamic, "fruit", source)
      heterogony!(tribe)

      g =
        gall("g1", %{"inducer" => "t1"}, %{
          "name_as_written" => "the large, round, corky branch gall"
        })

      statements =
        [g]
        |> match([resolved("t1", wasp)], [trait_fact("g1", "plant_part", "stem")])
        |> Map.values()

      [s] = statements
      assert s.resolution == :ambiguous
      assert s.candidate_ids == [agamic.id]
      refute Map.has_key?(s.detail, "proposed")
      assert s.detail["best"] == agamic.id
      assert s.detail["conflicts"] == ["where"]

      {item, proposed} = item_for(statements, "g1")
      assert item.proposal["best"] == agamic.id
      assert item.proposal["conflicts"] == ["where"]
      refute Map.has_key?(item.proposal, "proposed")
      assert proposed == {:none, :weak}
    end

    test "roots vs stem: a lone Gall that would resolve goes to a curator " <>
           "(Callirhytis rhizoxenus)",
         %{source: source} do
      wasp = taxon_fixture(name: "Callirhytis rhizoxenus", kingdom: "Animalia")
      entry = gall_fixture(name: "Callirhytis rhizoxenus")
      inducer!(wasp, entry, source)
      plant_part!(entry, "stem", source)

      g = gall("g1", %{"inducer" => "t1", "plant_part" => part("underground (roots+)")})
      statements = [g] |> match([resolved("t1", wasp)]) |> Map.values()

      [s] = statements
      assert s.resolution == :ambiguous
      assert s.gall_id == nil
      assert s.candidate_ids == [entry.id]
      assert s.detail["best"] == entry.id
      assert s.detail["conflicts"] == ["where"]
      assert s.detail["reason"] =~ "where on the plant"

      {_item, proposed} = item_for(statements, "g1")
      assert proposed == {:none, :weak}
    end

    test "a different form conflicts too", %{source: source} do
      wasp = taxon_fixture(name: "Andricus formosus", kingdom: "Animalia")
      entry = gall_fixture(name: "Andricus formosus")
      inducer!(wasp, entry, source)
      trait!(entry, "form", "oak apple", source)

      %{"g1" => s} =
        match([gall("g1", %{"inducer" => "t1"})], [resolved("t1", wasp)], [
          trait_fact("g1", "form", "bullet")
        ])

      assert s.resolution == :ambiguous
      assert s.detail["conflicts"] == ["form"]
    end

    # `c8c3` item 13: Nastasi & Davis's silverpuff stem gall ("swellings": tapered swelling)
    # was asked about because its one Gall, Antistrophus microseris's, held abrupt swelling.
    test "forms that are readings of one ambiguous term differ, not conflict: resolved",
         %{source: source} do
      wasp = taxon_fixture(name: "Antistrophus microseris", kingdom: "Animalia")
      entry = gall_fixture(name: "Antistrophus microseris")
      inducer!(wasp, entry, source)
      trait!(entry, "form", "abrupt swelling", source)

      %{"g11" => s} =
        match([gall("g11", %{"inducer" => "t1"})], [resolved("t1", wasp)], [
          trait_fact("g11", "form", "tapered swelling")
        ])

      assert s.resolution == :resolved
      assert s.gall_id == entry.id
    end

    test "lower leaf vs leaf midrib agrees: resolved, and proposed stays firm",
         %{source: source} do
      tribe = taxon_fixture(name: "Cynipini", rank: :tribe, kingdom: "Animalia")
      genus = taxon_fixture(name: "Neuroterus", rank: :genus, kingdom: "Animalia", parent: tribe)
      wasp = taxon_fixture(name: "Neuroterus foliaris", kingdom: "Animalia", parent: genus)
      sexual = gall_fixture(name: "Neuroterus foliaris (sexgen)", generation: "sexual")
      inducer!(wasp, sexual, source)
      plant_part!(sexual, "leaf midrib", source)

      g = gall("g1", %{"inducer" => "t1", "plant_part" => part("lower leaf")})

      %{"g1" => s} = match([g], [resolved("t1", wasp)])
      assert s.resolution == :resolved
      assert s.gall_id == sexual.id

      heterogony!(tribe)
      statements = [g] |> match([resolved("t1", wasp)]) |> Map.values()

      [s] = statements
      assert s.detail["proposed"] == sexual.id
      refute Map.has_key?(s.detail, "conflicts")

      {_item, proposed} = item_for(statements, "g1")
      assert proposed == {:ok, %{"gall_id" => sexual.id}}
    end

    test "an undescribed best match is never firm (the pin oak wart vs a leaf curl)",
         %{source: source} do
      palustris = plant_fixture(name: "Quercus palustris")
      curl = gall_fixture(name: "Unknown q-palustris-leaf-curl")
      host!(palustris, curl, source)
      trait!(curl, "form", "leaf curl", source)

      g =
        gall("g7", %{"host" => "t2"}, %{
          "name_as_written" => "wart-like excrescences on the pin oak"
        })

      statements =
        [g] |> match([resolved("t2", palustris, "species", true)]) |> Map.values()

      [s] = statements
      assert s.method == "undescribed"
      assert s.detail["best"] == curl.id
      refute Map.has_key?(s.detail, "proposed")

      {item, proposed} = item_for(statements, "g7")
      assert item.kind == :undescribed_gall
      assert item.proposal["best"] == curl.id
      assert proposed == {:none, :weak}
    end

    test "candidates rank by agreeing fields, each with its comparison", %{source: source} do
      wasp = taxon_fixture(name: "Antistrophus rankedus", kingdom: "Animalia")
      plant = plant_fixture(name: "Silphium rankedum")
      # Created first, so first by ID: conflicts on where.
      leafy = gall_fixture(name: "Antistrophus rankedus leaf gall")
      stemmy = gall_fixture(name: "Antistrophus rankedus stem gall")

      for e <- [leafy, stemmy] do
        inducer!(wasp, e, source)
        host!(plant, e, source)
      end

      plant_part!(leafy, "upper leaf", source)
      plant_part!(stemmy, "stem", source)

      taxa = [resolved("t1", wasp), resolved("t2", plant, "species", true)]

      # No generation, and the plant part only as a Trait: both stay candidates.
      statements =
        [gall("g1", %{"inducer" => "t1", "host" => "t2"})]
        |> match(taxa, [trait_fact("g1", "plant_part", "stem")])
        |> Map.values()

      [s] = statements
      assert s.resolution == :ambiguous
      assert s.candidate_ids == [stemmy.id, leafy.id]

      {item, proposed} = item_for(statements, "g1")
      assert proposed == {:none, :weak}
      assert item.proposal["candidate_ids"] == [stemmy.id, leafy.id]

      assert [
               %{"gall_id" => first, "agrees" => 2, "conflicts" => []},
               %{"gall_id" => second, "agrees" => 1, "conflicts" => ["where"]} = c
             ] = item.proposal["comparisons"]

      assert {first, second} == {stemmy.id, leafy.id}
      assert c["fields"]["host"] == "agree"
    end
  end

  describe "a Gall's Gallformers note" do
    test "the note's own Gall resolves to it, whatever matching would find", %{source: source} do
      genus = taxon_fixture(name: "Notegenus", rank: :genus, kingdom: "Animalia")
      noted = gall_fixture(name: "Notegenus q-alba-bud-gall")
      inducer!(genus, noted, source)

      batch = %{
        "batch_type" => "gall",
        "source" => %{
          "gallformers" => true,
          "note" => %{"gallformers_gall_id" => noted.id, "stated_on" => "2026-10-30"}
        },
        "galls" => [
          gall("g1", %{"inducer" => "t1"}, %{"gallformers_gall_id" => noted.id}),
          # Another Gall the note mentions is matched as usual.
          gall("g2", %{"inducer" => "t1"}, %{"gallformers_gall_id" => noted.id + 1})
        ],
        "facts" => []
      }

      %{"g1" => s, "g2" => other} =
        batch |> GallMatcher.match_galls([resolved("t1", genus, "genus")]) |> by_ref()

      assert %{resolution: :resolved, method: "note", gall_id: gall_id} = s
      assert gall_id == noted.id
      refute other.method == "note"
    end
  end

  describe "a curator's Gallformers statement" do
    test "a Gall given by gallformers_gall_id is that Gall, whatever matching would find",
         %{source: source} do
      wasp = taxon_fixture(name: "Andricus curatorius", kingdom: "Animalia")
      one = gall_fixture(name: "Andricus curatorius stem gall")
      two = gall_fixture(name: "Andricus curatorius leaf gall")
      inducer!(wasp, one, source)
      inducer!(wasp, two, source)

      batch = %{
        "batch_type" => "gall",
        "source" => %{"gallformers" => true},
        "galls" => [
          gall("g1", %{"inducer" => "t1"}, %{"gallformers_gall_id" => two.id}),
          # An ID Gallformers does not hold is matched as usual.
          gall("g2", %{"inducer" => "t1"}, %{"gallformers_gall_id" => 999_999_999})
        ],
        "facts" => []
      }

      %{"g1" => s, "g2" => other} =
        batch |> GallMatcher.match_galls([resolved("t1", wasp)]) |> by_ref()

      assert %{resolution: :resolved, method: "gallformers_gall_id", gall_id: gall_id} = s
      assert gall_id == two.id
      assert other.resolution == :ambiguous
    end

    test "another Source's gallformers_gall_id is only checked", %{source: source} do
      wasp = taxon_fixture(name: "Andricus publicus", kingdom: "Animalia")
      one = gall_fixture(name: "Andricus publicus stem gall")
      two = gall_fixture(name: "Andricus publicus leaf gall")
      inducer!(wasp, one, source)
      inducer!(wasp, two, source)

      %{"g1" => s} =
        match([gall("g1", %{"inducer" => "t1"}, %{"gallformers_gall_id" => two.id})], [
          resolved("t1", wasp)
        ])

      assert s.resolution == :ambiguous
    end
  end

  describe "queue_items/1" do
    test "ambiguous Galls go to the queue; undescribed ones as candidates" do
      statements = [
        %{
          kind: :gall,
          ref: "g1",
          resolution: :ambiguous,
          method: "identified_by",
          candidate_ids: [1, 2],
          gall_id: nil,
          flags: [],
          detail: %{"reason" => "two"}
        },
        %{
          kind: :gall,
          ref: "g2",
          resolution: :ambiguous,
          method: "undescribed",
          candidate_ids: [3],
          gall_id: nil,
          flags: [],
          detail: %{"best" => 3, "conflicts" => ["form"]}
        },
        %{
          kind: :gall,
          ref: "g3",
          resolution: :unresolved,
          method: nil,
          candidate_ids: [],
          gall_id: nil,
          flags: [],
          detail: %{}
        },
        %{
          kind: :gall,
          ref: "g4",
          resolution: :resolved,
          method: "identified_by",
          candidate_ids: [],
          gall_id: 5,
          flags: [],
          detail: %{}
        }
      ]

      items = statements |> GallMatcher.queue_items() |> Map.new(&{&1.statement_ref, &1})

      assert %{kind: :ambiguous_match, proposal: %{"candidate_ids" => [1, 2]}} = items["g1"]

      assert %{kind: :undescribed_gall, proposal: %{"best" => 3, "conflicts" => ["form"]}} =
               items["g2"]

      assert %{kind: :unresolved_name} = items["g3"]
      refute Map.has_key?(items, "g4")
    end
  end
end
