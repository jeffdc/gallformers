defmodule Gallformers.Import.DisputesTest do
  @moduledoc "Disputes as queue items: what each finding carries to the review page."
  use ExUnit.Case, async: true

  alias Gallformers.Import.Disputes

  test "each side's one-sentence position is kept" do
    content = %{"facts" => [%{"id" => "f2", "kind" => "relationship", "type" => "host_of"}]}

    review = %{
      "findings" => [
        %{
          "batch" => "gall.json",
          "id" => "f2",
          "problem" => "unsupported",
          "reason" => "The Host is only 'an unknown oak in Utah'.",
          "summary" => "An unnamed oak is never paired with a scientific name.",
          "response" => %{
            "decision" => "disagree",
            "reason" => "The Source pairs 'oak' with Quercus.",
            "summary" => "Ashmead uses 'oak' for the genus throughout."
          }
        }
      ]
    }

    assert [%{subject: %{"findings" => [finding]}}] = Disputes.items(review, "gall.json", content)
    assert finding["summary"] == "An unnamed oak is never paired with a scientific name."
    assert finding["response"]["summary"] == "Ashmead uses 'oak' for the genus throughout."
  end

  describe "identical disputes (d213 Task 10)" do
    defp host_of(id, host, gall),
      do: %{
        "id" => id,
        "kind" => "relationship",
        "type" => "host_of",
        "subject" => host,
        "object" => gall
      }

    defp finding(id),
      do: %{
        "batch" => "gall.json",
        "id" => id,
        "problem" => "unsupported",
        "reason" => "An unnamed oak.",
        "response" => %{"decision" => "disagree", "reason" => "Oak is Quercus."}
      }

    test "disputes about the same statement share a group" do
      ids = for n <- 1..10, do: "f#{n}"

      content = %{
        "taxa" => [
          %{"ref" => "t5", "name_as_written" => "Quercus", "rank" => "genus"},
          %{"ref" => "t6", "name_as_written" => "Q. alba", "rank" => "species"}
        ],
        "facts" =>
          for({id, n} <- Enum.with_index(ids, 1), do: host_of(id, "t5", "g#{n}")) ++
            [host_of("f11", "t6", "g1")]
      }

      review = %{"findings" => Enum.map(ids ++ ["f11"], &finding/1)}
      items = Disputes.items(review, "gall.json", content)

      groups = Map.new(items, &{&1.statement_ref, &1.subject["group"]})
      assert groups |> Map.take(ids) |> Map.values() |> Enum.uniq() == ["host_of:quercus"]
      assert groups["f11"] == "host_of:q. alba"
    end

    test "a dispute about a Trait term carries the Trait and the term" do
      content = %{
        "format_version" => 4,
        "facts" => [
          %{
            "id" => "f2",
            "kind" => "trait",
            "gall" => "g1",
            "trait" => "detachable",
            "term" => "attached by a small point",
            "category" => %{"value" => "detachable"}
          }
        ]
      }

      assert [%{subject: subject}] =
               Disputes.items(%{"findings" => [finding("f2")]}, "gall.json", content)

      assert subject["trait"] == "detachable"
      assert subject["term"] == "attached by a small point"
      assert subject["group"] == "trait:detachable:attached by a small point"
      assert Disputes.trait?(%{subject: subject}) == true
    end
  end

  describe "what each side chose (c8c3 item 3)" do
    # Nastasi & Davis 2022: the producer's summary dropped the value it chose for "fleshy"
    # (succulent, from the term table); the review must say it from data, not prose.
    defp texture(id, gall, term, value),
      do: %{
        "id" => id,
        "kind" => "trait",
        "gall" => gall,
        "trait" => "texture",
        "term" => term,
        "category" => value && %{"value" => value}
      }

    defp placement(id, reviewer, value, extra \\ %{}),
      do:
        Map.merge(
          %{"id" => id, "reviewer" => reviewer, "category" => value && %{"value" => value}},
          extra
        )

    test "a Trait dispute carries the producer's categories and each checker's" do
      content = %{
        "format_version" => 4,
        "facts" => [
          texture("f422", "g35", "fleshy", "succulent"),
          texture("f423", "g36", "fleshy", "succulent")
        ]
      }

      review = %{
        "findings" => [finding("f422")],
        "placements" => [
          placement("f422", "claude-opus-5-5", "succulent"),
          placement("f422", "claude-sonnet-5-5", nil, %{"reason" => "the inside, not the surface"}),
          placement("f423", "claude-opus-5-5", "succulent")
        ]
      }

      assert [%{statement_ref: "f422", subject: subject}] =
               Disputes.items(review, "gall.json", content)

      assert subject["facts"] == ["f422"]
      assert subject["suggestions"] == ["succulent"]

      assert subject["placements"] == [
               %{"reviewer" => "claude-opus-5-5", "category" => "succulent"},
               %{"reviewer" => "claude-sonnet-5-5", "reason" => "the inside, not the surface"}
             ]
    end

    test "a term naming several values gives every value its Facts hold" do
      content = %{
        "format_version" => 4,
        "facts" => [
          %{texture("f1", "g1", "green or yellowish", "green") | "trait" => "color"},
          %{texture("f2", "g1", "Green or yellowish", "yellow") | "trait" => "color"}
        ]
      }

      review = %{
        "findings" => [finding("f1")],
        "placements" => [placement("f1", "a", "green"), placement("f2", "a", "yellow")]
      }

      assert [%{subject: subject}] = Disputes.items(review, "gall.json", content)
      assert subject["facts"] == ["f1", "f2"]
      assert subject["suggestions"] == ["green", "yellow"]
      assert Enum.map(subject["placements"], & &1["category"]) == ["green", "yellow"]
    end

    test "a dispute about anything else carries none" do
      content = %{"facts" => [%{"id" => "f2", "kind" => "relationship", "type" => "host_of"}]}

      assert [%{subject: subject}] =
               Disputes.items(%{"findings" => [finding("f2")]}, "gall.json", content)

      refute Map.has_key?(subject, "suggestions")
      refute Map.has_key?(subject, "placements")
    end
  end
end
