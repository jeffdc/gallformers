defmodule GallformersWeb.GallLive.RangeExclusionsTest do
  @moduledoc """
  The Gall page's range exclusions as a Gallformers statement (matter a856,
  Task 7): which places to exclude and which earlier exclusions to withdraw
  for the places a curator marked, and the gall batch that says so.
  """
  use ExUnit.Case, async: true

  alias GallformersWeb.GallLive.RangeExclusions

  defp exclusion(code, leaves), do: %{place_code: code, leaves: leaves}

  describe "plan/2" do
    test "newly marked places are excluded" do
      assert RangeExclusions.plan([], MapSet.new(["US-NV", "US-CA"])) ==
               %{exclude: ["US-CA", "US-NV"], withdraw: []}
    end

    test "an exclusion no longer marked is withdrawn" do
      exclusions = [exclusion("US-CA", ["US-CA"]), exclusion("US-NV", ["US-NV"])]

      assert RangeExclusions.plan(exclusions, MapSet.new(["US-NV"])) ==
               %{exclude: [], withdraw: ["US-CA"]}
    end

    test "nothing changed is an empty plan" do
      exclusions = [exclusion("US-CA", ["US-CA"])]

      assert RangeExclusions.plan(exclusions, MapSet.new(["US-CA"])) ==
               %{exclude: [], withdraw: []}
    end

    test "restoring part of a country's exclusion withdraws it and excludes the rest" do
      exclusions = [exclusion("XX", ["XX-A", "XX-B", "XX-C"])]

      assert RangeExclusions.plan(exclusions, MapSet.new(["XX-A", "XX-C"])) ==
               %{exclude: ["XX-A", "XX-C"], withdraw: ["XX"]}
    end

    test "a place a kept exclusion covers is not excluded again" do
      exclusions = [exclusion("XX", ["XX-A", "XX-B"])]

      assert RangeExclusions.plan(exclusions, MapSet.new(["XX-A", "XX-B", "YY"])) ==
               %{exclude: ["YY"], withdraw: []}
    end
  end
end
