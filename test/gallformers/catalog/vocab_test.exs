defmodule Gallformers.Catalog.VocabTest do
  @moduledoc """
  Catalog vocabularies (`9449` §4, Task 8): Trait values and term mappings
  loaded from the contract (`priv/import/vocab/traits.json`), the provisional
  generation groups, and the fixed list of Relationship types.

  Not async: the vocabulary tables are unique on their values, so concurrent
  sandbox transactions loading them wait on each other.
  """
  use Gallformers.DataCase, async: false

  alias Gallformers.Catalog
  alias Gallformers.Catalog.RelationshipTypes
  alias Gallformers.Catalog.Vocab.GenerationGroup
  alias Gallformers.Catalog.Vocab.GenerationGroupTaxon
  alias Gallformers.Catalog.Vocab.GenerationValue
  alias Gallformers.Catalog.Vocab.TraitTermMapping
  alias Gallformers.Catalog.Vocab.TraitValue

  @vocab_dir Path.expand("../../../priv/import/vocab", __DIR__)

  defp contract(file), do: @vocab_dir |> Path.join(file) |> File.read!() |> Jason.decode!()

  defp audit_change_count, do: Repo.aggregate(Carbonite.Change, :count)

  describe "Relationship types" do
    test "match the contract's three endpoint groups" do
      defs = contract("relationships.schema.json")["$defs"]

      for {group, endpoints} <- [
            {"taxon_to_gall", :taxon_to_gall},
            {"gall_to_gall", :gall_to_gall},
            {"taxon_to_taxon_in_gall", :taxon_to_taxon_in_gall}
          ] do
        assert Enum.sort(RelationshipTypes.names(endpoints)) == Enum.sort(defs[group]["enum"])
      end

      assert Enum.sort(RelationshipTypes.names()) == Enum.sort(defs["type"]["enum"])
      assert length(RelationshipTypes.all()) == 15
    end

    test "each has a direction label, an inverse label and its endpoint kinds" do
      assert %{
               name: "host_of",
               label: "host of",
               inverse_label: "induced on",
               endpoints: :taxon_to_gall
             } = RelationshipTypes.get("host_of")

      assert %{inverse_label: "alternate generation of", endpoints: :gall_to_gall} =
               RelationshipTypes.get("alternate_generation_of")

      assert %{inverse_label: "has parasitoid", endpoints: :taxon_to_taxon_in_gall} =
               RelationshipTypes.get("parasitoid_of")

      assert RelationshipTypes.get("eats") == nil
    end

    test "qualifiers fit the types the producer guide gives them, with the contract's values" do
      defs = contract("relationships.schema.json")["$defs"]

      assert RelationshipTypes.qualifiers("symbiont_of") == ["required_for_formation"]
      assert RelationshipTypes.qualifiers("inquiline_of") == ["lethality"]
      assert RelationshipTypes.qualifiers("cecidophage_in") == ["lethality"]
      assert RelationshipTypes.qualifiers("parasitoid_in") == ["parasitism_mode"]
      assert RelationshipTypes.qualifiers("parasitoid_of") == ["parasitism_mode"]
      assert RelationshipTypes.qualifiers("host_of") == []

      assert RelationshipTypes.qualifier_values("lethality") == defs["lethality"]["enum"]

      assert RelationshipTypes.qualifier_values("parasitism_mode") ==
               defs["parasitism_mode"]["enum"]

      assert RelationshipTypes.qualifier_values("required_for_formation") == ["true"]
    end
  end

  describe "load_vocab/1" do
    test "loads every Trait value in the contract, with its definition" do
      {:ok, _counts} = Catalog.load_vocab(test_actor())

      schema = contract("traits.schema.json")["$defs"]
      traits = Map.delete(schema, "generation")

      for {trait, %{"enum" => values}} <- traits, value <- values do
        assert %TraitValue{} = Catalog.get_trait_value(trait, value),
               "#{trait}: #{value} is missing"
      end

      expected = traits |> Enum.map(fn {_trait, %{"enum" => values}} -> length(values) end)
      assert Repo.aggregate(TraitValue, :count) == Enum.sum(expected)

      assert %TraitValue{definition: "The Gall forms and grows in spring."} =
               Catalog.get_trait_value("season", "Spring")
    end

    test "loads every generation value in the contract into a generation group" do
      {:ok, _counts} = Catalog.load_vocab(test_actor())

      for value <- contract("traits.schema.json")["$defs"]["generation"]["enum"] do
        assert %GenerationValue{group: %GenerationGroup{}} = Catalog.get_generation_value(value),
               "generation #{value} is missing"
      end
    end

    test "starts the provisional generation groups, the aphid values included, with no taxa mapped" do
      {:ok, _counts} = Catalog.load_vocab(test_actor())

      groups =
        Catalog.list_generation_groups()
        |> Map.new(fn group -> {group.name, Enum.map(group.values, & &1.value)} end)

      assert groups == %{
               "heterogony" => ["agamic", "sexual"],
               "seasonal" => ["spring", "summer", "autumn"],
               "rust_stages" => ["aecial", "telial"],
               "aphid_life_cycle" => [
                 "fundatrix",
                 "apterae",
                 "exules",
                 "gallicolae",
                 "radicicolae"
               ]
             }

      assert %GenerationValue{name_qualifier: "sexgen"} = Catalog.get_generation_value("sexual")
      assert %GenerationValue{name_qualifier: "agamic"} = Catalog.get_generation_value("agamic")

      assert %GenerationValue{definition: "Phylloxerid generations that induce root galls."} =
               Catalog.get_generation_value("radicicolae")

      assert Repo.aggregate(GenerationGroupTaxon, :count) == 0
    end

    test "loads the term mappings" do
      {:ok, _counts} = Catalog.load_vocab(test_actor())

      assert %TraitTermMapping{maps_to: ["flower"], candidates: []} =
               Repo.get_by(TraitTermMapping,
                 trait: "plant_part",
                 term: "inflorescence, raceme, catkin, ament"
               )

      assert %TraitTermMapping{
               maps_to: [],
               candidates: ["tapered swelling", "abrupt swelling", "stem club"],
               rule: "Choose the candidate" <> _
             } = Repo.get_by(TraitTermMapping, trait: "form", term: "swelling")

      mappings = contract("traits.json")["mappings"]

      assert Repo.aggregate(from(m in TraitTermMapping, where: m.trait != "generation"), :count) ==
               length(mappings)

      # The aphid values' other names (`8567`) map onto them.
      assert %TraitTermMapping{maps_to: ["fundatrix"]} =
               Repo.get_by(TraitTermMapping, trait: "generation", term: "stem mother")
    end

    test "is idempotent: loading again writes nothing" do
      {:ok, first} = Catalog.load_vocab(test_actor())
      assert first.trait_values > 0

      counts =
        for t <- [TraitValue, TraitTermMapping, GenerationGroup, GenerationValue],
            do: Repo.aggregate(t, :count)

      changes = audit_change_count()

      assert {:ok, second} = Catalog.load_vocab(test_actor())

      assert second == %{
               trait_values: 0,
               trait_term_mappings: 0,
               generation_groups: 0,
               generation_values: 0
             }

      assert audit_change_count() == changes

      assert counts ==
               for(
                 t <- [TraitValue, TraitTermMapping, GenerationGroup, GenerationValue],
                 do: Repo.aggregate(t, :count)
               )
    end

    test "updates a definition that changed and is audited" do
      {:ok, _} = Catalog.load_vocab(test_actor())

      Repo.update_all(from(t in TraitValue, where: t.trait == "season" and t.value == "Spring"),
        set: [definition: "stale"]
      )

      assert {:ok, %{trait_values: 1}} = Catalog.load_vocab(test_actor())

      assert Catalog.get_trait_value("season", "Spring").definition ==
               "The Gall forms and grows in spring."

      assert [%{changed_from: %{"definition" => "stale"}}] =
               Repo.all(
                 from c in Carbonite.Change,
                   where: c.table_name == "trait_values" and c.op == :update,
                   order_by: c.id
               )
               |> Enum.drop(1)
    end
  end
end
