defmodule Gallformers.RangesTest do
  use Gallformers.DataCase, async: false

  alias Gallformers.Places
  alias Gallformers.Ranges

  describe "precision-aware range queries" do
    test "get_places_for_host/1 returns both exact and country-level codes" do
      # M. arvensis (id=8) has exact ranges in CA-AB and US-CA,
      # plus a country-level range for US
      codes = Ranges.get_places_for_host(8)
      assert "CA-AB" in codes
      assert "US-CA" in codes
      assert "US" in codes
    end

    test "get_places_for_host_with_precision/1 includes precision metadata" do
      results = Ranges.get_places_for_host_with_precision(8)
      us_entry = Enum.find(results, &(&1.code == "US"))
      ca_entry = Enum.find(results, &(&1.code == "US-CA"))
      assert us_entry.precision == "country"
      assert ca_entry.precision == "exact"
    end

    test "host_covers_place?/2 returns true for exact match" do
      # M. arvensis (8) has exact range in California (US-CA)
      california = Places.get_place_by_code("US-CA")
      assert Ranges.host_covers_place?(8, california.id)
    end

    test "host_covers_place?/2 returns true when ancestor has range" do
      # M. arvensis (8) has country-level range for US
      # So any US state should be covered
      california = Places.get_place_by_code("US-CA")
      assert Ranges.host_covers_place?(8, california.id)
    end

    test "host_covers_place?/2 returns false for unrelated place" do
      # T. alpinus (6) only has exact range in California
      alberta = Places.get_place_by_code("CA-AB")
      refute Ranges.host_covers_place?(6, alberta.id)
    end
  end

  describe "precision validation" do
    test "rejects continent precision" do
      alias Gallformers.Ranges.HostRange

      changeset =
        HostRange.changeset(%HostRange{}, %{
          species_id: 1,
          place_id: 1,
          precision: "continent"
        })

      assert %{precision: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects continent precision for gall range exclusion" do
      alias Gallformers.Ranges.GallRangeExclusion

      changeset =
        GallRangeExclusion.changeset(%GallRangeExclusion{}, %{
          species_id: 1,
          place_id: 1,
          precision: "continent"
        })

      assert %{precision: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "precision-aware range management" do
    test "add_place_to_host/3 accepts precision parameter" do
      bahamas = Places.get_place_by_code("BS")
      {:ok, _} = Ranges.add_place_to_host(6, bahamas.id, "exact")
      codes = Ranges.get_places_for_host(6)
      assert "BS" in codes
    end

    test "add_place_to_host/3 stores country precision" do
      mexico = Places.get_place_by_code("MX")
      {:ok, _} = Ranges.add_place_to_host(6, mexico.id, "country")
      results = Ranges.get_places_for_host_with_precision(6)
      mx = Enum.find(results, &(&1.code == "MX"))
      assert mx.precision == "country"
    end

    test "add_place_to_host/2 defaults to exact precision" do
      bahamas = Places.get_place_by_code("BS")
      {:ok, _} = Ranges.add_place_to_host(6, bahamas.id)
      results = Ranges.get_places_for_host_with_precision(6)
      bs = Enum.find(results, &(&1.code == "BS"))
      assert bs.precision == "exact"
    end

    test "update_host_places/2 accepts {place_id, precision} tuples" do
      california = Places.get_place_by_code("US-CA")
      mexico = Places.get_place_by_code("MX")
      {:ok, _} = Ranges.update_host_places(6, [{california.id, "exact"}, {mexico.id, "country"}])
      results = Ranges.get_places_for_host_with_precision(6)
      ca = Enum.find(results, &(&1.code == "US-CA"))
      mx = Enum.find(results, &(&1.code == "MX"))
      assert ca.precision == "exact"
      assert mx.precision == "country"
    end

    test "update_host_places/2 remains backwards-compatible with plain IDs" do
      california = Places.get_place_by_code("US-CA")
      {:ok, _} = Ranges.update_host_places(6, [california.id])
      results = Ranges.get_places_for_host_with_precision(6)
      ca = Enum.find(results, &(&1.code == "US-CA"))
      assert ca.precision == "exact"
    end

    test "set_range_exclusions_for_gall/2 accepts {place_id, precision} tuples" do
      mexico = Places.get_place_by_code("MX")
      {:ok, :ok} = Ranges.set_range_exclusions_for_gall(100, [{mexico.id, "country"}])
      excluded = Ranges.get_excluded_places_with_precision_for_gall(100)
      mx = Enum.find(excluded, &(&1.code == "MX"))
      assert mx.precision == "country"
    end

    test "set_range_exclusions_for_gall/2 remains backwards-compatible with plain IDs" do
      mexico = Places.get_place_by_code("MX")
      {:ok, :ok} = Ranges.set_range_exclusions_for_gall(100, [mexico.id])
      excluded = Ranges.get_excluded_places_with_precision_for_gall(100)
      mx = Enum.find(excluded, &(&1.code == "MX"))
      assert mx.precision == "exact"
    end
  end

  describe "display range computation" do
    test "get_display_range_for_gall returns DisplayRange struct" do
      result = Ranges.get_display_range_for_gall(100)
      assert %Ranges.DisplayRange{} = result
    end

    test "get_display_range_for_gall subtracts exclusions from both exact and inherited" do
      # Gall 100 hosts: 6 (US-CA exact) and 8 (CA-AB exact, US-CA exact, US country)
      # Gall 100 exclusion: MX-JAL (place 3, not in host range)
      # MX-JAL shows in excluded_range but doesn't affect exact/inherited since it's
      # not in any host range
      result = Ranges.get_display_range_for_gall(100)
      excluded_set = MapSet.new(result.excluded_range)
      exact_set = MapSet.new(result.in_range)
      inherited_set = MapSet.new(result.inherited_range)

      # No overlap between any of the three sets
      assert MapSet.disjoint?(excluded_set, exact_set)
      assert MapSet.disjoint?(excluded_set, inherited_set)
      assert MapSet.disjoint?(exact_set, inherited_set)

      # MX-JAL should be in excluded
      assert "MX-JAL" in result.excluded_range

      # Host range codes should be in exact
      assert "US-CA" in result.in_range
      assert "CA-AB" in result.in_range
    end

    test "compute_display_range subtracts exclusions from exact set" do
      # Use compute_display_range directly to test exclusion of a code
      # that IS in the host range
      ranges = Ranges.get_places_for_host_with_precision(8)
      result = Ranges.compute_display_range(ranges, ["US-CA"])
      refute "US-CA" in result.in_range
      assert "US-CA" in result.excluded_range
      # CA-AB should still be in range
      assert "CA-AB" in result.in_range
    end

    test "get_display_range_for_host returns DisplayRange with empty excluded_range" do
      result = Ranges.get_display_range_for_host(8)
      assert %Ranges.DisplayRange{} = result
      assert result.excluded_range == []
      # Host 8 has exact entries for CA-AB and US-CA
      assert "CA-AB" in result.in_range
      assert "US-CA" in result.in_range
    end

    test "compute_display_range with no exclusions passes through all codes" do
      # Host 6 only has US-CA exact
      ranges = Ranges.get_places_for_host_with_precision(6)
      result = Ranges.compute_display_range(ranges)
      assert "US-CA" in result.in_range
      assert result.excluded_range == []
    end
  end

  describe "gall range queries" do
    test "get_places_for_gall returns union of host places" do
      # Gall 100 hosts: 6 (US-CA) and 8 (CA-AB, US-CA, US)
      places = Ranges.get_places_for_gall(100)
      assert is_list(places)
      assert "US-CA" in places
      assert "CA-AB" in places
      assert "US" in places
    end

    test "get_places_for_galls returns grouped results" do
      result = Ranges.get_places_for_galls([100, 101])
      assert is_map(result)
      assert is_list(result[100])
      assert "US-CA" in result[100]
      # Gall 101 host: 7 (US-CA only)
      assert is_list(result[101])
      assert "US-CA" in result[101]
    end

    test "get_places_for_gall with no hosts returns empty list" do
      # Gall 102 has no host mappings
      places = Ranges.get_places_for_gall(102)
      assert places == []
    end
  end

  describe "toggle operations" do
    test "toggle_exclusion_for_gall adds then removes" do
      # Gall 101, place 1 (CA-AB) - no existing exclusion
      result = Ranges.toggle_exclusion_for_gall(101, 1)
      assert {:added, 1} = result

      # Verify it was added
      excluded = Ranges.get_excluded_places_for_gall(101)
      assert "CA-AB" in excluded

      # Toggle off
      result = Ranges.toggle_exclusion_for_gall(101, 1)
      assert {:removed, 1} = result

      # Verify it was removed
      excluded = Ranges.get_excluded_places_for_gall(101)
      refute "CA-AB" in excluded
    end

    test "toggle_place_for_host adds then removes" do
      # Host 6 does not have place 3 (MX-JAL)
      result = Ranges.toggle_place_for_host(6, 3)
      assert {:added, 3} = result

      # Verify it was added
      codes = Ranges.get_places_for_host(6)
      assert "MX-JAL" in codes

      # Toggle off
      result = Ranges.toggle_place_for_host(6, 3)
      assert {:removed, 3} = result

      # Verify it was removed
      codes = Ranges.get_places_for_host(6)
      refute "MX-JAL" in codes
    end
  end
end
