defmodule Gallformers.Catalog.SearchGallsTest do
  @moduledoc """
  The gall part of the global search (`803b` Task 11):
  `Catalog.search_galls/2` finds Galls by their display name, their current
  alias Facts of every kind, and their current species-rank Inducer's
  accepted name and synonyms; `:place_ids` keeps the Galls whose potential
  range (`gall_index`) meets those places, and every `everywhere` Gall.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Taxa

  setup do
    %{source: source_fixture("Kinsey", "1920")}
  end

  defp inducer!(taxon, gall, source) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: taxon.id, object_gall_id: gall.id},
        confirm(source)
      )

    :ok
  end

  defp host!(plant, gall, source) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: plant.id, object_gall_id: gall.id},
        confirm(source)
      )

    :ok
  end

  defp alias!(gall, name, kind, attribution) do
    {:ok, _} =
      Catalog.assert_alias(test_actor(), %{gall_id: gall.id, name: name, kind: kind}, attribution)

    :ok
  end

  defp ids(results), do: results |> Enum.map(& &1.id) |> Enum.sort()

  describe "search_galls/2" do
    test "finds a Gall by its display name, every word anywhere in it" do
      gall = gall_fixture(name: "Qxsearch gall", name_override: "Qxsearchus crystallinus")

      assert [%{id: id, name: "Qxsearchus crystallinus"}] =
               Catalog.search_galls("qxsearch crystal", [])

      assert id == gall.id
      assert Catalog.search_galls("qxsearch nothing", []) == []
      assert Catalog.search_galls("  ", []) == []
    end

    test "finds a Gall by a current alias Fact of every kind", %{source: source} do
      gall = gall_fixture(name: "Qxalias gall")
      alias!(gall, "Qxpurple bead", :common_name, confirm(source))
      alias!(gall, "Qxandricus q-old-label", :former_label, confirm(source))
      alias!(gall, "QX-CODE-7", :code, confirm(source))

      for query <- ["qxpurple bead", "q-old-label", "qx-code"] do
        assert ids(Catalog.search_galls(query, [])) == [gall.id], query
      end

      assert [%{aliases: aliases}] = Catalog.search_galls("qxalias", [])

      assert Enum.sort(aliases) ==
               Enum.sort(["Qxpurple bead", "Qxandricus q-old-label", "QX-CODE-7"])
    end

    test "an alias Fact no longer current finds nothing", %{source: source} do
      gall = gall_fixture(name: "Qxdenied gall")
      alias!(gall, "Qxgone name", :common_name, confirm(source))
      alias!(gall, "Qxgone name", :common_name, deny(source_fixture("Revision", "1990")))

      assert Catalog.search_galls("qxgone", []) == []
    end

    test "an Inducer's synonym or accepted name finds its Galls", %{source: source} do
      genus = taxon_fixture(rank: :genus, name: "Qxinducer", kingdom: "Animalia")
      wasp = taxon_fixture(name: "Qxinducer seedii", kingdom: "Animalia", parent: genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), wasp, "Qxcallirhytis seedii")
      agamic = gall_fixture(name: "Qxgall one (agamic)")
      sexgen = gall_fixture(name: "Qxgall one (sexgen)")
      inducer!(wasp, agamic, source)
      inducer!(wasp, sexgen, source)

      assert ids(Catalog.search_galls("qxcallirhytis", [])) == Enum.sort([agamic.id, sexgen.id])

      assert ids(Catalog.search_galls("qxinducer seedii", [])) ==
               Enum.sort([agamic.id, sexgen.id])

      assert [%{aliases: ["Qxcallirhytis seedii"]} | _] =
               Catalog.search_galls("qxcallirhytis", [])
    end

    test "an Inducer above species finds its Galls only by their own names", %{source: source} do
      tribe = taxon_fixture(rank: :tribe, name: "Qxtribini", kingdom: "Animalia")
      gall = gall_fixture(name: "Unknown qx-midrib-cluster")
      inducer!(tribe, gall, source)

      assert Catalog.search_galls("qxtribini", []) == []
      assert ids(Catalog.search_galls("qx-midrib", [])) == [gall.id]
    end

    test "says whether each Gall is undescribed, by name", %{source: source} do
      wasp = taxon_fixture(name: "Qxdesc wasp", kingdom: "Animalia")
      described = gall_fixture(name: "Qxdesc b")
      undescribed = gall_fixture(name: "Qxdesc a")
      inducer!(wasp, described, source)
      inducer!(taxon_fixture(rank: :genus, name: "Qxdescgenus"), undescribed, source)

      assert [
               %{id: first, undescribed: true},
               %{id: second, undescribed: false}
             ] = Catalog.search_galls("qxdesc", [])

      assert {first, second} == {undescribed.id, described.id}
    end
  end

  describe "search_galls/2 with :place_ids" do
    test "keeps Galls whose range meets the places, and every everywhere Gall", %{source: source} do
      california = plant_fixture(name: "Qxplace californica")
      host_range_fixture(california, [{"US-CA", "exact"}])
      romania = plant_fixture(name: "Qxplace romanica")
      host_range_fixture(romania, [{"RO-B", "exact"}])

      in_ca = gall_fixture(name: "Qxplace ca")
      host!(california, in_ca, source)
      in_ro = gall_fixture(name: "Qxplace ro")
      host!(romania, in_ro, source)
      no_range = gall_fixture(name: "Qxplace norange")
      host!(plant_fixture(), no_range, source)
      no_row = gall_fixture(name: "Qxplace nofacts")

      assert ids(Catalog.search_galls("qxplace", place_ids: [place_id("US-CA")])) ==
               Enum.sort([in_ca.id, no_range.id, no_row.id])

      assert ids(Catalog.search_galls("qxplace", place_ids: [place_id("RO-B")])) ==
               Enum.sort([in_ro.id, no_range.id, no_row.id])

      assert length(Catalog.search_galls("qxplace", place_ids: nil)) == 4
    end
  end
end
