defmodule Gallformers.Ranges.PowoDiffTest do
  @moduledoc """
  `Gallformers.Ranges.Wcvp.compute_powo_diff/3`: a range against WCVP's in
  six buckets (moved here with the old `Gallformers.Plants`, which only
  delegated to it).
  """
  use ExUnit.Case, async: true

  alias Gallformers.Ranges.Wcvp

  describe "compute_powo_diff/3" do
    test "empty range with POWO data returns add_native and add_introduced" do
      range_entries = %{}
      native_codes = MapSet.new(["US-AL", "US-CA"])
      introduced_codes = MapSet.new(["CA-ON"])

      result = Wcvp.compute_powo_diff(range_entries, native_codes, introduced_codes)

      assert Enum.sort(result.add_native) == ["US-AL", "US-CA"]
      assert result.add_introduced == ["CA-ON"]
      assert result.remove == []
      assert result.reclassify_to_introduced == []
      assert result.reclassify_to_native == []
      assert result.agree_count == 0
      assert result.has_changes == true
    end

    test "exact match returns agree_count and no changes" do
      range_entries = %{
        "US-AL" => %{precision: "exact", distribution_type: "native"},
        "CA-ON" => %{precision: "exact", distribution_type: "introduced"}
      }

      native_codes = MapSet.new(["US-AL"])
      introduced_codes = MapSet.new(["CA-ON"])

      result = Wcvp.compute_powo_diff(range_entries, native_codes, introduced_codes)

      assert result.add_native == []
      assert result.add_introduced == []
      assert result.remove == []
      assert result.reclassify_to_introduced == []
      assert result.reclassify_to_native == []
      assert result.agree_count == 2
      assert result.has_changes == false
    end

    test "range has places POWO doesn't lists them in remove" do
      range_entries = %{
        "US-AL" => %{precision: "exact", distribution_type: "native"},
        "US-CA" => %{precision: "exact", distribution_type: "introduced"}
      }

      result = Wcvp.compute_powo_diff(range_entries, MapSet.new(), MapSet.new())

      assert Enum.sort(result.remove) == ["US-AL", "US-CA"]
      assert result.add_native == []
      assert result.add_introduced == []
      assert result.agree_count == 0
      assert result.has_changes == true
    end

    test "range has native but POWO says introduced → reclassify_to_introduced" do
      range_entries = %{"US-AL" => %{precision: "exact", distribution_type: "native"}}

      result = Wcvp.compute_powo_diff(range_entries, MapSet.new(), MapSet.new(["US-AL"]))

      assert result.reclassify_to_introduced == ["US-AL"]
      assert result.reclassify_to_native == []
      assert result.remove == []
      assert result.agree_count == 0
      assert result.has_changes == true
    end

    test "range has introduced but POWO says native → reclassify_to_native" do
      range_entries = %{"US-AL" => %{precision: "exact", distribution_type: "introduced"}}

      result = Wcvp.compute_powo_diff(range_entries, MapSet.new(["US-AL"]), MapSet.new())

      assert result.reclassify_to_native == ["US-AL"]
      assert result.reclassify_to_introduced == []
      assert result.remove == []
      assert result.agree_count == 0
      assert result.has_changes == true
    end

    test "mixed scenario distributes correctly across all buckets" do
      range_entries = %{
        "US-AL" => %{precision: "exact", distribution_type: "native"},
        "US-CA" => %{precision: "exact", distribution_type: "introduced"},
        "US-TX" => %{precision: "exact", distribution_type: "native"},
        "US-FL" => %{precision: "exact", distribution_type: "introduced"},
        "US-NY" => %{precision: "exact", distribution_type: "native"}
      }

      # US-AL: native in both → agree
      # US-CA: we have introduced, POWO says native → reclassify_to_native
      # US-TX: we have native, POWO says introduced → reclassify_to_introduced
      # US-FL: introduced in both → agree
      # US-NY: we have native, POWO doesn't list → remove
      # CA-ON: POWO says native, we don't have → add_native
      # CA-BC: POWO says introduced, we don't have → add_introduced
      native_codes = MapSet.new(["US-AL", "US-CA", "CA-ON"])
      introduced_codes = MapSet.new(["US-TX", "US-FL", "CA-BC"])

      result = Wcvp.compute_powo_diff(range_entries, native_codes, introduced_codes)

      assert result.add_native == ["CA-ON"]
      assert result.add_introduced == ["CA-BC"]
      assert result.remove == ["US-NY"]
      assert result.reclassify_to_introduced == ["US-TX"]
      assert result.reclassify_to_native == ["US-CA"]
      assert result.agree_count == 2
      assert result.has_changes == true

      # No place appears in multiple buckets
      all_changed =
        result.add_native ++
          result.add_introduced ++
          result.remove ++ result.reclassify_to_introduced ++ result.reclassify_to_native

      assert length(all_changed) == length(Enum.uniq(all_changed))
    end

    test "both empty returns no changes" do
      result = Wcvp.compute_powo_diff(%{}, MapSet.new(), MapSet.new())

      assert result.add_native == []
      assert result.add_introduced == []
      assert result.remove == []
      assert result.reclassify_to_introduced == []
      assert result.reclassify_to_native == []
      assert result.agree_count == 0
      assert result.has_changes == false
    end
  end
end
