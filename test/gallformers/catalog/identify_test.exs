defmodule Gallformers.Catalog.IdentifyTest do
  @moduledoc """
  The ID tool's query over the lookup table (`803b` Task 9,
  `Gallformers.Catalog.Identify`): `Catalog.identify/1`,
  `Catalog.count_identified/1`, `Catalog.identify_options/0` and
  `Catalog.gall_families_for_hosts/1`.

  The fixture Galls' rows are refreshed as their Facts are asserted (Oban
  runs inline in tests). Results are narrowed to this test's Galls: the
  converted seeds have rows too.

  Not async: loads the vocabularies (see `Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Vocab.TraitValue

  setup do
    load_vocab!()
    source = source_fixture("Weld", "1959")

    fagaceae = plant_fixture(rank: :family, name: "Fixturaceae")
    quercus = plant_fixture(rank: :genus, name: "Fixturquercus", parent: fagaceae)
    lobatae = plant_fixture(rank: :section, name: "Fixturlobatae", parent: quercus)
    alba = plant_fixture(name: "Fixturquercus alba", parent: quercus)
    rubra = plant_fixture(name: "Fixturquercus rubra", parent: lobatae)
    rangeless = plant_fixture(name: "Fixturquercus nullus", parent: quercus)
    host_range_fixture(alba, [{"US-CA", "exact"}])
    host_range_fixture(rubra, [{"CA", "country"}, {"BS", "exact", "introduced"}])

    cynipidae = taxon_fixture(rank: :family, name: "Fixturcynipidae", kingdom: "Animalia")
    andricus = taxon_fixture(rank: :genus, name: "Fixturandricus", parent: cynipidae)
    wasp1 = taxon_fixture(name: "Fixturandricus unus", parent: andricus)
    wasp2 = taxon_fixture(name: "Fixturandricus duo", parent: andricus)
    figitidae = taxon_fixture(rank: :family, name: "Fixturfigitidae", kingdom: "Animalia")
    other_genus = taxon_fixture(rank: :genus, name: "Fixturfigites", parent: figitidae)
    wasp3 = taxon_fixture(name: "Fixturfigites tres", parent: other_genus)

    g1 = gall!("Fixtura one", wasp1, [alba], source)

    traits!(
      g1,
      [{"color", "red"}, {"plant_part", "upper leaf"}, {"plant_part", "lower leaf"}],
      source
    )

    traits!(g1, [{"texture", "hairy"}, {"detachable", "integral"}], source)

    g2 = gall!("Fixtura two", wasp2, [rubra], source)
    traits!(g2, [{"color", "brown"}, {"plant_part", "upper leaf"}], source)
    traits!(g2, [{"texture", "hairy"}, {"texture", "woolly"}, {"detachable", "both"}], source)

    g3 = gall!("Fixtura three", andricus, [quercus], source)
    traits!(g3, [{"detachable", "detachable"}], source)

    g4 = gall!("Fixtura four", wasp3, [alba], source)
    g5 = gall!("Fixtura five", wasp3, [rangeless], source)

    image =
      Repo.insert_all(
        "image",
        [%{species_id: 300, gall_id: g1.id, path: "gall/#{g1.id}/fixture_original.jpg"}],
        returning: [:path]
      )

    {1, [%{path: path}]} = image
    :ok = Catalog.refresh_gall_index([g1.id])

    %{
      source: source,
      quercus: quercus,
      lobatae: lobatae,
      alba: alba,
      rubra: rubra,
      cynipidae: cynipidae,
      andricus: andricus,
      figitidae: figitidae,
      galls: %{g1: g1, g2: g2, g3: g3, g4: g4, g5: g5},
      image_path: path
    }
  end

  defp gall!(name, inducer, hosts, source) do
    gall = gall_fixture(name: name)

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: inducer.id, object_gall_id: gall.id},
        confirm(source)
      )

    for host <- hosts do
      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "host_of", subject_taxon_id: host.id, object_gall_id: gall.id},
          confirm(source)
        )
    end

    gall
  end

  defp traits!(gall, traits, source) do
    for {trait, value} <- traits do
      {:ok, _} =
        Catalog.assert_trait(
          test_actor(),
          %{gall_id: gall.id, trait: trait, value: value},
          confirm(source)
        )
    end
  end

  # The fixture Galls a filter finds, by key, in result order.
  defp found(ctx, filters) do
    keys = Map.new(ctx.galls, fn {key, gall} -> {gall.id, key} end)
    for %{id: id} <- Catalog.identify(filters), key = keys[id], do: key
  end

  describe "identify/1, one filter at a time" do
    test "a Host finds the Galls on it", ctx do
      assert found(ctx, %{host_id: ctx.alba.id}) == [:g4, :g1]
      assert found(ctx, %{host_id: ctx.rubra.id}) == [:g2]
    end

    test "a Host genus finds the Galls on its plants, and on the genus itself", ctx do
      assert found(ctx, %{host_group_id: ctx.quercus.id}) == [:g5, :g4, :g1, :g3, :g2]
    end

    test "a Host section finds the Galls on its plants only", ctx do
      assert found(ctx, %{host_group_id: ctx.lobatae.id}) == [:g2]
    end

    test "an Inducer family finds its Galls, an Inducer at a genus in it too", ctx do
      assert found(ctx, %{inducer_family_id: ctx.cynipidae.id}) == [:g1, :g3, :g2]
      assert found(ctx, %{inducer_family_id: ctx.figitidae.id}) == [:g5, :g4]
    end

    test "a Trait value", ctx do
      assert found(ctx, %{traits: %{"color" => ["red"]}}) == [:g1]
      assert found(ctx, %{traits: %{"color" => ["red", "brown"]}}) == [:g1, :g2]
    end

    test "plant parts and textures match any value, or all of them", ctx do
      parts = %{"plant_part" => ["upper leaf", "lower leaf"]}
      assert found(ctx, %{traits: parts}) == [:g1, :g2]
      assert found(ctx, %{traits: parts, trait_logic: %{"plant_part" => :and}}) == [:g1]

      textures = %{"texture" => ["hairy", "woolly"]}
      assert found(ctx, %{traits: textures, trait_logic: %{"texture" => :and}}) == [:g2]
    end

    test "an unknown Trait value matches nothing", ctx do
      assert found(ctx, %{traits: %{"color" => ["chartreuse"]}}) == []
      assert found(ctx, %{traits: %{"color" => ["red", "chartreuse"]}}) == [:g1]

      assert found(ctx, %{
               traits: %{"plant_part" => ["upper leaf", "nowhere"]},
               trait_logic: %{"plant_part" => :and}
             }) == []
    end

    test "detachable: integral or detachable include both; both is only both", ctx do
      assert found(ctx, %{detachable: "integral"}) == [:g1, :g2]
      assert found(ctx, %{detachable: "detachable"}) == [:g3, :g2]
      assert found(ctx, %{detachable: "both"}) == [:g2]
      assert length(found(ctx, %{detachable: "unknown"})) == 5
    end

    test "undescribed", ctx do
      assert found(ctx, %{undescribed: true}) == [:g3]
      assert length(found(ctx, %{undescribed: false})) == 5
    end

    test "a place matches the Galls whose potential range meets it, and Galls found everywhere",
         ctx do
      # g3's only Host is the genus, which has no range rows of its own: its
      # range is its species' (US-CA, CA, BS; `803b` decision 8). g5's Host
      # has no range data: it is everywhere.
      assert found(ctx, %{place_codes: ["US-CA"]}) == [:g5, :g4, :g1, :g3]
      # A country matches its subdivisions; an introduced range counts.
      assert found(ctx, %{place_codes: ["CA"]}) == [:g5, :g3, :g2]
      assert found(ctx, %{place_codes: ["BS"]}) == [:g5, :g3, :g2]
      # A subdivision matches a country-level range; a continent its countries.
      assert found(ctx, %{place_codes: ["CA-AB"]}) == [:g5, :g3, :g2]
      assert found(ctx, %{place_codes: ["XN"]}) == [:g5, :g4, :g1, :g3, :g2]
      assert found(ctx, %{place_codes: ["RO-B"]}) == [:g5]
      assert found(ctx, %{place_codes: ["NOWHERE"]}) == [:g5]
    end
  end

  describe "identify/1, filters combined" do
    test "every filter must hold", ctx do
      filters = %{host_group_id: ctx.quercus.id, place_codes: ["US-CA"], detachable: "integral"}
      assert found(ctx, filters) == [:g1]

      assert found(ctx, %{host_id: ctx.alba.id, inducer_family_id: ctx.figitidae.id}) == [:g4]
      assert found(ctx, %{host_id: ctx.alba.id, traits: %{"color" => ["brown"]}}) == []
    end

    test "count_identified/1 counts the same Galls, with or without the place", ctx do
      filters = %{host_group_id: ctx.quercus.id, place_codes: ["CA"]}

      assert Catalog.count_identified(filters) == length(Catalog.identify(filters))
      assert Catalog.count_identified(filters) == 3
      assert Catalog.count_identified(%{filters | place_codes: nil}) == 5
    end
  end

  describe "results" do
    test "carry the name, flags, default image and Traits, by name", ctx do
      results = Catalog.identify(%{host_group_id: ctx.quercus.id})

      assert Enum.map(results, & &1.name) ==
               ["Fixtura five", "Fixtura four", "Fixtura one", "Fixtura three", "Fixtura two"]

      one = Enum.find(results, &(&1.id == ctx.galls.g1.id))
      assert one.undescribed == false
      assert one.detachable == "integral"
      assert one.image_url =~ String.replace(ctx.image_path, "original", "small")

      assert one.traits == %{
               "color" => ["red"],
               "detachable" => ["integral"],
               "plant_part" => ["lower leaf", "upper leaf"],
               "texture" => ["hairy"]
             }

      three = Enum.find(results, &(&1.id == ctx.galls.g3.id))
      assert %{undescribed: true, image_url: nil} = three
    end
  end

  describe "identify_options/0" do
    test "lists each Trait's values in order" do
      options = Catalog.identify_options()

      assert Enum.map(options["season"], & &1.value) == ~w(Fall Spring Summer Winter)
      assert "upper leaf" in Enum.map(options["plant_part"], & &1.value)
      assert Map.keys(options) |> Enum.sort() == Enum.sort(TraitValue.traits())
      assert %TraitValue{trait: "color", value: "UV"} = hd(options["color"])
    end
  end

  describe "gall_families_for_hosts/1" do
    test "gives the Inducer families of the Galls on the Hosts, by name", ctx do
      assert Catalog.gall_families_for_hosts([ctx.alba.id]) == [
               %{id: ctx.cynipidae.id, name: "Fixturcynipidae"},
               %{id: ctx.figitidae.id, name: "Fixturfigitidae"}
             ]

      assert Catalog.gall_families_for_hosts([ctx.rubra.id]) == [
               %{id: ctx.cynipidae.id, name: "Fixturcynipidae"}
             ]

      # A genus covers the Galls on its plants and on itself.
      assert length(Catalog.gall_families_for_hosts([ctx.quercus.id])) == 2
      assert Catalog.gall_families_for_hosts([]) == []
    end
  end
end
