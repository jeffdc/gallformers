defmodule Gallformers.Import.InatTaxaPlanTest do
  @moduledoc """
  What bringing an iNaturalist taxon into our tree would do (matter `cb28`
  Task 3, `Gallformers.Import.InatTaxa.plan/2`): whether we hold the taxon
  (by its iNaturalist ID, else its name at its rank in its kingdom); its
  lineage, each rank held, needed to attach it (ticked), above the nearest
  one we hold (not ticked) or a rank we don't use; its children, held
  under another parent (to move) or not (to add); its names, the synonym
  that matched and iNaturalist's common name ticked; WCVP's authorship for
  a plant. Against iNaturalist's recorded taxa.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures
  import Gallformers.INaturalistFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Import
  alias Gallformers.Taxa

  setup :audit_test_metadata

  # Our tree as it is for Rubus: the family and genus, a species under the genus.
  defp rubus_tree do
    rosaceae = plant_fixture(rank: :family, name: "Rosaceae")
    rubus = plant_fixture(rank: :genus, name: "Rubus", parent: rosaceae)
    frondosus = plant_fixture(name: "Rubus frondosus", parent: rubus)
    %{rosaceae: rosaceae, rubus: rubus, frondosus: frondosus}
  end

  defp row(rows, name, rank), do: Enum.find(rows, &(&1.name == name and &1.rank == rank))
  defp states(rows), do: Enum.map(rows, &{&1.name, &1.state})

  describe "a plant we don't hold: Arguti, the section iNaturalist files Rubus pensilvanicus under" do
    setup do
      Map.put(
        rubus_tree(),
        :plan,
        Import.plan_inat_taxon(inat_taxon(1_449_402), "Rubus pensilvanicus")
      )
    end

    test "the taxon: new, at a rank we use, a plant", %{plan: plan} do
      assert plan.held == nil
      assert plan.name == "Arguti"
      assert plan.rank == "section"
      assert plan.ours == :section
      assert plan.kingdom == "Plantae"
      assert plan.plant? == true
      assert plan.active? == true
      assert plan.inat.id == 1_449_402
    end

    test "where it goes: subgenus Rubus needed; Rosoideae, Rubeae and the ranks above Rosaceae not",
         %{plan: plan, rosaceae: rosaceae, rubus: rubus} do
      assert states(plan.lineage) == [
               {"Plantae", :higher},
               {"Tracheophyta", :higher},
               {"Angiospermae", :higher},
               {"Magnoliopsida", :higher},
               {"Rosales", :higher},
               {"Rosaceae", :held},
               {"Rosoideae", :higher},
               {"Rubeae", :higher},
               {"Rubus", :held},
               {"Rubus", :needed}
             ]

      assert row(plan.lineage, "Rosaceae", "family").held.id == rosaceae.id
      assert row(plan.lineage, "Rubus", "genus").held.id == rubus.id

      subgenus = row(plan.lineage, "Rubus", "subgenus")
      assert subgenus.ours == :subgenus
      assert subgenus.key in plan.ticked
      refute row(plan.lineage, "Rosoideae", "subfamily").key in plan.ticked
      assert plan.held_any? == true
    end

    test "under it: the species we hold under Rubus to move, the rest to add, none ticked",
         %{plan: plan, frondosus: frondosus} do
      assert length(plan.children) == 26
      assert [first | rest] = plan.children

      assert %{name: "Rubus frondosus", state: :move, held: %{id: id, parent: "Rubus"}} = first
      assert id == frondosus.id
      assert Enum.uniq(Enum.map(rest, & &1.state)) == [:add]
      refute Enum.any?(plan.children, &(&1.key in plan.ticked))
    end

    test "names: the synonym that matched and iNaturalist's common name ticked", %{plan: plan} do
      matched = Enum.find(plan.synonyms, &(&1.name == "Rubus pensilvanicus"))
      assert matched.matched? == true
      assert matched.key in plan.ticked

      other = Enum.find(plan.synonyms, &(&1.name == "Rubus abactus"))
      refute other.matched?
      refute other.key in plan.ticked

      refute Enum.any?(plan.synonyms, &(&1.name == "Arguti"))

      preferred = Enum.find(plan.commons, &(&1.name == "Field Highbush Blackberries"))
      assert preferred.preferred? == true
      assert preferred.key in plan.ticked

      pennsylvania = Enum.find(plan.commons, &(&1.name == "Pennsylvania Blackberry"))
      refute pennsylvania.preferred?
      refute pennsylvania.key in plan.ticked

      # English only.
      refute Enum.any?(plan.commons, &(&1.name == "ronce de Pennsylvanie"))
    end
  end

  describe "a species: Rubus frondosus" do
    test "WCVP's authorship for the taxon added; its section and subgenus needed" do
      rosaceae = plant_fixture(rank: :family, name: "Rosaceae")
      _rubus = plant_fixture(rank: :genus, name: "Rubus", parent: rosaceae)

      plan = Import.plan_inat_taxon(inat_taxon(168_056), nil)

      assert plan.held == nil
      assert plan.authorship == %{"t" => "Bigelow"}
      assert {"Rubus", :needed} in states(plan.lineage)
      assert {"Arguti", :needed} in states(plan.lineage)
      assert plan.children == []

      # No name matched: no synonym ticked.
      refute Enum.any?(plan.synonyms, &(&1.key in plan.ticked))
    end

    test "held by its name at its rank: linked, and only what we don't hold offered" do
      %{frondosus: frondosus} = rubus_tree()
      {:ok, _} = Taxa.add_common_name(test_actor(), frondosus, "Yankee Blackberry")

      plan = Import.plan_inat_taxon(inat_taxon(168_056), nil)

      assert plan.held.id == frondosus.id
      assert plan.authorship == %{}
      refute Enum.any?(plan.commons, &(&1.name == "Yankee Blackberry"))

      assert %{preferred?: true} =
               Enum.find(plan.commons, &(&1.name == "Leafy-bracted Blackberry"))
    end

    test "held by its iNaturalist ID, whatever its name" do
      rosaceae = plant_fixture(rank: :family, name: "Rosaceae")
      other = plant_fixture(name: "Rubus leafyus", parent: rosaceae)
      {:ok, _} = Import.record_taxonomy_edit(test_actor(), {:set_inat, other, 168_056})

      assert Import.plan_inat_taxon(inat_taxon(168_056), nil).held.id == other.id
    end

    test "a plant of another name is not it, nor an animal of the same name" do
      _animal = taxon_fixture(name: "Rubus frondosus", kingdom: "Animalia")
      assert Import.plan_inat_taxon(inat_taxon(168_056), nil).held == nil
    end
  end

  describe "an animal family we have nothing above: Syrphidae" do
    test "every rank above it unticked, a rank we don't use skipped, its children to add" do
      plan = Import.plan_inat_taxon(inat_taxon(49_995), "Syrphidae")

      refute plan.plant?
      assert plan.kingdom == "Animalia"
      refute plan.held_any?

      assert states(plan.lineage) == [
               {"Animalia", :higher},
               {"Arthropoda", :higher},
               {"Hexapoda", :higher},
               {"Insecta", :higher},
               {"Pterygota", :higher},
               {"Diptera", :higher},
               {"Brachycera", :higher},
               {"Cyclorrhapha", :higher},
               {"Aschiza", :skipped}
             ]

      assert row(plan.lineage, "Aschiza", "zoosection").ours == nil
      refute Enum.any?(plan.lineage, &(&1.key in plan.ticked))

      assert Enum.map(plan.children, &{&1.name, &1.state}) == [
               {"Syrphinae", :add},
               {"Eristalinae", :add},
               {"Pipizinae", :add},
               {"Microdontinae", :add},
               {"Pia", :add}
             ]

      # The name that matched is its own: no synonym ticked.
      refute Enum.any?(plan.synonyms, &(&1.key in plan.ticked))
      assert %{name: "Hover Flies", preferred?: true} = Enum.find(plan.commons, & &1.preferred?)
      assert plan.authorship == %{}
    end

    test "a rank we hold with no kingdom recorded is held; the ranks below it needed" do
      diptera = taxon_fixture(rank: :order, name: "Diptera")
      assert diptera.kingdom == nil
      plan = Import.plan_inat_taxon(inat_taxon(49_995), nil)
      assert row(plan.lineage, "Diptera", "order").held.id == diptera.id
      assert {"Brachycera", :needed} in states(plan.lineage)
      assert {"Cyclorrhapha", :needed} in states(plan.lineage)
    end
  end

  describe "a rank we don't use" do
    test "the taxon's own: no rank of ours; in its lineage: skipped" do
      rubus_tree()
      plan = Import.plan_inat_taxon(inat_taxon(1_449_411), nil)

      assert plan.rank == "complex"
      assert plan.ours == nil
      assert %{state: :skipped, ours: nil} = row(plan.lineage, "Rubus", "subsection")
      assert row(plan.lineage, "Rubus", "section").state == :needed
    end
  end

  describe "an inactive taxon" do
    test "says so, and which taxon replaced it" do
      plan = Import.plan_inat_taxon(inat_taxon(78_894), "Rubus pensilvanicus")
      refute plan.active?
      assert plan.replaced_by == [1_449_402]
    end
  end

  describe "a taxon we hold" do
    test "a child held under it is held; one held elsewhere is to move" do
      %{rubus: rubus} = rubus_tree()
      arguti = plant_fixture(rank: :section, name: "Arguti", parent: rubus)
      _argutus = plant_fixture(name: "Rubus argutus", parent: arguti)

      plan = Import.plan_inat_taxon(inat_taxon(1_449_402), nil)

      assert plan.held.id == arguti.id
      assert %{state: :held} = Enum.find(plan.children, &(&1.name == "Rubus argutus"))
      assert %{state: :move} = Enum.find(plan.children, &(&1.name == "Rubus frondosus"))
    end
  end
end
