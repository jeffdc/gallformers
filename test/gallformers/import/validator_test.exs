defmodule Gallformers.Import.ValidatorTest do
  @moduledoc """
  The package validator (`Gallformers.Import.Validator`), ported from the
  contract validator's tests (`priv/import/tests/`): the schemas
  (`test_schema.py`), the package checks (`test_document_checks.py`) and the
  readiness gate (`test_review_gate.py`). Each case asserts what the Python
  test asserts about `validate.py`'s messages.
  """
  use ExUnit.Case, async: true

  import Gallformers.ImportFixtures

  alias Gallformers.DoclingFixtures
  alias Gallformers.Import.Validator

  defp schema_errors(batch), do: Validator.schema_errors(batch)

  defp errors_mention?(errors, words),
    do: Enum.any?(errors, fn e -> Enum.all?(words, &String.contains?(e, &1)) end)

  # As validate.py's package_problems/report print them: "file: message".
  defp problems(package, level \\ :error, opts \\ []) do
    for p <- Validator.validate(package, opts), p.level == level, do: "#{p.file}: #{p.message}"
  end

  defp paper, do: example("simple-paper")
  defp revision, do: example("revision", "taxonomy.json")

  defp put(map, path, value), do: put_in(map, access(path), value)
  defp delete(map, path), do: map |> pop_in(access(path)) |> elem(1)
  defp append(map, key, value), do: Map.update!(map, key, &(&1 ++ [value]))

  defp access(path),
    do:
      Enum.map(path, fn
        i when is_integer(i) -> Access.at(i)
        k -> k
      end)

  # -- the schemas ---------------------------------------------------------------

  describe "schemas: the examples" do
    for name <- Gallformers.ImportFixtures.example_names(),
        file <- ["taxonomy.json", "gall.json"],
        File.exists?(Path.join([Gallformers.ImportFixtures.examples_dir(), name, file])) do
      test "#{name}/#{file} is valid" do
        assert schema_errors(example(unquote(name), unquote(file))) == []
      end
    end

    for name <- Gallformers.ImportFixtures.example_names() do
      test "the #{name} package passes every check" do
        assert problems(example_package(unquote(name))) == []
      end
    end

    test "the examples' warnings are validate.py's" do
      warnings =
        for name <- example_names(), message <- problems(example_package(name), :warning) do
          "#{name}/#{message}"
        end

      assert warnings == [
               "gallformers-statement/gall.json: Gall g1 is identified by Inducer t1 but has " <>
                 "no confirmed inducer_of Fact from t1"
             ]
    end
  end

  describe "schemas: rejections" do
    test "an unknown Trait value" do
      batch = put(paper(), ["facts", 5, "value", "value"], "beige")
      assert errors_mention?(schema_errors(batch), ["facts/5/value/value"])
    end

    test "a controlled value needs as_written" do
      batch = delete(paper(), ["facts", 5, "value", "as_written"])
      assert errors_mention?(schema_errors(batch), ["as_written"])
    end

    test "an extra property" do
      batch = put(paper(), ["facts", 0, "confidence"], 0.9)
      assert schema_errors(batch) == ["facts/0: property 'confidence' is not allowed"]
    end

    test "errors are the causes only: no echoes from failed if-branches or unevaluated parents" do
      batch = put(paper(), ["source", "identifiers", "url"], "not a url")
      assert [error] = schema_errors(batch)
      assert error =~ "source/identifiers/url"
      assert error =~ "uri"
    end

    test "host_of needs a taxon subject" do
      batch = put(paper(), ["facts", 1, "subject"], "g2")
      assert errors_mention?(schema_errors(batch), ["facts/1/subject"])
    end

    test "whole_item excludes quote" do
      batch = put(paper(), ["facts", 10, "evidence", 1, "quote"], "x")
      assert schema_errors(batch) == ["facts/10/evidence/1: property 'quote' is not allowed"]
    end

    test "an unknown rank" do
      batch = put(paper(), ["taxa", 0, "rank"], "clade")
      assert errors_mention?(schema_errors(batch), ["taxa/0/rank"])
    end

    test "not a Gallformers batch" do
      assert [message] = schema_errors(%{"format" => "something-else"})
      assert message =~ "not a Gallformers import batch"
    end
  end

  describe "schemas: accepted shapes" do
    test "ranks above family are accepted" do
      for rank <- ~w(kingdom phylum class order suborder superfamily) do
        assert schema_errors(put(paper(), ["taxa", 3, "rank"], rank)) == [], rank
      end
    end

    test "an empty taxonomy batch is valid" do
      assert schema_errors(%{revision() | "taxa" => [], "acts" => []}) == []
    end

    test "status_as_written on acts" do
      batch =
        revision()
        |> put(["acts", 7, "status_as_written"], "syn. nov.")
        |> put(["acts", 0, "status_as_written"], "nomen dubium")

      assert schema_errors(batch) == []

      assert errors_mention?(
               schema_errors(put(batch, ["acts", 7, "status_as_written"], "")),
               ["status_as_written"]
             )
    end

    test "name_reading on taxa" do
      batch = put(paper(), ["taxa", 0, "name_reading"], "Andricus quercuscalifornicus")
      assert schema_errors(batch) == []
      batch = put(batch, ["taxa", 0, "name_reading"], "")
      assert errors_mention?(schema_errors(batch), ["name_reading"])
    end

    test "formerly_undescribed on Galls" do
      batch = put(paper(), ["galls", 0, "formerly_undescribed"], true)
      assert schema_errors(batch) == []
      batch = put(batch, ["galls", 0, "formerly_undescribed"], "yes")
      assert errors_mention?(schema_errors(batch), ["formerly_undescribed"])
    end

    test "an only range adjustment" do
      assert schema_errors(put(paper(), ["facts", 8, "adjustment"], "only")) == []

      assert errors_mention?(
               schema_errors(put(paper(), ["facts", 8, "adjustment"], "mostly")),
               ["adjustment"]
             )
    end

    test "no include range adjustment: a place outside every Host's range is an occurrence" do
      assert errors_mention?(
               schema_errors(put(paper(), ["facts", 8, "adjustment"], "include")),
               ["adjustment"]
             )
    end

    test "cites on quote evidence" do
      cites = ["facts", 1, "evidence", 0, "cites"]
      assert schema_errors(put(paper(), cites, %{"as_written" => "Kinsey 1923"})) == []
      assert errors_mention?(schema_errors(put(paper(), cites, %{})), ["cites"])
    end

    test "plant_part in identified_by tells two Galls of one Inducer apart" do
      part = ["galls", 0, "identified_by", "plant_part"]
      ok = %{"value" => "stem", "as_written" => "collar of the stem"}
      assert schema_errors(put(paper(), part, ok)) == []
      bad = %{"value" => "trunk", "as_written" => "trunk"}
      assert errors_mention?(schema_errors(put(paper(), part, bad)), ["plant_part"])
    end

    test "sensu on taxa (a misapplied name)" do
      assert schema_errors(put(revision(), ["taxa", 0, "sensu"], "O. S. non Harris")) == []
      assert errors_mention?(schema_errors(put(revision(), ["taxa", 0, "sensu"], "")), ["sensu"])
    end

    test "a common_name act" do
      act = %{
        "id" => "a99",
        "stance" => "confirm",
        "kind" => "common_name",
        "taxon" => "t3",
        "common_name" => "exemplary oak gall wasp",
        "evidence" => [
          %{
            "item" => "#/texts/120",
            "quote" => "Andricus exemplaris Smith & Jones, sp. nov.",
            "page" => "12"
          }
        ]
      }

      assert schema_errors(append(revision(), "acts", act)) == []

      assert errors_mention?(
               schema_errors(append(revision(), "acts", Map.delete(act, "common_name"))),
               ["common_name"]
             )
    end

    test "the taxonomic_act unmapped slot" do
      unmapped = [
        %{
          "term" => "Syn. C. confluens Harris ?",
          "slot" => "taxonomic_act",
          "evidence" => [
            %{
              "item" => "#/texts/120",
              "quote" => "Andricus exemplaris Smith & Jones, sp. nov.",
              "page" => "12"
            }
          ]
        }
      ]

      assert schema_errors(Map.put(revision(), "unmapped", unmapped)) == []
    end
  end

  describe "schemas: recorded occurrences" do
    defp occurrence_fact(fields \\ %{}) do
      Map.merge(
        %{
          "id" => "f99",
          "stance" => "confirm",
          "kind" => "occurrence",
          "gall" => "g1",
          "place" => %{"value" => "US-CA", "as_written" => "Mt. Diablo, California"},
          "evidence" => [
            %{
              "item" => "#/texts/42",
              "quote" => "common on Q. lobata throughout the hills",
              "page" => "58"
            }
          ]
        },
        fields
      )
    end

    test "with a place only" do
      assert schema_errors(append(paper(), "facts", occurrence_fact())) == []
    end

    test "with when and stage" do
      fact =
        occurrence_fact(%{
          "when_as_written" => "July 1961",
          "stage_as_written" => "mature, adults emerging"
        })

      assert schema_errors(append(paper(), "facts", fact)) == []
    end

    test "needs a place" do
      batch = append(paper(), "facts", Map.delete(occurrence_fact(), "place"))
      assert errors_mention?(schema_errors(batch), ["place"])
    end

    test "the place is a place code" do
      fact =
        occurrence_fact(%{"place" => %{"value" => "Mt. Diablo", "as_written" => "Mt. Diablo"}})

      assert errors_mention?(schema_errors(append(paper(), "facts", fact)), ["place"])
    end

    test "when and stage are not empty" do
      batch = append(paper(), "facts", occurrence_fact(%{"when_as_written" => ""}))
      assert errors_mention?(schema_errors(batch), ["when_as_written"])
      batch = append(paper(), "facts", occurrence_fact(%{"stage_as_written" => ""}))
      assert errors_mention?(schema_errors(batch), ["stage_as_written"])
    end

    test "takes no coordinates" do
      fact = occurrence_fact(%{"coordinates" => "37.88 N, 121.91 W"})

      assert errors_mention?(schema_errors(append(paper(), "facts", fact)), [
               "facts/15",
               "coordinates"
             ])
    end
  end

  # -- the package checks --------------------------------------------------------

  describe "package checks" do
    test "a clean package" do
      assert problems(package()) == []
    end

    test "reports a quote that is not in its item" do
      bad = put(batch(), ["facts", 1, "evidence", 0, "quote"], "Rare on Q. lobata")
      assert errors_mention?(problems(package(gall: bad)), ["quote not found"])
    end

    test "a quote across a line-break hyphen and extra whitespace" do
      evidence = %{"item" => "#/texts/1", "quote" => "are globular  and pale tan"}
      b = update_in(batch(), access(["facts", 0, "evidence"]), &(&1 ++ [evidence]))
      assert problems(package(gall: b)) == []
    end

    test "a quote found in another item names it" do
      quote = "external parasitoid of the gall wasp larva"
      b = put(batch(), ["facts", 1, "evidence", 0, "quote"], quote)
      assert [error] = problems(package(gall: b))
      assert error =~ "facts/1/evidence/0"
      assert error =~ "found in #/texts/3"
    end

    test "a missing item" do
      b = put(batch(), ["facts", 1, "evidence", 0, "item"], "#/texts/99")
      assert errors_mention?(problems(package(gall: b)), ["#/texts/99 does not exist"])
    end

    test "a quote needs an item when there is a document" do
      b = delete(batch(), ["facts", 1, "evidence", 0, "item"])
      assert errors_mention?(problems(package(gall: b)), ["needs an item"])
    end

    test "a whole item needs text" do
      b = put(batch(), ["facts", 3, "evidence", 0, "item"], "#/pictures/0")
      assert errors_mention?(problems(package(gall: b)), ["has no text"])
    end

    test "a document hash mismatch" do
      pkg = Map.put(package(), "document.json", ~s({"changed": true}))
      assert errors_mention?(problems(pkg), ["sha256"])
    end

    test "undeclared references" do
      b =
        batch()
        |> put(["facts", 0, "subject"], "t9")
        |> put(["facts", 1, "object"], "g7")

      errors = problems(package(gall: b))
      assert errors_mention?(errors, ["t9"])
      assert errors_mention?(errors, ["g7"])
    end

    test "duplicate ids" do
      b = put(batch(), ["facts", 1, "id"], "f1")
      assert errors_mention?(problems(package(gall: b)), ["duplicate", "f1"])
    end

    test "a qualifier's Relationship type must be allowed" do
      b = put(batch(), ["facts", 3, "of"], "f1")
      assert errors_mention?(problems(package(gall: b)), ["parasitism_mode", "inducer_of"])
    end

    test "one Inducer per Gall" do
      second = batch()["facts"] |> hd() |> Map.merge(%{"id" => "f9", "subject" => "t3"})
      b = append(batch(), "facts", second)
      assert errors_mention?(problems(package(gall: b)), ["more than one inducer"])
    end

    test "a new Gall needs a Fact" do
      gall = %{
        "ref" => "g2",
        "name_as_written" => "x",
        "new" => true,
        "identified_by" => %{"host" => "t2"}
      }

      b = append(batch(), "galls", gall)
      assert errors_mention?(problems(package(gall: b)), ["g2", "no Facts"])
    end

    test "one description per Gall" do
      b =
        Enum.reduce(~w(f7 f8), batch(), fn id, acc ->
          append(acc, "facts", %{
            "id" => id,
            "stance" => "confirm",
            "kind" => "description",
            "gall" => "g1",
            "evidence" => [%{"item" => "#/texts/1", "whole_item" => true}]
          })
        end)

      assert errors_mention?(problems(package(gall: b)), ["more than one description"])
    end

    test "an unused taxon is a warning" do
      b =
        append(batch(), "taxa", %{
          "ref" => "t5",
          "name_as_written" => "Quercus",
          "rank" => "genus"
        })

      pkg = package(gall: b)
      assert problems(pkg) == []
      assert errors_mention?(problems(pkg, :warning), ["t5"])
    end

    test "a missing document is an error" do
      pkg = Map.delete(package(), "document.json")
      assert errors_mention?(problems(pkg), ["document.json is missing"])
    end

    test "document none is no longer allowed" do
      b = put(batch(), ["source", "document"], %{"none" => "scanned, unreadable"})
      pkg = Map.put(package(), "gall.json", Jason.encode!(b))
      assert errors_mention?(problems(pkg), ["source/document"])
    end

    test "a package with no batch" do
      pkg = %{"document.json" => DoclingFixtures.document_json()}
      assert errors_mention?(problems(pkg), ["no taxonomy.json or gall.json"])
    end

    test "a batch that is not JSON" do
      pkg = Map.put(package(), "gall.json", "{not json")
      assert errors_mention?(problems(pkg), ["gall.json", "not valid JSON"])
    end

    test "problems name their file" do
      b = put(batch(), ["facts", 1, "evidence", 0, "quote"], "Rare on Q. lobata")
      assert [%{file: "gall.json", level: :error}] = Validator.validate(package(gall: b))
    end
  end

  describe "package checks: taxonomy batches" do
    defp above_family(kind, ranks, fields) do
      taxa =
        ranks
        |> Enum.with_index(2)
        |> Enum.map(fn {rank, i} ->
          %{"ref" => "t#{i}", "name_as_written" => "Taxon #{i}", "rank" => rank}
        end)

      act =
        Map.merge(
          %{
            "id" => "a2",
            "stance" => "confirm",
            "kind" => kind,
            "evidence" => [%{"item" => "#/texts/1", "quote" => "Andricus quercuscalifornicus"}]
          },
          fields
        )

      taxonomy_batch()
      |> Map.update!("taxa", &(&1 ++ taxa))
      |> append("acts", act)
    end

    test "synonymy above family is rejected" do
      tb =
        above_family("synonymy", ~w(superfamily superfamily), %{
          "name" => "t3",
          "accepted" => "t2"
        })

      assert errors_mention?(problems(package(gall: nil, taxonomy: tb)), ["above family"])
    end

    test "a split above family is rejected" do
      tb = above_family("split", ~w(order order), %{"taxon" => "t2", "into" => ["t2", "t3"]})
      assert errors_mention?(problems(package(gall: nil, taxonomy: tb)), ["above family"])
    end

    test "a placement above family is fine" do
      tb = above_family("placement", ~w(superfamily family), %{"taxon" => "t3", "parent" => "t2"})
      assert problems(package(gall: nil, taxonomy: tb)) == []
    end

    test "an empty taxonomy batch validates" do
      tb = %{taxonomy_batch() | "taxa" => [], "acts" => []}
      assert problems(package(gall: nil, taxonomy: tb)) == []
    end
  end

  describe "package checks: Inducers and occurrences" do
    defp without_inducer_fact(flags) do
      b = batch()
      facts = Enum.reject(b["facts"], &(&1["id"] == "f1" or &1["of"] == "f1"))

      %{b | "facts" => facts}
      |> update_in(access(["galls", 0]), &Map.merge(&1, flags))
    end

    defp named_inducer(messages) do
      Enum.filter(messages, &(&1 =~ "g1" and &1 =~ "t1" and &1 =~ "inducer_of"))
    end

    test "a new Gall needs its Inducer Fact" do
      assert named_inducer(problems(package(gall: without_inducer_fact(%{"new" => true})))) != []

      pkg = package(gall: without_inducer_fact(%{"formerly_undescribed" => true}))
      assert named_inducer(problems(pkg)) != []
    end

    test "an existing Gall without its Inducer Fact is a warning" do
      pkg = package(gall: without_inducer_fact(%{}))
      assert named_inducer(problems(pkg)) == []
      assert named_inducer(problems(pkg, :warning)) != []
    end

    defp occurrence(gall) do
      %{
        "id" => "f9",
        "stance" => "confirm",
        "kind" => "occurrence",
        "gall" => gall,
        "place" => %{"value" => "US-CA", "as_written" => "throughout the hills"},
        "evidence" => [
          %{"item" => "#/texts/2", "quote" => "Common on Q. lobata throughout the hills"}
        ]
      }
    end

    test "an occurrence is checked" do
      assert problems(package(gall: append(batch(), "facts", occurrence("g1")))) == []
      errors = problems(package(gall: append(batch(), "facts", occurrence("g7"))))
      assert errors_mention?(errors, ["facts/4", "g7"])
    end

    test "an occurrence is a Fact about a new Gall" do
      gall = %{
        "ref" => "g2",
        "name_as_written" => "x",
        "new" => true,
        "identified_by" => %{"host" => "t2"}
      }

      b = batch() |> append("galls", gall) |> append("facts", occurrence("g2"))
      refute errors_mention?(problems(package(gall: b)), ["no Facts"])
    end

    test "the Inducer Fact must name the identified Inducer" do
      b =
        batch()
        |> put(["facts", 0, "subject"], "t3")
        |> put(["galls", 0, "new"], true)

      assert named_inducer(problems(package(gall: b))) != []
    end
  end

  # -- the readiness gate --------------------------------------------------------

  describe "readiness gate" do
    @finding %{
      "batch" => "gall.json",
      "id" => "f2",
      "problem" => "wrong_value",
      "reason" => "the quote says Q. douglasii"
    }

    defp gate(pkg, level \\ :error), do: problems(pkg, level, review: true)

    defp answered(decision, id \\ "f2") do
      Map.merge(@finding, %{
        "id" => id,
        "response" => %{"decision" => decision, "reason" => "checked against #/texts/42"}
      })
    end

    defp change_gall_batch(pkg) do
      gall =
        pkg["gall.json"]
        |> Jason.decode!()
        |> put(["facts", 1, "evidence", 0, "quote"], "Common on Q. lobata")

      Map.put(pkg, "gall.json", Jason.encode!(gall))
    end

    test "phase 4 ignores the review" do
      pkg = with_review(package(), [@finding])
      assert problems(pkg, :error, review: false) == []
    end

    test "a missing review fails the gate" do
      assert errors_mention?(gate(package()), ["no review.json", "phase 5"])
    end

    test "a fresh empty review passes" do
      assert gate(with_review(package())) == []
    end

    test "unanswered findings await phase 6" do
      assert [error] = gate(with_review(package(), [@finding]))
      assert error =~ "phase 6"
      assert error =~ "f2"
      assert error =~ "wrong_value"
    end

    test "the review goes stale when a batch changes" do
      pkg = package() |> with_review() |> change_gall_batch()
      assert errors_mention?(gate(pkg), ["stale", "gall.json"])
    end

    test "the review must cover every batch" do
      pkg = package(taxonomy: taxonomy_batch())
      hashes = batch_hashes(pkg) |> Map.delete("taxonomy.json")
      pkg = with_review(pkg, [], override: %{"reviewed" => hashes})
      assert errors_mention?(gate(pkg), ["stale", "taxonomy.json"])
    end

    test "a malformed review" do
      finding = %{"batch" => "gall.json", "id" => "f2", "problem" => "looks off"}
      assert errors_mention?(gate(with_review(package(), [finding])), ["review.json", "problem"])
    end

    test "a finding must name a real statement" do
      pkg = with_review(package(), [Map.put(@finding, "id", "f99")])
      assert errors_mention?(gate(pkg), ["f99", "not in gall.json"])
    end

    test "agreed findings pass" do
      pkg = with_review(package(), [answered("agree")], responded: true)
      assert gate(pkg) == []
      assert gate(pkg, :warning) == []
    end

    test "an agreed fix may remove the statement" do
      pkg = with_review(package(), [answered("agree", "f99")], responded: true)
      assert gate(pkg) == []
    end

    test "disputed findings pass but go to intake" do
      pkg = with_review(package(), [answered("disagree")], responded: true)
      assert gate(pkg) == []
      assert [warning] = gate(pkg, :warning)
      assert warning =~ "human review"
      assert warning =~ "f2"
      assert warning =~ "checked against #/texts/42"
    end

    test "a disputed statement must still exist" do
      pkg = with_review(package(), [answered("disagree", "f99")], responded: true)
      assert errors_mention?(gate(pkg), ["f99", "not in gall.json"])
    end

    test "every finding needs a response" do
      findings = [answered("agree"), Map.put(@finding, "id", "f1")]
      pkg = with_review(package(), findings, responded: true)
      assert errors_mention?(gate(pkg), ["f1", "no phase 6 response"])
    end

    test "batches changed after phase 6" do
      pkg = package() |> with_review([answered("agree")], responded: true) |> change_gall_batch()
      assert errors_mention?(gate(pkg), ["changed after phase 6", "gall.json"])
    end

    test "responses are well formed" do
      bad = Map.put(@finding, "response", %{"decision" => "maybe", "reason" => "x"})
      pkg = with_review(package(), [bad], responded: true)
      assert errors_mention?(gate(pkg), ["review.json", "decision"])
    end

    test "gate problems are filed under review.json" do
      assert [%{file: "review.json"}] = Validator.validate(package(), review: true)
    end
  end
end
