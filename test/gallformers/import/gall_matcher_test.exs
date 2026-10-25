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
    |> Map.new(&{&1.ref, &1})
  end

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

    test "an unresolved Inducer leaves the Gall unresolved" do
      %{"g1" => s} =
        match([gall("g1", %{"inducer" => "t1"})], [statement("t1", :unresolved, "Nonesuch")])

      assert s.resolution == :unresolved
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

    test "one candidate by genus, Host and descriptive words is proposed, not resolved", ctx do
      %{"g2" => s} =
        match([undescribed(ctx, "a small spindle-shaped gall on the leaf midrib")], taxa(ctx))

      assert s.resolution == :ambiguous
      assert s.method == "undescribed"
      assert s.gall_id == nil
      assert s.candidate_ids == [ctx.spindle.id]
      assert s.detail["proposed"] == ctx.spindle.id
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
        assert results[ref].detail["reason"] =~ "another of this batch's Galls"
      end
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
          detail: %{"proposed" => 3}
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
      assert %{kind: :undescribed_gall, proposal: %{"proposed" => 3}} = items["g2"]
      assert %{kind: :unresolved_name} = items["g3"]
      refute Map.has_key?(items, "g4")
    end
  end
end
