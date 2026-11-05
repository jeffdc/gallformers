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
  alias Gallformers.Facts
  alias Gallformers.Sources

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

  describe "identify/1, leaf and the leaf values (d213)" do
    # g1 is on upper leaf and lower leaf, g2 on upper leaf only.
    setup ctx do
      galls =
        for {key, part} <- [leaf: "leaf", lower: "lower leaf", petiole: "petiole"], into: %{} do
          gall = gall!("Fixtura #{key}", ctx.andricus, [ctx.alba], ctx.source)
          traits!(gall, [{"plant_part", part}], ctx.source)
          {key, gall}
        end

      %{galls: Map.merge(ctx.galls, galls)}
    end

    defp parts(ctx, values, logic \\ :or) do
      ctx
      |> found(%{traits: %{"plant_part" => values}, trait_logic: %{"plant_part" => logic}})
      |> Enum.sort()
    end

    test "leaf finds the Galls on the leaf and on every leaf value, not the petiole", ctx do
      assert parts(ctx, ["leaf"]) == [:g1, :g2, :leaf, :lower]
    end

    test "a leaf value finds the Galls on it and those only on the leaf, not another leaf value",
         ctx do
      assert parts(ctx, ["lower leaf"]) == [:g1, :leaf, :lower]
      assert parts(ctx, ["upper leaf"]) == [:g1, :g2, :leaf]
    end

    test "all of several leaf values: each is that value or leaf", ctx do
      assert parts(ctx, ["upper leaf", "lower leaf"], :and) == [:g1, :leaf]
    end

    test "the petiole is not on the leaf", ctx do
      assert parts(ctx, ["petiole"]) == [:petiole]
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

  describe "filter_identified/2, the results' text search (d213)" do
    setup ctx do
      kinsey = source_fixture("Kinsey", "1959")

      # A term placed for every Source: any Gall on its category is found by it.
      {:ok, _} =
        Catalog.place_term(test_actor(), "shape", "Fixturoval", "globular", :agreement)

      {:ok, _} =
        Catalog.assert_trait(
          test_actor(),
          %{gall_id: ctx.galls.g4.id, trait: "shape", value: "globular"},
          confirm(kinsey, %{term: "fixturbulbous egg-shaped"})
        )

      traits!(ctx.galls.g5, [{"shape", "globular"}], ctx.source)
      :ok
    end

    defp searched(ctx, text) do
      keys = Map.new(ctx.galls, fn {key, gall} -> {gall.id, key} end)
      results = Catalog.identify(%{host_group_id: ctx.quercus.id})
      for %{id: id} <- Catalog.filter_identified(results, text), key = keys[id], do: key
    end

    test "finds a Gall by its name, ignoring case", ctx do
      assert searched(ctx, "fixtura ON") == [:g1]
      assert searched(ctx, "fixtura") == [:g5, :g4, :g1, :g3, :g2]
      assert searched(ctx, "") == [:g5, :g4, :g1, :g3, :g2]
      assert searched(ctx, "  ") == [:g5, :g4, :g1, :g3, :g2]
    end

    test "finds a Gall by a Trait value", ctx do
      assert searched(ctx, "globular") == [:g5, :g4]
      assert searched(ctx, "Upper Leaf") == [:g1, :g2]
    end

    test "finds a Gall on a term's category through the term table", ctx do
      assert searched(ctx, "fixturoval") == [:g5, :g4]
      assert searched(ctx, "FixturOval") == [:g5, :g4]
    end

    test "finds a Gall by the term its Source used", ctx do
      assert searched(ctx, "fixturbulbous") == [:g4]
      assert searched(ctx, "egg-shaped fixturbulbous") == [:g4]
    end

    test "every word must match; a word in a term matches whole", ctx do
      assert searched(ctx, "fixtura fixturoval") == [:g5, :g4]
      assert searched(ctx, "red hairy") == [:g1]
      # "hair" is in neither "hairy" nor "hairless" as a word, nor in a name.
      assert searched(ctx, "hair") == []
      assert searched(ctx, "fixturbulb") == []
      # A word such as "on" or "the" (of the leaf rule, "on the leaf") finds nothing on its own.
      assert searched(ctx, "the") == []
      assert searched(ctx, "on") == [:g1]
    end

    test "a term waiting on a question is not searched", ctx do
      origin = package_and_batch()

      {:ok, _} =
        Catalog.put_pending_term(
          test_actor(),
          Map.merge(origin, %{
            gall_id: ctx.galls.g3.id,
            source_id: ctx.source.id,
            trait: "texture",
            term: "fixturrugose"
          })
        )

      assert searched(ctx, "fixturrugose") == []
    end

    test "a retracted Source's term is not searched", ctx do
      retracted = source_fixture("Retracted", "1960")
      notice = source_fixture("Retraction notice", "1961")

      {:ok, _} =
        Catalog.assert_trait(
          test_actor(),
          %{gall_id: ctx.galls.g5.id, trait: "shape", value: "globular"},
          confirm(retracted, %{term: "fixturlenticular"})
        )

      assert searched(ctx, "fixturlenticular") == [:g5]

      {:ok, _} = Sources.retract_source(test_actor(), retracted, notice, ~D[1961-06-01])
      {:ok, _} = Facts.recompute_for_source(test_actor(), retracted.id)

      assert searched(ctx, "fixturlenticular") == []
      assert searched(ctx, "globular") == [:g5, :g4]
    end

    test "the filter lists stay the Trait values, without terms", ctx do
      assert searched(ctx, "fixturoval") != []
      refute "Fixturoval" in Enum.map(Catalog.identify_options()["shape"], & &1.value)
      assert found(ctx, %{traits: %{"shape" => ["Fixturoval"]}}) == []
    end
  end

  defp package_and_batch do
    n = System.unique_integer([:positive])
    now = ~U[2026-11-01 00:00:00Z]

    {1, [%{id: package_id}]} =
      Repo.insert_all(
        "import_packages",
        [
          %{
            key: "pkg-#{n}",
            s3_prefix: "import/pkg-#{n}/",
            submitter_name: "test",
            inserted_at: now,
            updated_at: now
          }
        ],
        returning: [:id]
      )

    {1, [%{id: batch_id}]} =
      Repo.insert_all(
        "import_batches",
        [
          %{
            package_id: package_id,
            file: "gall.json",
            batch_type: "gall",
            mode: "add",
            producer_batch_id: "batch-#{n}",
            sha256: "0",
            content: %{},
            inserted_at: now,
            updated_at: now
          }
        ],
        returning: [:id]
      )

    %{package_id: package_id, batch_id: batch_id}
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
