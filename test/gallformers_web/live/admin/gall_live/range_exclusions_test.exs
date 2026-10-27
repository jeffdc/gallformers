defmodule GallformersWeb.Admin.GallLive.RangeExclusionsTest do
  @moduledoc """
  The Gall page's range exclusions as a Gallformers statement (matter a856,
  Task 7): which places to exclude and which earlier exclusions to withdraw
  for the places a curator marked, and the gall batch that says so.
  """
  use ExUnit.Case, async: true

  alias GallformersWeb.Admin.GallLive.RangeExclusions

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

  describe "batch/4" do
    @names %{"US-CA" => "California", "US-NV" => "Nevada"}

    defp summary(attrs) do
      Map.merge(
        %{
          gall_id: 42,
          name: "Andricus quercuscalifornicus (agamic)",
          generation: "agamic",
          inducers: [%{taxon_id: 1, name: "Andricus quercuscalifornicus", rank: :species}],
          hosts: [%{taxon_id: 2, name: "Quercus lobata", rank: :species}]
        },
        Map.new(attrs)
      )
    end

    defp statement, do: %{text: "  No records there.  ", stated_on: ~D[2026-10-27]}

    test "names the Gall by its Inducer and generation, excludes and withdraws by place" do
      plan = %{exclude: ["US-NV"], withdraw: ["US-CA"]}

      assert {:ok, batch} = RangeExclusions.batch(summary(%{}), plan, statement(), @names)

      assert %{
               "format" => "gallformers-import",
               "format_version" => 3,
               "batch_type" => "gall",
               "mode" => "add",
               "source" => %{"gallformers" => true},
               "taxa" => [
                 %{
                   "ref" => "t1",
                   "name_as_written" => "Andricus quercuscalifornicus",
                   "rank" => "species"
                 }
               ],
               "galls" => [
                 %{
                   "ref" => "g1",
                   "name_as_written" => "Andricus quercuscalifornicus (agamic)",
                   "gallformers_gall_id" => 42,
                   "identified_by" => %{
                     "inducer" => "t1",
                     "generation" => %{"value" => "agamic", "as_written" => "agamic"}
                   }
                 }
               ],
               "facts" => [exclude, withdraw]
             } = batch

      evidence = [
        %{"statement" => %{"text" => "No records there.", "stated_on" => "2026-10-27"}}
      ]

      assert exclude == %{
               "id" => "f1",
               "stance" => "confirm",
               "kind" => "range",
               "gall" => "g1",
               "adjustment" => "exclude",
               "place" => %{"value" => "US-NV", "as_written" => "Nevada"},
               "evidence" => evidence
             }

      assert withdraw == %{
               "id" => "f2",
               "stance" => "deny",
               "kind" => "range",
               "gall" => "g1",
               "adjustment" => "exclude",
               "place" => %{"value" => "US-CA", "as_written" => "California"},
               "evidence" => evidence
             }
    end

    test "an undescribed Gall is named by its Inducer above species and its Host" do
      undescribed =
        summary(
          generation: nil,
          inducers: [%{taxon_id: 1, name: "Andricus", rank: :genus}]
        )

      assert {:ok, batch} =
               RangeExclusions.batch(
                 undescribed,
                 %{exclude: ["US-CA"], withdraw: []},
                 statement(),
                 @names
               )

      assert batch["taxa"] == [
               %{"ref" => "t1", "name_as_written" => "Andricus", "rank" => "genus"},
               %{"ref" => "t2", "name_as_written" => "Quercus lobata", "rank" => "species"}
             ]

      assert [%{"identified_by" => %{"inducer" => "t1", "host" => "t2"} = identified_by}] =
               batch["galls"]

      refute Map.has_key?(identified_by, "generation")
    end

    test "a Gall with no Inducer is named by its Host" do
      no_inducer = summary(generation: nil, inducers: [])

      assert {:ok, %{"galls" => [%{"identified_by" => identified_by}]}} =
               RangeExclusions.batch(
                 no_inducer,
                 %{exclude: ["US-CA"], withdraw: []},
                 statement(),
                 @names
               )

      assert identified_by == %{"host" => "t1"}
    end

    test "a Gall with neither Inducer nor Host cannot be named" do
      assert RangeExclusions.batch(
               summary(inducers: [], hosts: []),
               %{exclude: ["US-CA"], withdraw: []},
               statement(),
               @names
             ) == {:error, :unidentified}
    end
  end
end
