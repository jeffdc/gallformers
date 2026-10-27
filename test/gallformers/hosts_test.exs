defmodule Gallformers.HostsTest do
  @moduledoc """
  Unit tests for the Plants and Ranges contexts (formerly Hosts).
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.{Galls, Plants, Species}

  # Test seeds: plants 1-11 (Q. alba, Q. rubra, Q. velutina, Acer rubrum,
  # Acer saccharum, Thymus alpinus, Thymus serpyllum, Mentha arvensis, Q. robur,
  # Notholithocarpus densiflorus, and the genus placeholder Notholithocarpus spp)

  describe "list_hosts_paginated/2" do
    test "returns host plants ordered by name" do
      hosts = Plants.list_hosts_paginated(20, 0)
      assert length(hosts) == 11
      assert Enum.all?(hosts, &(&1.taxoncode == "plant")) == true

      names = Enum.map(hosts, & &1.name)
      assert names == Enum.sort(names)
    end

    test "returns limited number of hosts" do
      hosts = Plants.list_hosts_paginated(5, 0)
      assert length(hosts) == 5
    end

    test "respects offset parameter" do
      # 11 hosts total
      first_page = Plants.list_hosts_paginated(6, 0)
      second_page = Plants.list_hosts_paginated(6, 6)

      assert length(first_page) == 6
      assert length(second_page) == 5

      first_ids = MapSet.new(Enum.map(first_page, & &1.id))
      second_ids = MapSet.new(Enum.map(second_page, & &1.id))
      assert MapSet.disjoint?(first_ids, second_ids) == true
    end
  end

  describe "count_hosts/0" do
    test "returns count matching seeded hosts" do
      assert Plants.count_hosts() == 11
    end
  end

  describe "get_hosts_for_gall/1" do
    test "returns empty list for non-existent gall" do
      assert Galls.get_hosts_for_gall(999_999_999) == []
    end

    test "returns hosts for a gall with known host relationships" do
      # Gall 100 is linked to hosts 6 (T. alpinus) and 8 (M. arvensis)
      hosts = Galls.get_hosts_for_gall(100)
      assert length(hosts) == 2
      host_ids = Enum.map(hosts, & &1.host_species_id) |> Enum.sort()
      assert host_ids == [6, 8]
    end
  end

  describe "search_hosts/2" do
    test "returns empty list for empty query" do
      assert Plants.search_hosts("") == []
    end

    test "returns empty list for whitespace query" do
      assert Plants.search_hosts("   ") == []
    end

    test "returns matching hosts for valid query" do
      results = Plants.search_hosts("Quercus")
      assert length(results) >= 3
      assert Enum.all?(results, &String.contains?(&1.name, "Quercus")) == true
    end

    test "search is case-insensitive" do
      upper_results = Plants.search_hosts("QUERCUS")
      lower_results = Plants.search_hosts("quercus")

      assert length(upper_results) > 0
      assert length(upper_results) == length(lower_results)
    end

    test "respects limit parameter" do
      results = Plants.search_hosts("a", 3)
      assert length(results) <= 3
    end

    test "results have aliases field" do
      results = Plants.search_hosts("Quercus", 5)
      assert length(results) > 0
      assert Enum.all?(results, &Map.has_key?(&1, :aliases)) == true
      assert Enum.all?(results, &is_list(&1.aliases)) == true
    end

    test "batch-loaded aliases match individually loaded aliases" do
      results = Plants.search_hosts("Quercus", 10)
      assert length(results) >= 3

      for result <- results do
        individual_aliases =
          result.id |> Plants.get_aliases_for_host_full() |> Enum.map(& &1.name)

        batch_aliases = result.aliases

        assert Enum.sort(batch_aliases) == Enum.sort(individual_aliases),
               "Aliases mismatch for host #{result.id}: batch=#{inspect(batch_aliases)}, individual=#{inspect(individual_aliases)}"
      end
    end
  end

  describe "host deletion via Species.delete_species/1" do
    test "deletes the host species" do
      # Species 1 is "Quercus alba" - a host plant
      species = Species.get_species!(1)
      assert species.taxoncode == "plant"

      # Delete via the canonical Species.delete_species path
      assert {:ok, deleted} = Species.delete_species(species)
      assert deleted.id == 1

      # Verify the host species is gone
      assert nil == Species.get_species(1)
    end
  end
end
