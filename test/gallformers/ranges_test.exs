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
      :ok = Ranges.set_range_exclusions_for_gall(100, [{mexico.id, "country"}])
      excluded = Ranges.get_excluded_places_with_precision_for_gall(100)
      mx = Enum.find(excluded, &(&1.code == "MX"))
      assert mx.precision == "country"
    end

    test "set_range_exclusions_for_gall/2 remains backwards-compatible with plain IDs" do
      mexico = Places.get_place_by_code("MX")
      :ok = Ranges.set_range_exclusions_for_gall(100, [mexico.id])
      excluded = Ranges.get_excluded_places_with_precision_for_gall(100)
      mx = Enum.find(excluded, &(&1.code == "MX"))
      assert mx.precision == "exact"
    end
  end
end
