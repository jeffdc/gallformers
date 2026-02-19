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
end
