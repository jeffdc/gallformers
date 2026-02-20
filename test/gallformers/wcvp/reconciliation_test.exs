defmodule Gallformers.Wcvp.ReconciliationTest do
  @moduledoc """
  Integration test for the full WCVP reconciliation pipeline.

  Tests the flow: reader -> matcher -> report generation using fixture CSVs
  that mirror real WCVP structure with known scenarios.
  """
  use ExUnit.Case, async: true

  alias Gallformers.Wcvp.{Matcher, Reader, Reporter, Tdwg}

  @fixtures_dir "test/support/fixtures"
  @names_path Path.join(@fixtures_dir, "wcvp_names_sample.csv")
  @dist_path Path.join(@fixtures_dir, "wcvp_distributions_sample.csv")

  # Simulated gallformers plants (what would come from the DB)
  @gf_plants [
    %{id: 1, name: "Quercus alba", genus: "Quercus", family: "Fagaceae"},
    # Uses a WCVP synonym name — should match via synonym pass
    %{id: 2, name: "Quercus borealis", genus: "Quercus", family: "Fagaceae"},
    # Family mismatch — WCVP says Fagaceae, GF has wrong family
    %{id: 3, name: "Quercus velutina", genus: "Quercus", family: "Betulaceae"},
    # Not in WCVP at all
    %{id: 4, name: "Gallusium imaginarium", genus: "Gallusium", family: "Nothingaceae"},
    # Exact match
    %{id: 5, name: "Rosa canina", genus: "Rosa", family: "Rosaceae"}
  ]

  # Minimal TDWG mapping for test
  @tdwg_mapping [
    %{
      "tdwg_code" => "ALB",
      "tdwg_name" => "Alabama",
      "places" => [%{"code" => "US-AL", "precision" => "exact"}]
    },
    %{
      "tdwg_code" => "ILL",
      "tdwg_name" => "Illinois",
      "places" => [%{"code" => "US-IL", "precision" => "exact"}]
    },
    %{
      "tdwg_code" => "NWY",
      "tdwg_name" => "New York",
      "places" => [%{"code" => "US-NY", "precision" => "exact"}]
    },
    %{
      "tdwg_code" => "PEN",
      "tdwg_name" => "Pennsylvania",
      "places" => [%{"code" => "US-PA", "precision" => "exact"}]
    },
    %{
      "tdwg_code" => "FLA",
      "tdwg_name" => "Florida",
      "places" => [%{"code" => "US-FL", "precision" => "exact"}]
    },
    %{
      "tdwg_code" => "CUB",
      "tdwg_name" => "Cuba",
      "places" => [%{"code" => "CU", "precision" => "country"}]
    }
  ]

  setup do
    accepted_by_id = Reader.build_accepted_name_lookup(@names_path)
    accepted_by_name = Map.new(accepted_by_id, fn {_id, n} -> {n.taxon_name, n} end)
    synonym_index = Reader.build_synonym_index(@names_path)
    dist_index = Reader.build_distribution_index(@dist_path)
    tdwg_lookup = Tdwg.build_lookup(@tdwg_mapping)

    %{
      accepted_by_id: accepted_by_id,
      accepted_by_name: accepted_by_name,
      synonym_index: synonym_index,
      dist_index: dist_index,
      tdwg_lookup: tdwg_lookup
    }
  end

  describe "reader indexes" do
    test "accepted names index contains only accepted entries", %{accepted_by_id: accepted_by_id} do
      assert map_size(accepted_by_id) == 7
      assert Enum.all?(accepted_by_id, fn {_id, n} -> n.taxon_status == "Accepted" end)
    end

    test "synonym index maps synonym names to accepted IDs", %{synonym_index: synonym_index} do
      assert synonym_index["Quercus borealis"] == "101"
    end

    test "distribution index groups TDWG codes by plant_name_id", %{dist_index: dist_index} do
      # Quercus alba (100): ALB, ILL, NWY (introduced ILL excluded)
      assert "ALB" in dist_index["100"]
      assert "NWY" in dist_index["100"]

      # Quercus velutina (103): ALB only (extinct row excluded)
      assert dist_index["103"] == ["ALB"]
    end
  end

  describe "matching pipeline" do
    test "exact match works", %{
      accepted_by_name: accepted_by_name,
      synonym_index: synonym_index,
      accepted_by_id: accepted_by_id
    } do
      assert {:exact, name} =
               Matcher.match_name("Quercus alba", accepted_by_name, synonym_index, accepted_by_id)

      assert name.plant_name_id == "100"
    end

    test "synonym match resolves to accepted name", %{
      accepted_by_name: accepted_by_name,
      synonym_index: synonym_index,
      accepted_by_id: accepted_by_id
    } do
      assert {:synonym, accepted} =
               Matcher.match_name(
                 "Quercus borealis",
                 accepted_by_name,
                 synonym_index,
                 accepted_by_id
               )

      assert accepted.taxon_name == "Quercus rubra"
      assert accepted.plant_name_id == "101"
    end

    test "no match returns closest genus member", %{
      accepted_by_name: accepted_by_name,
      synonym_index: synonym_index,
      accepted_by_id: accepted_by_id
    } do
      assert {:no_match, _closest} =
               Matcher.match_name(
                 "Gallusium imaginarium",
                 accepted_by_name,
                 synonym_index,
                 accepted_by_id
               )
    end
  end

  describe "full reconciliation flow" do
    test "classifies all GF plants correctly", %{
      accepted_by_name: accepted_by_name,
      synonym_index: synonym_index,
      accepted_by_id: accepted_by_id
    } do
      results =
        Enum.map(@gf_plants, fn plant ->
          match = Matcher.match_name(plant.name, accepted_by_name, synonym_index, accepted_by_id)
          {plant.name, elem(match, 0)}
        end)

      result_map = Map.new(results)

      assert result_map["Quercus alba"] == :exact
      assert result_map["Quercus borealis"] == :synonym
      assert result_map["Quercus velutina"] == :exact
      assert result_map["Gallusium imaginarium"] == :no_match
      assert result_map["Rosa canina"] == :exact
    end

    test "taxonomy mismatch detected for Quercus velutina", %{
      accepted_by_name: accepted_by_name,
      synonym_index: synonym_index,
      accepted_by_id: accepted_by_id
    } do
      plant = Enum.find(@gf_plants, &(&1.name == "Quercus velutina"))

      {:exact, wcvp} =
        Matcher.match_name(plant.name, accepted_by_name, synonym_index, accepted_by_id)

      # GF says Betulaceae, WCVP says Fagaceae
      assert plant.family != wcvp.family
      assert wcvp.family == "Fagaceae"
    end
  end

  describe "TDWG distribution conversion" do
    test "converts TDWG codes to place codes", %{dist_index: dist_index, tdwg_lookup: tdwg_lookup} do
      tdwg_codes = Map.get(dist_index, "100", [])
      {places, unknown} = Tdwg.convert_tdwg_codes_with_warnings(tdwg_codes, tdwg_lookup)

      place_codes = Enum.map(places, & &1.code)
      assert "US-AL" in place_codes
      assert "US-NY" in place_codes

      # No unknown codes since our test mapping covers all fixture TDWG codes
      assert unknown == []
    end

    test "reports unknown TDWG codes", %{tdwg_lookup: tdwg_lookup} do
      {_places, unknown} = Tdwg.convert_tdwg_codes_with_warnings(["ALB", "XYZ"], tdwg_lookup)
      assert unknown == ["XYZ"]
    end
  end

  describe "report writing" do
    test "writes and reads back report JSON" do
      dir = Path.join(System.tmp_dir!(), "wcvp_integration_test_#{:rand.uniform(10000)}")

      items = [
        %{gf_name: "Quercus alba", status: "exact_match"},
        %{gf_name: "Rosa canina", status: "exact_match"}
      ]

      path = Reporter.write_report(items, "test-matches", dir)
      assert File.exists?(path)

      decoded = path |> File.read!() |> Jason.decode!()
      assert length(decoded) == 2
      assert hd(decoded)["gf_name"] == "Quercus alba"

      File.rm_rf!(dir)
    end
  end
end
