defmodule Gallformers.Catalog.VocabTest do
  @moduledoc """
  Catalog vocabularies (`9449` §4, Task 8): Trait values and term mappings
  seeded from the contract (`priv/import/vocab/traits.json`) and added by
  curators (`6611` Task 1), the provisional generation groups, and the fixed
  list of Relationship types.

  Not async: the vocabulary tables are unique on their values, so concurrent
  sandbox transactions loading them wait on each other.
  """
  use Gallformers.DataCase, async: false

  alias Gallformers.Catalog
  alias Gallformers.Catalog.RelationshipTypes
  alias Gallformers.Catalog.Vocab.GenerationGroup
  alias Gallformers.Catalog.Vocab.GenerationGroupTaxon
  alias Gallformers.Catalog.Vocab.GenerationValue
  alias Gallformers.Catalog.Vocab.Loader
  alias Gallformers.Catalog.Vocab.TraitTermMapping
  alias Gallformers.Catalog.Vocab.TraitValue

  @vocab_dir Path.expand("../../../priv/import/vocab", __DIR__)

  defp contract(file), do: @vocab_dir |> Path.join(file) |> File.read!() |> Jason.decode!()

  defp audit_change_count, do: Repo.aggregate(test_audit_changes(), :count)

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

      assert %TraitValue{definition: "Galls are located on the leaf" <> _} =
               Catalog.get_trait_value("plant_part", "leaf")
    end

    test "loads every generation value in the contract into a generation group" do
      {:ok, _counts} = Catalog.load_vocab(test_actor())

      for value <- contract("traits.schema.json")["$defs"]["generation"]["enum"] do
        assert %GenerationValue{group: %GenerationGroup{}} = Catalog.get_generation_value(value),
               "generation #{value} is missing"
      end
    end

    test "starts the provisional generation groups, the aphid values included, leaving their taxa alone" do
      # The catalog migration writes the groups' taxa (`generation_group_taxa.csv`);
      # the loader never does.
      mapped = Repo.aggregate(GenerationGroupTaxon, :count)
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

      assert Repo.aggregate(GenerationGroupTaxon, :count) == mapped
    end

    test "loads the terms, one per row, as seeded placements" do
      {:ok, _counts} = Catalog.load_vocab(test_actor())

      for term <- ~w(inflorescence raceme catkin ament) do
        assert %TraitTermMapping{
                 status: :placed,
                 categories: ["flower"],
                 candidates: [],
                 placed_by: :seed,
                 placed_at: %DateTime{}
               } = Catalog.get_term("plant_part", term)
      end

      assert %TraitTermMapping{status: :placed, categories: ["globular"]} =
               Catalog.get_term("shape", "ovoid")

      assert %TraitTermMapping{
               status: :ambiguous,
               categories: [],
               candidates: ["tapered swelling", "abrupt swelling", "stem club"],
               rule: "The category depends on the gall" <> _
             } = Catalog.get_term("form", "swelling")

      # On the leaf, with no more precise place: `leaf` alone (d213).
      assert %TraitTermMapping{status: :placed, categories: ["leaf"], rule: nil} =
               Catalog.get_term("plant_part", "on the leaf")

      mappings = contract("traits.json")["mappings"]

      assert Repo.aggregate(from(m in TraitTermMapping, where: m.trait != "generation"), :count) ==
               length(mappings)

      # The aphid values' other names (`8567`), one per row, map onto them.
      assert %TraitTermMapping{categories: ["fundatrix"]} =
               Catalog.get_term("generation", "stem mother")

      assert %TraitTermMapping{categories: ["exules"]} =
               Catalog.get_term("generation", "alienicolae")

      assert %TraitTermMapping{categories: ["exules"]} =
               Catalog.get_term("generation", "virginoparae")
    end

    test "a fresh database loads the terms the migrated one holds, in the same order" do
      {:ok, _counts} = Catalog.load_vocab(test_actor())

      fields = [:trait, :term, :normalized_term, :status, :categories, :candidates, :rule]
      terms = fn -> Enum.map(Catalog.list_trait_term_mappings(), &Map.take(&1, fields)) end
      migrated = terms.()

      Repo.delete_all(TraitTermMapping)
      assert {:ok, %{trait_term_mappings: count}} = Catalog.load_vocab(test_actor())
      assert count == length(migrated)
      assert terms.() == migrated
    end

    test "the contract lists one term per row" do
      for mapping <- contract("traits.json")["mappings"] do
        assert mapping["status"] in ~w(placed ambiguous no_fit)
        refute mapping["term"] =~ ", ", "#{mapping["term"]} lists several terms"
      end
    end

    test "is idempotent: loading again writes nothing" do
      # The converted seeds already hold the vocabularies (the catalog
      # migration loads them), so this first load may write nothing either.
      {:ok, _first} = Catalog.load_vocab(test_actor())
      assert Repo.aggregate(TraitValue, :count) > 0

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

    test "never overwrites a definition or term mapping edited in the database" do
      {:ok, _} = Catalog.load_vocab(test_actor())

      Repo.update_all(from(t in TraitValue, where: t.trait == "season" and t.value == "Spring"),
        set: [definition: "Edited by a curator."]
      )

      Repo.update_all(
        from(m in TraitTermMapping, where: m.trait == "form" and m.term == "swelling"),
        set: [rule: "Edited rule."]
      )

      assert {:ok, %{trait_values: 0, trait_term_mappings: 0}} = Catalog.load_vocab(test_actor())

      assert Catalog.get_trait_value("season", "Spring").definition == "Edited by a curator."
      assert Catalog.get_term("form", "swelling").rule == "Edited rule."
    end

    test "never overwrites a term placed in the database" do
      {:ok, _} = Catalog.load_vocab(test_actor())

      Repo.update_all(
        from(m in TraitTermMapping, where: m.trait == "texture" and m.term == "rough"),
        set: [status: :no_fit, categories: [], placed_by: :superadmin]
      )

      assert {:ok, %{trait_term_mappings: 0}} = Catalog.load_vocab(test_actor())

      assert %TraitTermMapping{status: :no_fit, categories: [], placed_by: :superadmin} =
               Catalog.get_term("texture", "rough")
    end

    test "seeds the values and term mappings a file holds that the database lacks" do
      {:ok, _} = Catalog.load_vocab(test_actor())

      contract = contract("traits.json")

      contract =
        contract
        |> update_in(["traits", "shape", "values"], fn values ->
          values ++ [%{"value" => "seeded shape", "definition" => "A shape from the file."}]
        end)
        |> update_in(["traits", "season", "values"], fn values ->
          for v <- values,
              do: if(v["value"] == "Spring", do: %{v | "definition" => "From the file."}, else: v)
        end)
        |> Map.update!("mappings", fn mappings ->
          mappings ++
            [
              %{
                "term" => "Seeded  Term",
                "trait" => "shape",
                "status" => "placed",
                "categories" => ["sphere"]
              },
              # The same term in other words: the database holds it already.
              %{
                "term" => "OVOID",
                "trait" => "shape",
                "status" => "placed",
                "categories" => ["sphere"]
              }
            ]
        end)

      path = Path.join(System.tmp_dir!(), "traits_#{System.unique_integer([:positive])}.json")
      File.write!(path, Jason.encode!(contract))
      on_exit(fn -> File.rm(path) end)

      assert {:ok, %{trait_values: 1, trait_term_mappings: 1}} = Loader.load(test_actor(), path)

      assert %TraitValue{definition: "A shape from the file."} =
               Catalog.get_trait_value("shape", "seeded shape")

      assert %TraitTermMapping{
               term: "Seeded  Term",
               normalized_term: "seeded term",
               status: :placed,
               categories: ["sphere"],
               placed_by: :seed
             } = Catalog.get_term("shape", "seeded term")

      assert Catalog.get_term("shape", "ovoid").categories == ["globular"]

      # The database's definition stays.
      assert Catalog.get_trait_value("season", "Spring").definition ==
               "The Gall forms and grows in spring."
    end
  end

  describe "trait_definitions/0" do
    test "each Trait's values with their definitions, for the Trait value picker (87a1)" do
      {:ok, _} = Catalog.load_vocab(test_actor())
      definitions = Catalog.trait_definitions()

      assert definitions["season"]["Spring"] == "The Gall forms and grows in spring."

      for value <- Catalog.list_trait_values() do
        assert Map.fetch!(definitions[value.trait], value.value) == value.definition
      end
    end
  end

  describe "the leaf values (d213)" do
    test "are the contract's plant parts on the leaf; the petiole is not one" do
      parts = contract("traits.schema.json")["$defs"]["plant_part"]["enum"]

      assert "leaf" in parts

      assert Enum.sort(TraitValue.leaf_values()) ==
               parts |> Enum.filter(&(&1 =~ "leaf")) |> List.delete("leaf") |> Enum.sort()

      refute "petiole" in TraitValue.leaf_values()
    end
  end

  describe "add_trait_value/2" do
    setup do
      {:ok, _} = Catalog.load_vocab(test_actor())
      :ok
    end

    test "adds a value with its definition, audited" do
      changes = audit_change_count()

      assert {:ok, %TraitValue{trait: "shape", value: "lenticular"}} =
               Catalog.add_trait_value(test_actor(), %{
                 trait: "shape",
                 value: "lenticular",
                 definition: "Shaped like a lens: round and flattened, convex on both faces."
               })

      assert %TraitValue{definition: "Shaped like a lens" <> _} =
               Catalog.get_trait_value("shape", "lenticular")

      assert audit_change_count() == changes + 1
    end

    test "refuses a value without a definition" do
      for definition <- [nil, "", "  "] do
        assert {:error, changeset} =
                 Catalog.add_trait_value(test_actor(), %{
                   trait: "shape",
                   value: "lenticular",
                   definition: definition
                 })

        assert %{definition: ["can't be blank"]} = errors_on(changeset)
      end

      refute Catalog.get_trait_value("shape", "lenticular")
    end

    test "refuses an unknown trait, and generation" do
      for trait <- ["size", "generation", nil] do
        assert {:error, changeset} =
                 Catalog.add_trait_value(test_actor(), %{
                   trait: trait,
                   value: "big",
                   definition: "Large."
                 })

        assert %{trait: [_]} = errors_on(changeset)
      end
    end

    test "refuses a value the Trait already has" do
      assert {:error, changeset} =
               Catalog.add_trait_value(test_actor(), %{
                 trait: "season",
                 value: "Spring",
                 definition: "Again."
               })

      assert %{value: ["has already been taken"]} = errors_on(changeset)
    end
  end
end
