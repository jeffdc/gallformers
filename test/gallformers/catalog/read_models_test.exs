defmodule Gallformers.Catalog.ReadModelsTest do
  @moduledoc """
  Catalog read models (`9449` §4, Task 10): a Gall's potential range, its
  summary (current Inducer, Hosts, Traits), and the generation flags.

  Seeded places (`priv/repo/test_seeds.sql`): US (subdivision US-CA), CA
  (CA-AB), MX (MX-JAL), RO (RO-B), and BS, a country with no subdivisions.

  Not async: some tests load the vocabularies (see
  `Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.ReadModels.GallSummary
  alias Gallformers.Catalog.ReadModels.PotentialRange

  defp codes(:everywhere), do: :everywhere
  defp codes(places), do: places |> Enum.map(& &1.code) |> Enum.sort()

  defp host!(plant, gall, attribution) do
    {:ok, result} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: plant.id, object_gall_id: gall.id},
        attribution
      )

    result
  end

  defp inducer!(taxon, gall, source) do
    {:ok, result} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: taxon.id, object_gall_id: gall.id},
        confirm(source)
      )

    result
  end

  defp range!(gall, adjustment, code, attribution) do
    {:ok, result} =
      Catalog.assert_range(
        test_actor(),
        %{gall_id: gall.id, adjustment: adjustment, place_id: place_id(code)},
        attribution
      )

    result
  end

  defp alternate!(gall, other, source) do
    {:ok, result} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "alternate_generation_of", subject_gall_id: gall.id, object_gall_id: other.id},
        confirm(source)
      )

    result
  end

  defp map_group!(group_name, taxon) do
    [group] = for g <- Catalog.list_generation_groups(), g.name == group_name, do: g
    Repo.insert_all("generation_group_taxa", [%{group_id: group.id, taxon_id: taxon.id}])
  end

  setup do
    %{source: source_fixture("Weld", "1959")}
  end

  # -- potential range ---------------------------------------------------------

  describe "potential range" do
    setup do
      california_oak = plant_fixture()
      host_range_fixture(california_oak, [{"US-CA", "exact"}])

      canadian_oak = plant_fixture()
      host_range_fixture(canadian_oak, [{"CA", "country"}])

      %{california_oak: california_oak, canadian_oak: canadian_oak, gall: gall_fixture()}
    end

    test "acceptance: a Gall with no range data appears in every region", ctx do
      assert Catalog.potential_range(ctx.gall.id) == :everywhere

      # A Host with no range rows adds no range data either.
      host!(plant_fixture(), ctx.gall, confirm(ctx.source))
      assert Catalog.potential_range(ctx.gall.id) == :everywhere
    end

    test "is the union of the current Hosts' ranges, country-level rows as their subdivisions",
         ctx do
      host!(ctx.california_oak, ctx.gall, confirm(ctx.source))
      host!(ctx.canadian_oak, ctx.gall, confirm(ctx.source))

      assert codes(Catalog.potential_range(ctx.gall.id)) == ["CA-AB", "US-CA"]
    end

    test "includes introduced ranges", ctx do
      bahamas = plant_fixture()
      host_range_fixture(bahamas, [{"BS", "exact", "introduced"}])
      host!(bahamas, ctx.gall, confirm(ctx.source))

      assert codes(Catalog.potential_range(ctx.gall.id)) == ["BS"]
    end

    test "a genus Host contributes its own range rows", ctx do
      quercus = plant_fixture(rank: :genus, name: "Quercus")
      host_range_fixture(quercus, [{"MX-JAL", "exact"}])
      host!(quercus, ctx.gall, confirm(ctx.source))

      assert codes(Catalog.potential_range(ctx.gall.id)) == ["MX-JAL"]
    end

    test "a genus Host with no rows of its own takes its species' ranges (803b decision 8)",
         ctx do
      genus = plant_fixture(rank: :genus, name: "Fixturquercus")
      section = plant_fixture(rank: :section, name: "Fixturlobatae", parent: genus)
      alba = plant_fixture(name: "Fixturquercus alba", parent: genus)
      rubra = plant_fixture(name: "Fixturquercus rubra", parent: section)
      host_range_fixture(alba, [{"US-CA", "exact"}])
      host_range_fixture(rubra, [{"CA", "country"}, {"RO-B", "exact", "introduced"}])
      host!(genus, ctx.gall, confirm(ctx.source))

      assert codes(Catalog.potential_range(ctx.gall.id)) == ["CA-AB", "RO-B", "US-CA"]
    end

    test "a genus Host's own rows and its species' ranges are one union", ctx do
      genus = plant_fixture(rank: :genus, name: "Fixturquercus")
      host_range_fixture(genus, [{"MX-JAL", "exact"}])
      alba = plant_fixture(name: "Fixturquercus alba", parent: genus)
      host_range_fixture(alba, [{"US-CA", "exact"}])
      host!(genus, ctx.gall, confirm(ctx.source))

      assert codes(Catalog.potential_range(ctx.gall.id)) == ["MX-JAL", "US-CA"]
    end

    test "an exclude still removes a place from a genus Host's species' ranges", ctx do
      genus = plant_fixture(rank: :genus, name: "Fixturquercus")
      alba = plant_fixture(name: "Fixturquercus alba", parent: genus)
      host_range_fixture(alba, [{"US-CA", "exact"}, {"CA", "country"}])
      host!(genus, ctx.gall, confirm(ctx.source))
      range!(ctx.gall, :exclude, "CA-AB", confirm(ctx.source))

      assert codes(Catalog.potential_range(ctx.gall.id)) == ["US-CA"]
    end

    test "a species Host reads only its own rows, not those of taxa below it", ctx do
      alba = plant_fixture(name: "Fixturquercus alba")
      host_range_fixture(alba, [{"US-CA", "exact"}])

      variety =
        plant_fixture(name: "Fixturquercus alba var. fixtura", rank: :variety, parent: alba)

      host_range_fixture(variety, [{"MX-JAL", "exact"}])
      host!(alba, ctx.gall, confirm(ctx.source))

      assert codes(Catalog.potential_range(ctx.gall.id)) == ["US-CA"]
    end

    test "for many Galls at once, a genus Host's range is its species' too", ctx do
      genus = plant_fixture(rank: :genus, name: "Fixturquercus")
      alba = plant_fixture(name: "Fixturquercus alba", parent: genus)
      host_range_fixture(alba, [{"US-CA", "exact"}])
      host!(genus, ctx.gall, confirm(ctx.source))
      on_species = gall_fixture()
      host!(ctx.canadian_oak, on_species, confirm(ctx.source))

      ranges = PotentialRange.for_galls([ctx.gall.id, on_species.id])

      assert codes(ranges[ctx.gall.id]) == ["US-CA"]
      assert codes(ranges[on_species.id]) == ["CA-AB"]
    end

    test "reads host ranges by taxon: a genus Host carries its former placeholder's rows", ctx do
      # The data migration re-keys a genus placeholder's ("Quercus spp.") rows
      # to the genus taxon, which has a new ID and no `species` row; the
      # rows keep the placeholder's `species_id`.
      quercus = plant_fixture(rank: :genus, name: "Quercus")
      placeholder_id = placeholder_species_fixture("Quercus spp.")

      Repo.insert_all("host_range", [
        %{species_id: placeholder_id, taxon_id: quercus.id, place_id: place_id("MX-JAL")}
      ])

      host!(quercus, ctx.gall, confirm(ctx.source))

      assert codes(Catalog.potential_range(ctx.gall.id)) == ["MX-JAL"]
    end

    test "a withdrawn Host stops contributing", ctx do
      host!(ctx.california_oak, ctx.gall, confirm(ctx.source))
      host!(ctx.canadian_oak, ctx.gall, confirm(ctx.source))
      host!(ctx.canadian_oak, ctx.gall, deny(source_fixture("Revision", "1990")))

      assert codes(Catalog.potential_range(ctx.gall.id)) == ["US-CA"]
    end

    test "exclude removes a region", ctx do
      host!(ctx.california_oak, ctx.gall, confirm(ctx.source))
      host!(ctx.canadian_oak, ctx.gall, confirm(ctx.source))
      range!(ctx.gall, :exclude, "CA-AB", confirm(ctx.source))

      assert codes(Catalog.potential_range(ctx.gall.id)) == ["US-CA"]
    end

    test "excluding a country removes its subdivisions", ctx do
      host!(ctx.california_oak, ctx.gall, confirm(ctx.source))
      host!(ctx.canadian_oak, ctx.gall, confirm(ctx.source))
      range!(ctx.gall, :exclude, "CA", confirm(ctx.source))

      assert codes(Catalog.potential_range(ctx.gall.id)) == ["US-CA"]
    end

    test "only keeps one", ctx do
      host!(ctx.california_oak, ctx.gall, confirm(ctx.source))
      host!(ctx.canadian_oak, ctx.gall, confirm(ctx.source))
      range!(ctx.gall, :only, "US-CA", confirm(ctx.source))

      assert codes(Catalog.potential_range(ctx.gall.id)) == ["US-CA"]
    end

    test "only gives a range to a Gall with no Host range data", ctx do
      range!(ctx.gall, :only, "MX-JAL", confirm(ctx.source))

      assert codes(Catalog.potential_range(ctx.gall.id)) == ["MX-JAL"]
    end

    test "never reaches a place outside every Host's range, even where a Source records it",
         ctx do
      host!(ctx.california_oak, ctx.gall, confirm(ctx.source))

      {:ok, _} =
        Catalog.assert_occurrence(
          test_actor(),
          %{gall_id: ctx.gall.id, place_id: place_id("RO-B")},
          confirm(ctx.source)
        )

      assert codes(Catalog.potential_range(ctx.gall.id)) == ["US-CA"]
    end

    test "the newest of an exclude and an only for one place wins", ctx do
      host!(ctx.california_oak, ctx.gall, confirm(ctx.source))
      host!(ctx.canadian_oak, ctx.gall, confirm(ctx.source))

      range!(ctx.gall, :exclude, "US-CA", confirm(ctx.source))
      range!(ctx.gall, :only, "US-CA", confirm(source_fixture("Revision", "1990")))
      assert codes(Catalog.potential_range(ctx.gall.id)) == ["US-CA"]

      range!(ctx.gall, :exclude, "US-CA", confirm(source_fixture("Later", "2001")))
      assert codes(Catalog.potential_range(ctx.gall.id)) == ["CA-AB"]
    end

    test "a withdrawn adjustment no longer applies", ctx do
      host!(ctx.california_oak, ctx.gall, confirm(ctx.source))
      host!(ctx.canadian_oak, ctx.gall, confirm(ctx.source))
      range!(ctx.gall, :exclude, "CA-AB", confirm(ctx.source))
      range!(ctx.gall, :exclude, "CA-AB", deny(source_fixture("Revision", "1990")))

      assert codes(Catalog.potential_range(ctx.gall.id)) == ["CA-AB", "US-CA"]
    end

    test "excluding a region from a Gall with no range data leaves every other region", ctx do
      range!(ctx.gall, :exclude, "US-CA", confirm(ctx.source))

      range = Catalog.potential_range(ctx.gall.id)
      assert is_list(range)
      range = codes(range)
      assert "CA-AB" in range
      assert "BS" in range
      refute "US-CA" in range
    end

    test "for many Galls at once is each Gall's own range", ctx do
      both = ctx.gall
      host!(ctx.california_oak, both, confirm(ctx.source))
      host!(ctx.canadian_oak, both, confirm(ctx.source))

      excluded = gall_fixture()
      host!(ctx.california_oak, excluded, confirm(ctx.source))
      host!(ctx.canadian_oak, excluded, confirm(ctx.source))
      range!(excluded, :exclude, "CA", confirm(ctx.source))

      only = gall_fixture()
      range!(only, :only, "MX-JAL", confirm(ctx.source))

      everywhere_but = gall_fixture()
      range!(everywhere_but, :exclude, "US-CA", confirm(ctx.source))

      nowhere_known = gall_fixture()
      host!(plant_fixture(), nowhere_known, confirm(ctx.source))

      ids = Enum.map([both, excluded, only, everywhere_but, nowhere_known], & &1.id)
      ranges = PotentialRange.for_galls(ids ++ [both.id])

      assert Map.keys(ranges) |> Enum.sort() == Enum.sort(ids)
      for id <- ids, do: assert(ranges[id] == Catalog.potential_range(id))

      assert codes(ranges[both.id]) == ["CA-AB", "US-CA"]
      assert codes(ranges[excluded.id]) == ["US-CA"]
      assert codes(ranges[only.id]) == ["MX-JAL"]
      refute "US-CA" in codes(ranges[everywhere_but.id])
      assert ranges[nowhere_known.id] == :everywhere
      assert PotentialRange.for_galls([]) == %{}
    end
  end

  # -- summary -----------------------------------------------------------------

  describe "gall summary" do
    setup do
      load_vocab!()
      :ok
    end

    test "gives the current Inducer, Hosts and Traits", %{source: source} do
      gall = gall_fixture(name: "Andricus foo (agamic)", generation: "agamic")
      wasp = taxon_fixture(name: "Andricus foo", kingdom: "Animalia")
      alba = plant_fixture(name: "Quercus alba")
      rubra = plant_fixture(name: "Quercus rubra")
      newer = source_fixture("Revision", "1990")

      inducer!(wasp, gall, source)
      host!(alba, gall, confirm(source))
      host!(rubra, gall, confirm(source))
      host!(rubra, gall, deny(newer))

      for {trait, value} <- [{"color", "red"}, {"color", "brown"}, {"detachable", "integral"}] do
        {:ok, _} =
          Catalog.assert_trait(
            test_actor(),
            %{gall_id: gall.id, trait: trait, value: value},
            confirm(source)
          )
      end

      {:ok, _} =
        Catalog.assert_trait(
          test_actor(),
          %{gall_id: gall.id, trait: "detachable", value: "detachable"},
          confirm(newer)
        )

      assert %GallSummary{
               gall_id: gall_id,
               name: "Andricus foo (agamic)",
               generation: "agamic",
               inducers: [%{taxon_id: wasp_id, name: "Andricus foo"}],
               hosts: [%{taxon_id: alba_id, name: "Quercus alba"}],
               traits: %{"color" => ["brown", "red"], "detachable" => ["detachable"]}
             } = Catalog.gall_summary(gall.id)

      assert {gall_id, wasp_id, alba_id} == {gall.id, wasp.id, alba.id}
    end

    test "a Gall with no Facts has an empty summary" do
      gall = gall_fixture()

      assert %GallSummary{inducers: [], hosts: [], traits: traits, generation: nil} =
               Catalog.gall_summary(gall.id)

      assert traits == %{}
    end

    test "gives each taxon's rank", %{source: source} do
      gall = gall_fixture()
      genus = taxon_fixture(name: "Andricus", rank: :genus, kingdom: "Animalia")
      inducer!(genus, gall, source)

      assert %GallSummary{inducers: [%{taxon_id: id, rank: :genus}]} =
               Catalog.gall_summary(gall.id)

      assert id == genus.id
    end

    test "Galls by current Inducer and by current Host", %{source: source} do
      wasp = taxon_fixture(name: "Andricus foo", kingdom: "Animalia")
      other = taxon_fixture(name: "Andricus bar", kingdom: "Animalia")
      alba = plant_fixture(name: "Quercus alba")
      one = gall_fixture(name: "Andricus foo gall one")
      two = gall_fixture(name: "Andricus foo gall two")
      withdrawn = gall_fixture(name: "Andricus bar gall")
      inducer!(wasp, one, source)
      inducer!(wasp, two, source)
      inducer!(other, withdrawn, source)
      host!(alba, two, confirm(source))
      host!(alba, withdrawn, confirm(source))

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: other.id, object_gall_id: withdrawn.id},
          deny(source_fixture("Later", "2000"))
        )

      assert wasp.id |> List.wrap() |> Catalog.list_gall_summaries_by_inducer() |> ids() ==
               Enum.sort([one.id, two.id])

      assert Catalog.list_gall_summaries_by_inducer([other.id]) == []

      assert Catalog.list_gall_summaries_by_host([alba.id]) |> ids() ==
               Enum.sort([two.id, withdrawn.id])

      assert Catalog.list_gall_summaries_by_host([]) == []
    end
  end

  defp ids(summaries), do: summaries |> Enum.map(& &1.gall_id) |> Enum.sort()

  # -- flags -------------------------------------------------------------------

  # The flags on this test's Galls: the converted seeds' Galls (which keep
  # their species IDs) have generation pairs of their own.
  defp own(flags) do
    seeded =
      MapSet.new(Repo.all(from(s in "species", where: s.taxoncode == "gall", select: s.id)))

    Enum.reject(flags, fn flag -> Enum.any?(flag_galls(flag), &MapSet.member?(seeded, &1)) end)
  end

  defp flag_galls(%{gall_ids: ids}), do: ids
  defp flag_galls(%{gall_id: id}), do: [id]

  describe "alternate-generation flags" do
    setup %{source: source} do
      load_vocab!()
      wasp = taxon_fixture(name: "Andricus foo", kingdom: "Animalia")
      agamic = gall_fixture(name: "Andricus foo (agamic)", generation: "agamic")
      sexual = gall_fixture(name: "Andricus foo (sexgen)", generation: "sexual")
      inducer!(wasp, agamic, source)
      inducer!(wasp, sexual, source)

      %{wasp: wasp, agamic: agamic, sexual: sexual}
    end

    test "two generations of one species-level Inducer with no link are flagged", ctx do
      assert [flag] = own(Catalog.alternate_generation_flags())
      assert flag.kind == :unlinked_generations
      assert flag.inducer_id == ctx.wasp.id
      assert Enum.sort(flag.gall_ids) == Enum.sort([ctx.agamic.id, ctx.sexual.id])
    end

    test "linked generations are not flagged", ctx do
      alternate!(ctx.agamic, ctx.sexual, ctx.source)
      assert own(Catalog.alternate_generation_flags()) == []
    end

    test "a withdrawn link no longer counts", ctx do
      alternate!(ctx.agamic, ctx.sexual, ctx.source)

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{
            type: "alternate_generation_of",
            subject_gall_id: ctx.agamic.id,
            object_gall_id: ctx.sexual.id
          },
          deny(source_fixture("Revision", "1990"))
        )

      assert [%{kind: :unlinked_generations}] = own(Catalog.alternate_generation_flags())
    end

    test "a genus-level Inducer's Galls are not compared", ctx do
      genus = taxon_fixture(rank: :genus, name: "Callirhytis", kingdom: "Animalia")
      a = gall_fixture(generation: "agamic")
      b = gall_fixture(generation: "sexual")
      inducer!(genus, a, ctx.source)
      inducer!(genus, b, ctx.source)

      assert [%{inducer_id: inducer_id}] = own(Catalog.alternate_generation_flags())
      assert inducer_id == ctx.wasp.id
    end

    test "a link between Galls whose Inducers differ is flagged", ctx do
      other_wasp = taxon_fixture(name: "Andricus bar", kingdom: "Animalia")
      other_sexual = gall_fixture(name: "Andricus bar (sexgen)", generation: "sexual")
      inducer!(other_wasp, other_sexual, ctx.source)
      alternate!(ctx.agamic, ctx.sexual, ctx.source)
      %{fact: link} = alternate!(ctx.agamic, other_sexual, ctx.source)

      assert [flag] = own(Catalog.alternate_generation_flags())
      assert flag.kind == :linked_inducers_differ
      assert flag.fact_id == link.id
      assert flag.gall_ids == [ctx.agamic.id, other_sexual.id]
      assert Enum.sort(flag.inducer_ids) == Enum.sort([ctx.wasp.id, other_wasp.id])
    end
  end

  describe "generation-group flags" do
    setup %{source: source} do
      load_vocab!()
      cynipini = taxon_fixture(rank: :tribe, name: "Cynipini", kingdom: "Animalia")
      andricus = taxon_fixture(rank: :genus, name: "Andricus", parent: cynipini)
      wasp = taxon_fixture(rank: :species, name: "Andricus foo", parent: andricus)
      gall = gall_fixture(generation: "agamic")
      inducer!(wasp, gall, source)

      %{cynipini: cynipini, andricus: andricus, wasp: wasp, gall: gall}
    end

    test "a generation in the group of the Inducer's nearest mapped ancestor is fine", ctx do
      map_group!("heterogony", ctx.cynipini)
      assert own(Catalog.generation_group_flags()) == []
    end

    test "a deeper mapping overrides a higher one", ctx do
      map_group!("heterogony", ctx.cynipini)
      map_group!("seasonal", ctx.andricus)

      assert [flag] = own(Catalog.generation_group_flags())
      assert flag.kind == :generation_outside_groups
      assert flag.reason == :other_group
      assert flag.gall_id == ctx.gall.id
      assert flag.inducer_id == ctx.wasp.id
      assert flag.generation == "agamic"
    end

    test "with no ancestor mapped, any group mapped below the Inducer applies", ctx do
      family_gall = gall_fixture(generation: "sexual")
      cynipidae = taxon_fixture(rank: :family, name: "Cynipidae", kingdom: "Animalia")
      {:ok, _} = Gallformers.Taxa.place(test_actor(), ctx.cynipini, cynipidae)
      inducer!(cynipidae, family_gall, ctx.source)
      map_group!("heterogony", ctx.cynipini)

      assert own(Catalog.generation_group_flags()) == []
    end

    test "a generation with no group mapped for its Inducer is flagged", ctx do
      assert [%{reason: :no_groups, gall_id: gall_id}] = own(Catalog.generation_group_flags())
      assert gall_id == ctx.gall.id
    end
  end
end
