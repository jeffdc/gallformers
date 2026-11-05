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
end
