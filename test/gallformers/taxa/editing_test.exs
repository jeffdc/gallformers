defmodule Gallformers.Taxa.EditingTest do
  @moduledoc """
  The taxonomy admin's edits on `Gallformers.Taxa` (`a856` Task 8): a
  plant's editorial flags, removing synonyms and common names, deleting a
  taxon nothing refers to, and the section same-genus rule.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Taxa
  alias Gallformers.Taxa.CommonName
  alias Gallformers.Taxa.LegacyId
  alias Gallformers.Taxa.Taxon
  alias Gallformers.Taxa.TaxonName

  setup :audit_test_metadata

  defp changed_tables do
    Repo.all(from(c in test_audit_changes(), select: {c.table_name, c.op}))
  end

  describe "update_editorial/3" do
    test "sets a plant's data-complete flag and abundance, audited" do
      plant = plant_fixture()

      assert {:ok, %Taxon{datacomplete: true, abundance_id: 2}} =
               Taxa.update_editorial(test_actor(), plant, %{datacomplete: true, abundance_id: 2})

      assert %Taxon{datacomplete: true, abundance_id: 2} = Taxa.get_taxon!(plant.id)
      assert {"taxa", :update} in changed_tables()
    end

    test "clears the abundance with nil" do
      plant = plant_fixture(abundance_id: 2)

      assert {:ok, %Taxon{abundance_id: nil}} =
               Taxa.update_editorial(test_actor(), plant.id, %{abundance_id: nil})
    end

    test "only takes the editorial fields" do
      plant = plant_fixture()

      assert {:ok, taxon} =
               Taxa.update_editorial(test_actor(), plant, %{rank: :genus, datacomplete: true})

      assert taxon.rank == :species
    end

    test "an unknown abundance is an error and nothing changes" do
      plant = plant_fixture()

      assert {:error, changeset} =
               Taxa.update_editorial(test_actor(), plant, %{abundance_id: 999_999})

      assert %{abundance_id: [_]} = errors_on(changeset)
      assert Taxa.get_taxon!(plant.id).abundance_id == nil
    end
  end

  describe "remove_synonym/2" do
    test "removes a synonym, audited, and it no longer resolves" do
      taxon = taxon_fixture(name: "Andricus foo")
      {:ok, synonym} = Taxa.add_synonym(test_actor(), taxon, "Cynips foo")

      assert {:ok, %TaxonName{name: "Cynips foo"}} = Taxa.remove_synonym(test_actor(), synonym)

      assert Taxa.list_synonyms(taxon) == []
      assert Taxa.resolve_name("Cynips foo") == :none
      assert {"taxon_names", :delete} in changed_tables()
    end

    test "takes the synonym's ID" do
      taxon = taxon_fixture()
      {:ok, synonym} = Taxa.add_synonym(test_actor(), taxon, "Cynips bar")

      assert {:ok, _} = Taxa.remove_synonym(test_actor(), synonym.id)
      assert Taxa.list_synonyms(taxon) == []
    end

    test "refuses the accepted name" do
      taxon = taxon_fixture(name: "Andricus kept")
      [accepted] = Taxa.get_taxon!(taxon.id).names

      assert {:error, :accepted_name} = Taxa.remove_synonym(test_actor(), accepted)
      assert Taxa.accepted_name(taxon) == "Andricus kept"
    end
  end

  describe "remove_common_name/2" do
    test "removes a common name, audited" do
      taxon = taxon_fixture()
      {:ok, common} = Taxa.add_common_name(test_actor(), taxon, "Oak apple wasp")
      {:ok, _other} = Taxa.add_common_name(test_actor(), taxon, "Other name")

      assert {:ok, %CommonName{name: "Oak apple wasp"}} =
               Taxa.remove_common_name(test_actor(), common)

      assert Enum.map(Taxa.list_common_names(taxon), & &1.name) == ["Other name"]
      assert {"taxon_common_names", :delete} in changed_tables()
    end

    test "takes the common name's ID" do
      taxon = taxon_fixture()
      {:ok, common} = Taxa.add_common_name(test_actor(), taxon, "Oaks")

      assert {:ok, _} = Taxa.remove_common_name(test_actor(), common.id)
      assert Taxa.list_common_names(taxon) == []
    end
  end

  describe "references/1 and delete_taxon/2" do
    test "an unreferenced taxon is deleted with its own names, common names and crosswalk" do
      genus = taxon_fixture(rank: :genus, name: "Deletus")
      taxon = taxon_fixture(name: "Deletus mistakus", parent: genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), taxon, "Deletus erratus")
      {:ok, _} = Taxa.add_common_name(test_actor(), taxon, "Mistake")
      {:ok, _} = Taxa.add_legacy_id(test_actor(), taxon, :taxonomy, 987_654, "Deletus mistakus")

      refute Taxa.referenced?(taxon)
      assert Taxa.references(taxon) == []

      assert {:ok, %Taxon{id: id}} = Taxa.delete_taxon(test_actor(), taxon)
      assert id == taxon.id

      assert Taxa.get_taxon(taxon.id) == nil
      assert Repo.aggregate(from(n in TaxonName, where: n.taxon_id == ^id), :count) == 0
      assert Repo.aggregate(from(c in CommonName, where: c.taxon_id == ^id), :count) == 0
      assert Repo.aggregate(from(l in LegacyId, where: l.taxon_id == ^id), :count) == 0
      assert Taxa.descendants(genus) == []
      assert Taxa.resolve_name("Deletus erratus") == :none

      changes = changed_tables()

      for table <- ~w(taxa taxon_names taxon_common_names legacy_taxon_ids),
          do: assert({table, :delete} in changes, table)
    end

    test "a taxon with children is refused, with the reason" do
      genus = taxon_fixture(rank: :genus)
      _child = taxon_fixture(parent: genus)

      assert Taxa.referenced?(genus) == true
      assert [%{table: "taxa", column: "parent_id", count: 1}] = Taxa.references(genus)

      assert {:error, {:referenced, [%{table: "taxa", column: "parent_id"}]}} =
               Taxa.delete_taxon(test_actor(), genus)

      assert %Taxon{} = Taxa.get_taxon(genus.id)
    end

    test "a plant with Host range rows is refused (its foreign key would only clear them)" do
      plant = plant_fixture()
      host_range_fixture(plant, [{"US-CA", "exact"}])

      assert [%{table: "host_range", column: "taxon_id", count: 1}] = Taxa.references(plant)
      assert {:error, {:referenced, _}} = Taxa.delete_taxon(test_actor(), plant.id)
      assert %Taxon{} = Taxa.get_taxon(plant.id)
    end

    test "a taxon a Relationship Fact or an act Fact names is refused" do
      source = source_fixture("Weld", "1959")
      wasp = taxon_fixture(kingdom: "Animalia")
      gall = gall_fixture()

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
          confirm(source)
        )

      assert %{table: "relationship_facts", column: "subject_taxon_id", count: 1} in Taxa.references(
               wasp
             )

      parent = taxon_fixture(rank: :genus, kingdom: "Animalia")
      placed = taxon_fixture(kingdom: "Animalia")

      {:ok, _} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: placed.id, parent_id: parent.id},
          confirm(source)
        )

      assert %{table: "placement_facts", column: "taxon_id", count: 1} in Taxa.references(placed)
      assert %{table: "placement_facts", column: "parent_id", count: 1} in Taxa.references(parent)
      assert {:error, {:referenced, _}} = Taxa.delete_taxon(test_actor(), placed)
    end

    test "every column that refers to a taxon is checked, except the taxon's own rows" do
      blocking = MapSet.new(Taxa.reference_columns())

      for ref <- [
            {"taxa", "parent_id"},
            {"relationship_facts", "subject_taxon_id"},
            {"relationship_facts", "object_taxon_id"},
            {"placement_facts", "taxon_id"},
            {"placement_facts", "parent_id"},
            {"name_facts", "taxon_id"},
            {"synonymy_facts", "accepted_taxon_id"},
            {"split_facts", "taxon_id"},
            {"split_fact_daughters", "taxon_id"},
            {"common_name_facts", "taxon_id"},
            {"galls", "host_qualifier_taxon_id"},
            {"host_range", "taxon_id"},
            {"image", "taxon_id"},
            {"generation_group_taxa", "taxon_id"},
            {"attribution_names", "taxon_id"},
            {"batch_statements", "taxon_id"}
          ] do
        assert MapSet.member?(blocking, ref), inspect(ref)
      end

      for own <- ~w(taxon_names taxon_common_names legacy_taxon_ids taxon_ancestry taxon_wcvp) do
        refute Enum.any?(blocking, &(elem(&1, 0) == own)), own
      end
    end
  end

  describe "place/3 under a section" do
    setup do
      quercus = plant_fixture(rank: :genus, name: "Quercus")
      lobatae = plant_fixture(rank: :section, name: "Lobatae", parent: quercus)
      acer = plant_fixture(rank: :genus, name: "Acer")
      %{quercus: quercus, lobatae: lobatae, acer: acer}
    end

    test "a plant species of the section's genus can be placed in it", ctx do
      rubra = plant_fixture(name: "Quercus rubra", parent: ctx.quercus)

      assert {:ok, %Taxon{parent_id: parent_id}} = Taxa.place(test_actor(), rubra, ctx.lobatae)
      assert parent_id == ctx.lobatae.id
    end

    test "a plant species of another genus is refused", ctx do
      rubrum = plant_fixture(name: "Acer rubrum", parent: ctx.acer)

      assert {:error, changeset} = Taxa.place(test_actor(), rubrum, ctx.lobatae)
      assert %{parent_id: ["must be in the section's genus, Quercus"]} = errors_on(changeset)
      assert Taxa.get_taxon!(rubrum.id).parent_id == ctx.acer.id
    end

    test "the genus is compared as names are, ignoring case", ctx do
      odd = plant_fixture(name: "quercus velutina", parent: ctx.quercus)
      assert {:ok, _} = Taxa.place(test_actor(), odd, ctx.lobatae)
    end
  end
end
