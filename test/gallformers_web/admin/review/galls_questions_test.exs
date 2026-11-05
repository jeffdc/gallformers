defmodule GallformersWeb.Admin.Review.GallsQuestionsTest do
  @moduledoc """
  The Galls step's questions (matter `d213`, Task 19, after the Galls
  mockup): two sections (Galls of named species; Undescribed Galls), each
  candidate compared side by side with what the Source says, tagged when it
  is the best match or conflicts, at most three candidates, a candidate the
  Source disagrees with settled statement by statement (kept, left out, or
  for a Host read as another plant), and another generation's Gall.
  """
  use ExUnit.Case, async: true

  alias Gallformers.Import.QueueItem
  alias GallformersWeb.Admin.Review.Questions

  @who "Osten Sacken 1862"

  @names %{
    taxa: %{},
    galls: %{
      501 => "Callirhytis quercusoperator (sexgen)",
      502 => "Callirhytis quercusoperator (agamic)",
      503 => "Gall three",
      504 => "Gall four",
      505 => "Gall five"
    },
    sources: %{}
  }

  @source %{
    hosts: [%{name: "Quercus nigra", written: "Q. nigra", refs: ["f2"]}],
    where: [%{value: "stem", term: "on the twigs", refs: ["f7"]}],
    detachable: [],
    generation: nil,
    season: [],
    form: [],
    text: "A woolly gall on the twigs of the black-jack oak."
  }

  defp gall(id, opts \\ []) do
    Map.merge(
      %{
        hosts: ["Quercus marilandica"],
        where: ["flower"],
        detachable: ["detachable"],
        generation: "sexgen",
        season: ["spring"],
        form: [],
        photos: 3,
        sources: 2,
        quoted_in: nil,
        description: "Woolly masses on the staminate flowers."
      },
      Map.new(opts)
    )
    |> Map.put(:id, id)
  end

  defp fields(host, where, generation \\ "none"),
    do: %{
      "host" => host,
      "where" => where,
      "detachable" => "none",
      "generation" => generation,
      "form" => "none"
    }

  defp comparison(id, fields) do
    conflicts = for {k, "conflict"} <- fields, do: k
    agrees = Enum.count(fields, fn {_k, v} -> v == "agree" end)
    %{"gall_id" => id, "agrees" => agrees, "conflicts" => conflicts, "fields" => fields}
  end

  defp view,
    do: %{
      source: @source,
      galls: %{
        501 => gall(501),
        502 => gall(502, generation: "agamic", where: ["fruit"]),
        503 => gall(503),
        504 => gall(504),
        505 => gall(505)
      },
      generations: ["agamic", "sexgen"]
    }

  defp present(item, context \\ %{}),
    do:
      Questions.present(
        item,
        Map.merge(
          %{
            source: @who,
            names: @names,
            gall_view: view(),
            statement: %{method: "identified_by", flags: [], detail: %{}}
          },
          context
        )
      )

  defp choice(question, label), do: Enum.find(question.choices, &(&1.label == label))
  defp labels(question), do: Enum.map(question.choices, & &1.label)

  defp named(proposal),
    do: %QueueItem{
      kind: :ambiguous_match,
      statement_ref: "g3",
      subject: %{"name_as_written" => "the woolly twig gall of C. q. operator"},
      proposal: proposal
    }

  defp both_conflict,
    do:
      named(%{
        "candidate_ids" => [501, 502],
        "comparisons" => [
          comparison(501, fields("differ", "conflict")),
          comparison(502, fields("differ", "conflict"))
        ]
      })

  describe "the sections" do
    test "Galls of named species and Undescribed Galls" do
      q = present(both_conflict())
      assert q.section.id == :named_galls
      assert q.section.title == "Galls of named species"
      assert q.topic == :gall_generation
      assert q.holds_approval == true

      undescribed = %QueueItem{
        kind: :undescribed_gall,
        statement_ref: "g5",
        subject: %{"name_as_written" => "wart-like excrescences"},
        proposal: %{"candidate_ids" => [503], "best" => 503}
      }

      q = present(undescribed)
      assert q.section.id == :undescribed_galls
      assert q.section.title == "Undescribed Galls"
      assert q.topic == :undescribed

      new = %QueueItem{
        kind: :unresolved_name,
        statement_ref: "g7",
        subject: %{"name_as_written" => "a woolly leaf gall"},
        proposal: %{"candidate_ids" => [], "proposed" => "new"}
      }

      assert present(new).section.id == :undescribed_galls
      assert present(new).topic == :new_galls
    end
  end

  describe "a Gall of a named species" do
    test "asks which Gall, saying the Source names no generation" do
      q = present(both_conflict())

      assert q.question ==
               "Which Gall is Osten Sacken 1862's “the woolly twig gall of C. q. operator”?"

      assert q.scope ==
               "Osten Sacken 1862 doesn't name its generation. Gallformers holds 2 Galls for the " <>
                 "species."
    end

    test "each candidate is compared with what the Source says, field by field" do
      q = present(both_conflict())
      it = choice(q, "It's Callirhytis quercusoperator (sexgen)")

      assert it.comparison.who == @who
      assert it.comparison.gall == "Callirhytis quercusoperator (sexgen)"
      assert it.comparison.path == "/admin/galls/501"

      assert it.comparison.rows == [
               %{
                 label: "Host",
                 source: "Quercus nigra (written “Q. nigra”)",
                 gall: "Quercus marilandica",
                 mark: :differ
               },
               %{
                 label: "Where on the plant",
                 source: "stem (“on the twigs”)",
                 gall: "flower",
                 mark: :conflict
               },
               %{label: "Detachable", source: nil, gall: "detachable", mark: :none},
               %{
                 label: "Generation · season",
                 source: "not named",
                 gall: "sexgen · spring",
                 mark: :none
               }
             ]

      assert it.comparison.description ==
               {"A woolly gall on the twigs of the black-jack oak.",
                "Woolly masses on the staminate flowers."}

      assert it.comparison.meta == "Agrees on 0 of 2 stated fields · 3 photos · 2 Sources"
      assert it.comparison.quoted_in == nil
      assert [%{kind: :conflict, text: "Conflicts: where on the plant"}] = it.tags
    end

    test "a Gall whose description comes from this Source says so" do
      view = put_in(view(), [:galls, 501, :quoted_in], "Osten Sacken 1862")
      q = present(both_conflict(), %{gall_view: view})

      assert choice(q, "It's Callirhytis quercusoperator (sexgen)").comparison.quoted_in ==
               "✓ Gallformers' description comes from Osten Sacken 1862"
    end

    test "the form shows only when both sides state it" do
      item =
        named(%{
          "candidate_ids" => [501],
          "comparisons" => [comparison(501, %{fields("agree", "agree") | "form" => "conflict"})]
        })

      view =
        view()
        |> put_in([:source, :form], [%{value: "woolly", term: "woolly", refs: ["f9"]}])
        |> put_in([:galls, 501, :form], ["bead"])

      rows =
        choice(present(item, %{gall_view: view}), "It's Callirhytis quercusoperator (sexgen)").comparison.rows

      assert %{label: "Form", source: "woolly", gall: "bead", mark: :conflict} = List.last(rows)
    end

    test "when every candidate conflicts, the row says to check, not that none fits" do
      q = present(both_conflict())

      assert q.proposal == nil

      assert q.undecided == %{
               label: "Which Gall?",
               why: "Check: both Galls conflict with what Osten Sacken 1862 says"
             }
    end

    test "a proposed Gall that conflicts is only a suggestion to check" do
      item = %{
        both_conflict()
        | proposal:
            Map.merge(both_conflict().proposal, %{"proposed" => 501, "conflicts" => ["where"]})
      }

      q = present(item)

      refute q.proposal.firm
      assert q.proposal.check == "Check: it conflicts on where on the plant"
    end

    test "a firm match is recommended" do
      item =
        named(%{
          "candidate_ids" => [501],
          "proposed" => 501,
          "comparisons" => [comparison(501, fields("agree", "agree"))]
        })

      q = present(item)
      assert q.proposal.firm == true
      assert q.proposal.why == "the only Gall Gallformers holds for the species"
      assert choice(q, "It's Callirhytis quercusoperator (sexgen)").proposed == true
    end

    test "a candidate the Source disagrees with is settled statement by statement" do
      q = present(both_conflict())
      it = choice(q, "It's Callirhytis quercusoperator (sexgen)")

      assert it.picker == :statements
      assert it.decision == nil
      assert it.base == %{"gall_id" => 501}

      assert it.statements == [
               %{
                 key: "host",
                 label: "Host: “Q. nigra”",
                 refs: ["f2"],
                 keep: "Keep it as Quercus nigra",
                 reading: "Q. nigra",
                 as: nil,
                 other: "He means another plant",
                 note:
                   "Records what Osten Sacken 1862 means by “Q. nigra”, for every use of it " <>
                     "in Osten Sacken 1862.",
                 left: "Osten Sacken 1862's “Q. nigra” is left out.",
                 read:
                   "Osten Sacken 1862's “Q. nigra” is read as %{taxon} throughout Osten Sacken 1862."
               },
               %{
                 key: "where",
                 label: "Where on the plant: “on the twigs”",
                 refs: ["f7"],
                 keep: "Keep it",
                 reading: nil,
                 as: nil,
                 other: nil,
                 note: nil,
                 left: "Osten Sacken 1862's “on the twigs” is left out.",
                 read: nil
               }
             ]

      assert Questions.picked_decision(it, {:statements, %{"host" => :keep, "where" => :keep}}) ==
               %{"gall_id" => 501}

      assert Questions.picked_decision(
               it,
               {:statements, %{"host" => {:reading, 99}, "where" => :leave}}
             ) == %{
               "gall_id" => 501,
               "drop" => ["f7"],
               "host_reading" => %{"name" => "Q. nigra", "taxon_id" => 99}
             }

      assert Questions.picked_decision(it, {:statements, %{"host" => :leave, "where" => :leave}}) ==
               %{"gall_id" => 501, "drop" => ["f2", "f7"]}
    end

    test "a Host above species rank goes on another plant for this Gall only, not read" do
      genus = %{name: "Quercus", written: "Quercus", refs: ["f2"], rank: :genus}
      sections = [%{id: 7, name: "Lobatae", common_name: "Red Oaks"}]

      q =
        present(both_conflict(), %{
          gall_view: %{view() | source: %{@source | hosts: [genus]}},
          host_sections: sections
        })

      it = choice(q, "It's Callirhytis quercusoperator (sexgen)")
      assert it.sections == sections
      host = Enum.find(it.statements, &(&1.key == "host"))

      assert %{
               reading: "Quercus",
               as: "host_taxon_id",
               other: "On another plant",
               note:
                 "Puts this Gall's “Quercus” on the plant you pick, for this Gall only: " <>
                   "Osten Sacken 1862's other “Quercus” statements stay as they are.",
               read:
                 "Osten Sacken 1862's “Quercus” goes in on %{taxon}, for this Gall only. " <>
                   "Osten Sacken 1862's other “Quercus” statements stay as they are."
             } = host

      assert Questions.picked_decision(
               it,
               {:statements, %{"host" => {:reading, 99}, "where" => :leave}}
             ) == %{"gall_id" => 501, "drop" => ["f7"], "host_taxon_id" => 99}
    end

    test "another generation's Gall asks for its generation, the held ones not offered" do
      item =
        named(%{
          "candidate_ids" => [501],
          "comparisons" => [comparison(501, fields("agree", "agree"))]
        })

      create = choice(present(item), "It's another generation's Gall: create it")

      assert create.picker == :generation
      assert create.decision == nil

      assert create.generations == [
               %{value: "agamic", held: false},
               %{value: "sexgen", held: true}
             ]

      assert create.note == nil

      assert Questions.picked_decision(create, {:generation, "agamic"}) ==
               %{"new" => true, "generation" => "agamic"}

      # With every generation held, it is created as it is.
      both = choice(present(both_conflict()), "It's another generation's Gall: create it")
      assert both.decision == %{"new" => true}
      assert both.picker == nil
    end

    test "at most three candidates, ranked; the rest behind a search" do
      ids = [501, 502, 503, 504, 505]

      item =
        named(%{
          "candidate_ids" => ids,
          "comparisons" => for(id <- ids, do: comparison(id, fields("agree", "agree")))
        })

      q = present(item)
      galls = Enum.filter(labels(q), &(&1 =~ ~r/^It's (Callirhytis|Gall)/))
      assert length(galls) == 3
      assert "Choose from 2 more possible Galls…" in labels(q)
      assert choice(q, "Choose from 2 more possible Galls…").picker == :gall
      assert q.others == [%{id: 504, name: "Gall four"}, %{id: 505, name: "Gall five"}]
    end
  end

  describe "an undescribed Gall" do
    test "is never firm: the best match is to confirm" do
      item = %QueueItem{
        kind: :undescribed_gall,
        statement_ref: "g5",
        subject: %{"name_as_written" => "wart-like excrescences"},
        proposal: %{
          "candidate_ids" => [503, 504],
          "best" => 503,
          "comparisons" => [
            comparison(503, fields("agree", "none")),
            comparison(504, fields("none", "none"))
          ]
        }
      }

      q = present(item)

      assert q.question ==
               "Is Osten Sacken 1862's “wart-like excrescences” a Gall Gallformers holds?"

      assert q.scope == "Gallformers holds 2 undescribed Galls that could be it."
      refute q.proposal.firm
      assert q.proposal.check == "Best match: confirm it"
      assert [%{kind: :best, text: "Best match: confirm it"}] = choice(q, "It's Gall three").tags
      assert choice(q, "It's Gall four").tags == []
      assert choice(q, "It's Gall three").decision == %{"gall_id" => 503}
    end
  end
end
