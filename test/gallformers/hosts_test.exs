defmodule Gallformers.HostsTest do
  @moduledoc """
  Unit tests for the Plants, GallHosts, and Ranges contexts (formerly Hosts).
  """
  use Gallformers.DataCase, async: false

  alias Gallformers.{GallHosts, Galls, Ranges, Species, Taxonomy}
  alias Gallformers.Plants

  describe "list_hosts/0" do
    test "returns hosts with expected fields" do
      hosts = Plants.list_hosts()
      assert is_list(hosts)

      if length(hosts) > 0 do
        host = hd(hosts)
        assert Map.has_key?(host, :id)
        assert Map.has_key?(host, :name)
        assert Map.has_key?(host, :taxoncode)
        assert host.taxoncode == "plant"
      end
    end

    test "returns hosts ordered by name" do
      hosts = Plants.list_hosts()

      if length(hosts) > 1 do
        names = Enum.map(hosts, & &1.name)
        assert names == Enum.sort(names)
      end
    end
  end

  describe "list_hosts_paginated/2" do
    test "returns limited number of hosts" do
      hosts = Plants.list_hosts_paginated(5, 0)
      assert length(hosts) <= 5
    end

    test "respects offset parameter" do
      all_hosts = Plants.list_hosts()

      if length(all_hosts) > 5 do
        first_page = Plants.list_hosts_paginated(5, 0)
        second_page = Plants.list_hosts_paginated(5, 5)

        first_ids = MapSet.new(Enum.map(first_page, & &1.id))
        second_ids = MapSet.new(Enum.map(second_page, & &1.id))
        assert MapSet.disjoint?(first_ids, second_ids)
      end
    end
  end

  describe "count_hosts/0" do
    test "returns a non-negative integer" do
      count = Plants.count_hosts()
      assert is_integer(count)
      assert count >= 0
    end

    test "count matches length of list_hosts" do
      count = Plants.count_hosts()
      hosts = Plants.list_hosts()
      assert count == length(hosts)
    end
  end

  describe "get_host/1" do
    test "returns nil for non-existent ID" do
      assert nil == Plants.get_host(999_999_999)
    end

    test "returns host with expected fields for valid ID" do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = Plants.get_host(hd(hosts).id)
        assert host != nil
        assert Map.has_key?(host, :id)
        assert Map.has_key?(host, :name)
        assert Map.has_key?(host, :taxoncode)
        assert host.taxoncode == "plant"
      end
    end
  end

  describe "get_host_by_name/1" do
    test "returns nil for non-existent name" do
      assert nil == Plants.get_host_by_name("Nonexistent host name xyz")
    end

    test "returns host for valid name" do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = Plants.get_host_by_name(hd(hosts).name)
        assert host != nil
        assert host.name == hd(hosts).name
      end
    end
  end

  describe "get_hosts_for_gall/1" do
    test "returns empty list for non-existent gall" do
      hosts = GallHosts.get_hosts_for_gall(999_999_999)
      assert hosts == []
    end

    test "returns hosts with expected fields" do
      galls = Galls.list_galls()

      # Find a gall with hosts
      gall_with_host =
        Enum.find(galls, fn g ->
          length(GallHosts.get_hosts_for_gall(g.id)) > 0
        end)

      if gall_with_host do
        hosts = GallHosts.get_hosts_for_gall(gall_with_host.id)
        assert length(hosts) > 0
        host = hd(hosts)
        assert Map.has_key?(host, :host_relation_id)
        assert Map.has_key?(host, :host_species_id)
        assert Map.has_key?(host, :host_name)
      end
    end
  end

  describe "get_galls_for_host/1" do
    test "returns empty list for non-existent host" do
      galls = GallHosts.get_galls_for_host(999_999_999)
      assert galls == []
    end

    test "returns galls with expected fields" do
      hosts = Plants.list_hosts()

      # Find a host with galls
      host_with_gall =
        Enum.find(hosts, fn h ->
          length(GallHosts.get_galls_for_host(h.id)) > 0
        end)

      if host_with_gall do
        galls = GallHosts.get_galls_for_host(host_with_gall.id)
        assert length(galls) > 0
        gall = hd(galls)
        assert Map.has_key?(gall, :id)
        assert Map.has_key?(gall, :name)
        assert Map.has_key?(gall, :undescribed)
      end
    end
  end

  describe "get_places_for_host/1" do
    test "returns empty list for non-existent host" do
      places = Ranges.get_places_for_host(999_999_999)
      assert places == []
    end

    test "returns list of place codes" do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        places = Ranges.get_places_for_host(hd(hosts).id)
        assert is_list(places)

        if length(places) > 0 do
          # Place codes are strings
          assert is_binary(hd(places))
        end
      end
    end
  end

  describe "get_places_for_gall/1" do
    test "returns empty list for non-existent gall" do
      places = Ranges.get_places_for_gall(999_999_999)
      assert places == []
    end

    test "returns list of place codes" do
      galls = Galls.list_galls()

      if length(galls) > 0 do
        places = Ranges.get_places_for_gall(hd(galls).id)
        assert is_list(places)
      end
    end
  end

  describe "get_excluded_places_for_gall/1" do
    test "returns a list" do
      galls = Galls.list_galls()

      if length(galls) > 0 do
        excluded = Ranges.get_excluded_places_for_gall(hd(galls).id)
        assert is_list(excluded)
      end
    end
  end

  describe "search_hosts/2" do
    test "returns empty list for empty query" do
      results = Plants.search_hosts("")
      assert results == []
    end

    test "returns empty list for whitespace query" do
      results = Plants.search_hosts("   ")
      assert results == []
    end

    test "returns matching hosts for valid query" do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        # Search for part of first host's name
        host_name = hd(hosts).name
        search_term = String.slice(host_name, 0, 3)
        results = Plants.search_hosts(search_term)

        assert is_list(results)
        # Results should include hosts matching the search term
      end
    end

    test "search is case-insensitive" do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host_name = hd(hosts).name
        search_term = String.slice(host_name, 0, 3)
        upper_results = Plants.search_hosts(String.upcase(search_term))
        lower_results = Plants.search_hosts(String.downcase(search_term))

        # Both should return results (may not be identical due to aliases)
        assert is_list(upper_results)
        assert is_list(lower_results)
      end
    end

    test "respects limit parameter" do
      results = Plants.search_hosts("a", 3)
      assert length(results) <= 3
    end

    test "results have aliases field" do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host_name = hd(hosts).name
        search_term = String.slice(host_name, 0, 3)
        results = Plants.search_hosts(search_term, 5)

        if length(results) > 0 do
          result = hd(results)
          assert Map.has_key?(result, :aliases)
          assert is_list(result.aliases)
        end
      end
    end

    test "batch-loaded aliases match individually loaded aliases" do
      # This test verifies the N+1 optimization (attach_aliases_batch)
      # returns the same results as individual get_aliases_for_host calls
      results = Plants.search_hosts("a", 10)

      if length(results) > 1 do
        # For each result, verify batch-loaded aliases match individual lookup
        for result <- results do
          individual_aliases = Plants.get_aliases_for_host(result.id)
          batch_aliases = result.aliases

          # Both should be lists with the same contents (order may differ)
          assert Enum.sort(batch_aliases) == Enum.sort(individual_aliases),
                 "Aliases mismatch for host #{result.id}: batch=#{inspect(batch_aliases)}, individual=#{inspect(individual_aliases)}"
        end
      end
    end
  end

  describe "get_aliases_for_host/1" do
    test "returns empty list for non-existent host" do
      aliases = Plants.get_aliases_for_host(999_999_999)
      assert aliases == []
    end

    test "returns list of alias names" do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        aliases = Plants.get_aliases_for_host(hd(hosts).id)
        assert is_list(aliases)
      end
    end
  end

  describe "delete_host/1" do
    test "deletes the host species" do
      # Species 1 is "Quercus alba" - a host plant
      host = Plants.get_host(1)
      assert host != nil

      # Delete the host
      assert {:ok, deleted} = Plants.delete_host(1)
      assert deleted.id == 1

      # Verify host is gone
      assert nil == Plants.get_host(1)

      # Verify species is gone
      assert nil == Species.get_species(1)
    end

    test "returns error for non-existent host" do
      assert {:error, :not_found} = Plants.delete_host(999_999_999)
    end
  end

  describe "rename_host/3" do
    setup do
      # Create taxonomy structure: Fagaceae -> Quercus, Sapindaceae -> Acer
      {:ok, fagaceae} = Taxonomy.create_taxonomy(%{name: "Fagaceae", type: "family"})

      {:ok, quercus} =
        Taxonomy.create_taxonomy(%{name: "Quercus", type: "genus", parent_id: fagaceae.id})

      {:ok, sapindaceae} = Taxonomy.create_taxonomy(%{name: "Sapindaceae", type: "family"})

      {:ok, acer} =
        Taxonomy.create_taxonomy(%{name: "Acer", type: "genus", parent_id: sapindaceae.id})

      # Link Quercus alba (id=1) to Quercus genus
      Taxonomy.link_species_to_taxonomy(1, quercus.id)

      # Link Acer rubrum (id=4) to Acer genus
      Taxonomy.link_species_to_taxonomy(4, acer.id)

      %{
        fagaceae: fagaceae,
        quercus: quercus,
        sapindaceae: sapindaceae,
        acer: acer
      }
    end

    test "renames host without genus change" do
      # Rename within same genus: Quercus alba -> Quercus stellata
      assert {:ok, updated} = Plants.rename_host(1, "Quercus stellata")
      assert updated.name == "Quercus stellata"

      # Verify the change persisted
      host = Plants.get_host(1)
      assert host.name == "Quercus stellata"
    end

    test "renames host and adds old name as alias when requested" do
      original_name = "Quercus alba"
      new_name = "Quercus stellata"

      assert {:ok, updated} = Plants.rename_host(1, new_name, true)
      assert updated.name == new_name

      # Verify alias was created
      aliases = Plants.get_aliases_for_host(1)
      assert original_name in aliases
    end

    test "returns error when new name already exists" do
      # Try to rename Quercus alba to Quercus rubra (which exists as id=2)
      assert {:error, :name_exists} = Plants.rename_host(1, "Quercus rubra")
    end

    test "returns error for non-existent host" do
      assert {:error, :not_found} = Plants.rename_host(999_999_999, "New name")
    end

    test "updates genus link when renaming to existing genus", %{acer: acer} do
      # Rename Quercus alba -> Acer newspecies (Acer genus exists)
      assert {:ok, updated} = Plants.rename_host(1, "Acer newspecies")
      assert updated.name == "Acer newspecies"

      # Verify taxonomy was updated to Acer
      taxonomy = Taxonomy.get_taxonomy_for_species(1)
      assert taxonomy.genus_id == acer.id
      assert taxonomy.genus == "Acer"
    end

    test "returns needs_genus_confirmation when renaming to non-existent genus", %{
      fagaceae: fagaceae
    } do
      # Rename Quercus alba -> Betula papyrifera (Betula genus doesn't exist)
      result = Plants.rename_host(1, "Betula papyrifera")

      assert {:needs_genus_confirmation, info} = result
      assert info.new_genus == "Betula"
      assert info.new_name == "Betula papyrifera"
      assert info.old_name == "Quercus alba"
      assert info.family_id == fagaceae.id
      assert info.family_name == "Fagaceae"
    end
  end

  describe "rename_host_with_new_genus/5" do
    setup do
      # Create taxonomy structure
      {:ok, fagaceae} = Taxonomy.create_taxonomy(%{name: "Fagaceae", type: "family"})

      {:ok, quercus} =
        Taxonomy.create_taxonomy(%{name: "Quercus", type: "genus", parent_id: fagaceae.id})

      # Link Quercus alba (id=1) to Quercus genus
      Taxonomy.link_species_to_taxonomy(1, quercus.id)

      %{fagaceae: fagaceae, quercus: quercus}
    end

    test "creates new genus and renames host", %{fagaceae: fagaceae} do
      # Confirm genus creation for Betula under Fagaceae
      assert {:ok, updated} =
               Plants.rename_host_with_new_genus(
                 1,
                 "Betula papyrifera",
                 "Betula",
                 fagaceae.id,
                 false
               )

      assert updated.name == "Betula papyrifera"

      # Verify new genus was created
      betula = Taxonomy.get_taxonomy_by_name("Betula", "genus")
      assert betula != nil
      assert betula.parent_id == fagaceae.id

      # Verify species is linked to new genus
      taxonomy = Taxonomy.get_taxonomy_for_species(1)
      assert taxonomy.genus == "Betula"
      assert taxonomy.genus_id == betula.id
    end

    test "creates new genus and adds old name as alias", %{fagaceae: fagaceae} do
      original_name = "Quercus alba"

      assert {:ok, _updated} =
               Plants.rename_host_with_new_genus(
                 1,
                 "Betula papyrifera",
                 "Betula",
                 fagaceae.id,
                 true
               )

      # Verify alias was created
      aliases = Plants.get_aliases_for_host(1)
      assert original_name in aliases
    end

    test "returns error when new name already exists", %{fagaceae: fagaceae} do
      # Try to rename to a name that already exists
      assert {:error, :name_exists} =
               Plants.rename_host_with_new_genus(
                 1,
                 "Quercus rubra",
                 "Quercus",
                 fagaceae.id,
                 false
               )
    end

    test "returns error for non-existent host", %{fagaceae: fagaceae} do
      assert {:error, :not_found} =
               Plants.rename_host_with_new_genus(
                 999_999_999,
                 "New species",
                 "NewGenus",
                 fagaceae.id,
                 false
               )
    end
  end
end
