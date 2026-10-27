defmodule Gallformers.Catalog.GallPageTest do
  @moduledoc """
  The Gall page's read model (`Gallformers.Catalog.gall_page/1`).

  Mostly the converted seeds (`priv/repo/test_seeds.sql`, checked by
  `Gallformers.CatalogMigration.TestSeedsTest`): Galls 300/301 are an
  agamic/sexgen pair of Andricus seedii, 302/303 gall forms of Neuroterus
  seedatorius, 304 an undescribed Andricus gall with a genus Host, and 100
  a Gall with no Inducer; all but 100 are hosted on plant 10.

  Not async: some tests use the Gallformers Source (see
  `Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false

  # Reading the seeds, converted, is most of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.ReadModels.GallPage
  alias Gallformers.Facts.Attribution
  alias Gallformers.Ranges.DisplayRange
  alias Gallformers.Sources
  alias Gallformers.Taxa

  defp page!(id) do
    assert {:ok, %GallPage{} = page} = Catalog.gall_page(id)
    page
  end

  defp genus(old_taxonomy_id), do: Taxa.get_by_legacy_id(:taxonomy, old_taxonomy_id)

  describe "a described Gall" do
    setup do
      %{page: page!(300)}
    end

    test "has its name, code, abundance, completeness and generation", %{page: page} do
      assert page.id == 300
      assert page.name == "Andricus seedii (agamic)"
      assert page.gallformers_code == nil
      assert page.abundance == "common"
      assert page.datacomplete == true
      assert %{value: "agamic", name_qualifier: "agamic"} = page.generation
      refute page.undescribed?
      assert %DateTime{} = page.updated_at
    end

    test "has its Inducer with the Inducer's lineage, root first", %{page: page} do
      assert [inducer] = page.inducers
      assert {inducer.name, inducer.rank} == {"Andricus seedii", :species}

      assert Enum.map(inducer.lineage, &{&1.name, &1.rank}) == [
               {"Cynipidae", :family},
               {"Cynipinae", :subfamily},
               {"Cynipini", :tribe},
               {"Andricus", :genus},
               {"Andricus seedii", :species}
             ]
    end

    test "has its Hosts, a species-rank plant linking to its host page", %{page: page} do
      assert page.hosts == [
               %{
                 taxon_id: 10,
                 name: "Notholithocarpus densiflorus",
                 rank: :species,
                 link: {:host, 10}
               }
             ]
    end

    test "has its Traits by Trait", %{page: page} do
      assert page.traits == %{"detachable" => ["detachable"]}
    end

    test "has its common names and its Inducer's synonyms", %{page: page} do
      assert page.common_names == ["seed oak apple"]
      assert page.synonyms == [%{name: "Callirhytis seedii", sensu: nil}]
    end

    test "lists the other generation of its Inducer as related", %{page: page} do
      assert page.related_galls == [%{id: 301, name: "Andricus seedii (sexgen)"}]
    end

    test "has the default citation first, then the Gallformers note, with their Sources",
         %{page: page} do
      assert [citation, note] = page.sources

      assert %{
               id: 59,
               title: "Cynipid galls of the seed slope",
               author: "Weld, L. H.",
               pubyear: "1957",
               useasdefault: true,
               externallink: "https://example.com/seed-slope#p12",
               note?: false
             } = citation

      assert citation.description =~ "seed citation"

      assert %{id: 58, title: "Gallformers ID Notes", useasdefault: false, note?: true} = note
      assert note.description =~ "seed note"
      assert note.license == "Public Domain / CC0"
    end

    test "has its images", %{page: page} do
      assert [%{id: 1, path: "gall/300/300_seed_original.jpg"}] = page.images
    end

    test "has its display range", %{page: page} do
      assert %DisplayRange{introduced_range: ["RO-B"]} = page.display_range
      assert Enum.sort(page.display_range.in_range) == ["RO-B", "US-CA"]
    end

    test "carries each current Fact's attributions, not for display", %{page: page} do
      assert [%Attribution{} | _] = page.attributions[{:inducer, hd(page.inducers).taxon_id}]
      assert [%Attribution{} | _] = page.attributions[{:host, 10}]
      assert [%Attribution{} | _] = page.attributions[{:trait, "detachable", "detachable"}]
      assert [%Attribution{} | _] = page.attributions[{:alias, "seed oak apple"}]
    end
  end

  test "an undescribed Gall (a genus Inducer) is undescribed and has its Code" do
    page = page!(304)

    assert page.undescribed? == true
    assert page.gallformers_code == "n-densiflorus-seed-gall"
    assert [%{name: "Andricus", rank: :genus}] = page.inducers
    assert page.related_galls == []
  end

  test "a genus Host links to its genus page" do
    page = page!(304)
    notholithocarpus = genus(41)

    assert %{
             taxon_id: notholithocarpus.id,
             name: "Notholithocarpus",
             rank: :genus,
             link: {:genus, "Notholithocarpus"}
           } in page.hosts

    assert %{taxon_id: 10, link: {:host, 10}} = Enum.find(page.hosts, &(&1.taxon_id == 10))
  end

  test "the generation pair and the gall form pair list each other as related" do
    assert page!(301).related_galls == [%{id: 300, name: "Andricus seedii (agamic)"}]

    assert page!(302).related_galls == [%{id: 303, name: "Neuroterus seedatorius (sexgen)"}]

    assert page!(303).related_galls == [
             %{id: 302, name: "Neuroterus seedatorius (australis) (agamic)"}
           ]
  end

  test "a Gall with no Inducer has none, no lineage and no related Galls, and is undescribed" do
    page = page!(100)

    assert page.inducers == []
    assert page.related_galls == []
    assert page.synonyms == []
    assert page.undescribed? == true
  end

  test "the newest Gallformers note is shown; legacy citations sort by title after the note" do
    gallformers = gallformers_source()
    gall = gall_fixture()
    {:ok, _} = Sources.store_note(test_actor(), gallformers, gall.id, "Old note.", ~D[2020-01-01])
    {:ok, _} = Sources.store_note(test_actor(), gallformers, gall.id, "New note.", ~D[2024-01-01])

    zebra = source_fixture("Zebra galls", "1990")
    apple = source_fixture("Apple galls", "1990")

    {:ok, 2} =
      Catalog.insert_legacy_citations(test_actor(), [
        %{gall_id: gall.id, source_id: zebra.id, description: "Z.", useasdefault: false},
        %{gall_id: gall.id, source_id: apple.id, description: "A.", useasdefault: false}
      ])

    page = page!(gall.id)

    assert Enum.map(page.sources, &{&1.id, &1.description}) == [
             {gallformers.id, "New note."},
             {apple.id, "A."},
             {zebra.id, "Z."}
           ]
  end

  test "a Gall whose default Source is its note leads with the note" do
    assert [note] = page!(301).sources

    assert %{id: 58, note?: true, useasdefault: true} = note
    assert note.description =~ "sexgen seed note"
  end

  test "the default Source leads, then the note, then the citations by title" do
    gallformers = gallformers_source()
    zebra = source_fixture("Zebra galls", "1990")
    apple = source_fixture("Apple galls", "1990")
    gall = gall_fixture(default_source_id: zebra.id)
    {:ok, _} = Sources.store_note(test_actor(), gallformers, gall.id, "Note.", ~D[2024-01-01])

    {:ok, 2} =
      Catalog.insert_legacy_citations(test_actor(), [
        %{gall_id: gall.id, source_id: zebra.id, description: "Z.", useasdefault: false},
        # The legacy flag no longer orders: the Gall's default Source does.
        %{gall_id: gall.id, source_id: apple.id, description: "A.", useasdefault: true}
      ])

    assert Enum.map(page!(gall.id).sources, &{&1.id, &1.useasdefault}) == [
             {zebra.id, true},
             {gallformers.id, false},
             {apple.id, false}
           ]
  end

  test "former labels and codes are not common names" do
    page = page!(304)

    assert page.common_names == []

    assert page.labels == [
             %{name: "Andricus q-seed-old-label", kind: :former_label},
             %{name: "q-seed-code", kind: :code}
           ]

    assert page!(300).labels == []
  end

  test "the name shown is the override where set" do
    gall = gall_fixture(name: "Derived name", name_override: "Shown name")
    assert page!(gall.id).name == "Shown name"
  end

  test ":not_found for a missing ID and for an ID that is not a Gall" do
    assert Catalog.gall_page(999_999_999) == :not_found
    assert Catalog.gall_page(10) == :not_found
  end
end
