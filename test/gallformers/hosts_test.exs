defmodule Gallformers.HostsTest do
  @moduledoc """
  Unit tests for the Plants, GallHosts, and Ranges contexts (formerly Hosts).
  """
  use Gallformers.DataCase, async: false

  alias Gallformers.{GallHosts, Ranges, Species}
  alias Gallformers.Plants

  # Test seeds: plants 1-9 (Q. alba, Q. rubra, Q. velutina, Acer rubrum,
  # Acer saccharum, Thymus alpinus, Thymus serpyllum, Mentha arvensis, Q. robur)

  describe "list_hosts/0" do
    test "returns all host plants" do
      hosts = Plants.list_hosts()
      assert length(hosts) == 9
      assert Enum.all?(hosts, &(&1.taxoncode == "plant"))
    end

    test "returns hosts ordered by name" do
      hosts = Plants.list_hosts()
      names = Enum.map(hosts, & &1.name)
      assert names == Enum.sort(names)
    end
  end

  describe "list_hosts_paginated/2" do
    test "returns limited number of hosts" do
      hosts = Plants.list_hosts_paginated(5, 0)
      assert length(hosts) == 5
    end

    test "respects offset parameter" do
      # 9 hosts total
      first_page = Plants.list_hosts_paginated(5, 0)
      second_page = Plants.list_hosts_paginated(5, 5)

      assert length(first_page) == 5
      assert length(second_page) == 4

      first_ids = MapSet.new(Enum.map(first_page, & &1.id))
      second_ids = MapSet.new(Enum.map(second_page, & &1.id))
      assert MapSet.disjoint?(first_ids, second_ids)
    end
  end

  describe "count_hosts/0" do
    test "returns count matching seeded hosts" do
      assert Plants.count_hosts() == 9
    end

    test "count matches length of list_hosts" do
      assert Plants.count_hosts() == length(Plants.list_hosts())
    end
  end

  describe "get_host/1" do
    test "returns nil for non-existent ID" do
      assert nil == Plants.get_host(999_999_999)
    end

    test "returns host for valid ID" do
      host = Plants.get_host(1)
      assert host.id == 1
      assert host.name == "Quercus alba"
      assert host.taxoncode == "plant"
    end
  end

  describe "get_host_by_name/1" do
    test "returns nil for non-existent name" do
      assert nil == Plants.get_host_by_name("Nonexistent host name xyz")
    end

    test "returns host for valid name" do
      host = Plants.get_host_by_name("Quercus rubra")
      assert host.id == 2
    end
  end

  describe "get_hosts_for_gall/1" do
    test "returns empty list for non-existent gall" do
      assert GallHosts.get_hosts_for_gall(999_999_999) == []
    end

    test "returns hosts for a gall with known host relationships" do
      # Gall 100 is linked to hosts 6 (T. alpinus) and 8 (M. arvensis)
      hosts = GallHosts.get_hosts_for_gall(100)
      assert length(hosts) == 2
      host_ids = Enum.map(hosts, & &1.host_species_id) |> Enum.sort()
      assert host_ids == [6, 8]
    end
  end

  describe "get_galls_for_host/1" do
    test "returns empty list for non-existent host" do
      assert GallHosts.get_galls_for_host(999_999_999) == []
    end

    test "returns galls for a host with known gall relationships" do
      # Host 6 (T. alpinus) is linked to gall 100
      galls = GallHosts.get_galls_for_host(6)
      assert length(galls) == 1
      assert hd(galls).id == 100
      assert hd(galls).name == "Andricus quercuscalifornicus"
    end
  end

  describe "get_places_for_host/1" do
    test "returns empty list for non-existent host" do
      assert Ranges.get_places_for_host(999_999_999) == []
    end

    test "returns place codes for host with known range" do
      # Host 8 (M. arvensis) has ranges: US-CA (exact), CA-AB (exact), US (country)
      places = Ranges.get_places_for_host(8)
      assert "US-CA" in places
      assert "CA-AB" in places
    end
  end

  describe "get_places_for_gall/1" do
    test "returns empty list for non-existent gall" do
      assert Ranges.get_places_for_gall(999_999_999) == []
    end

    test "returns place codes from curated gall range" do
      # Gall 100 has gall_range entries for US-CA, CA-AB, US
      places = Ranges.get_places_for_gall(100)
      assert length(places) > 0
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
      assert Enum.all?(results, &String.contains?(&1.name, "Quercus"))
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
      assert Enum.all?(results, &Map.has_key?(&1, :aliases))
      assert Enum.all?(results, &is_list(&1.aliases))
    end

    test "batch-loaded aliases match individually loaded aliases" do
      results = Plants.search_hosts("Quercus", 10)
      assert length(results) >= 3

      for result <- results do
        individual_aliases = Plants.get_aliases_for_host(result.id)
        batch_aliases = result.aliases

        assert Enum.sort(batch_aliases) == Enum.sort(individual_aliases),
               "Aliases mismatch for host #{result.id}: batch=#{inspect(batch_aliases)}, individual=#{inspect(individual_aliases)}"
      end
    end
  end

  describe "get_aliases_for_host/1" do
    test "returns empty list for non-existent host" do
      assert Plants.get_aliases_for_host(999_999_999) == []
    end

    test "returns alias names for host with aliases" do
      # Host 1 (Q. alba) has alias "White Oak"
      aliases = Plants.get_aliases_for_host(1)
      assert aliases == ["White Oak"]
    end

    test "returns empty list for host with no aliases" do
      # Host 4 (Acer rubrum) has no aliases in test seeds
      assert Plants.get_aliases_for_host(4) == []
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

      # Verify host is gone
      assert nil == Plants.get_host(1)

      # Verify species is gone
      assert nil == Species.get_species(1)
    end
  end
end
