defmodule GallformersWeb.Admin.Review.NamesQuestionsTest do
  @moduledoc """
  The Names step's questions (matter `d213`, Task 18, after the Names
  mockup): three sections (Host plants; Which taxon is it; Where the Source
  and the tree differ), every taxon answer with its identity line and
  whether it already holds the Source's name, at most three candidates,
  what "Create" and "Leave this name out" do, and on a synonym question the
  choice to change the tree.
  """
  use ExUnit.Case, async: true

  alias Gallformers.Import.QueueItem
  alias GallformersWeb.Admin.Review.Questions

  @who "Ashmead 1897"

  @names %{
    taxa: %{
      10 => "Heteroecus dasydactyli",
      11 => "Neuroterus quercicola",
      12 => "Andricus one",
      13 => "Andricus two",
      14 => "Andricus three",
      30 => "Diplolepis gracilis",
      175 => "Quercus stellata",
      176 => "Quercus vacciniifolia"
    },
    galls: %{},
    sources: %{}
  }

  @info %{
    10 => %{
      taxon_id: 10,
      name: "Heteroecus dasydactyli",
      family: "Cynipidae",
      synonyms: [],
      galls: [%{id: 1, name: "Heteroecus dasydactyli (agamic)"}, %{id: 2, name: "H. d. (sexgen)"}],
      hosts: [%{taxon_id: 5, name: "Quercus chrysolepis"}]
    },
    11 => %{
      taxon_id: 11,
      name: "Neuroterus quercicola",
      family: "Cynipidae",
      synonyms: ["Neuroterus pacificus", "Andricus wisliceni", "Andricus dasydactylus"],
      galls: [],
      hosts: [
        %{taxon_id: 6, name: "Quercus lobata"},
        %{taxon_id: 7, name: "Quercus douglasii"},
        %{taxon_id: 8, name: "Quercus dumosa"},
        %{taxon_id: 9, name: "Quercus durata"}
      ]
    },
    30 => %{
      taxon_id: 30,
      name: "Diplolepis gracilis",
      family: nil,
      synonyms: ["Rhodites gracilis"],
      galls: [],
      hosts: []
    }
  }

  # A gall batch: t7 induces g1, t2 is its Host; t8 a genus.
  @content %{
    "taxa" => [
      %{"ref" => "t7", "name_as_written" => "ANDRICUS DASYDACTYLI"},
      %{"ref" => "t2", "name_as_written" => "Q. obtusiloba"},
      %{"ref" => "t8", "name_as_written" => "Andricus"}
    ],
    "galls" => [%{"ref" => "g1", "name_as_written" => "the gall of Andricus dasydactyli"}],
    "facts" => [
      %{
        "id" => "f1",
        "kind" => "relationship",
        "type" => "inducer_of",
        "subject" => "t7",
        "object" => "g1"
      },
      %{
        "id" => "f2",
        "kind" => "relationship",
        "type" => "host_of",
        "subject" => "t2",
        "object" => "g1"
      }
    ]
  }

  defp present(item, context \\ %{}),
    do:
      Questions.present(
        item,
        Map.merge(%{source: @who, names: @names, taxa_info: @info, content: @content}, context)
      )

  defp choice(question, label), do: Enum.find(question.choices, &(&1.label == label))
  defp labels(question), do: Enum.map(question.choices, & &1.label)

  defp called_new(proposal \\ %{"candidate_ids" => [10], "proposed" => 10}),
    do: %QueueItem{
      kind: :ambiguous_match,
      statement_ref: "t7",
      subject: %{"name_as_written" => "ANDRICUS DASYDACTYLI", "rank" => "species"},
      proposal: proposal
    }

  @new %{method: "epithet_in_family", flags: [], detail: %{"new_status" => "new species"}}

  describe "the sections" do
    test "Names has three: Host plants, Which taxon is it, Where the Source and the tree differ" do
      host = %QueueItem{
        kind: :unresolved_host,
        statement_ref: "t2",
        subject: %{"name_as_written" => "Q. obtusiloba", "host" => true},
        proposal: %{}
      }

      assert present(host).section.title == "Host plants"
      assert present(host).section.explanation =~ "Which plant does Ashmead 1897 mean?"

      q = present(called_new(), %{statement: @new})
      assert q.section.id == :which_taxon
      assert q.topic == :called_new
      assert q.section.title == "Which taxon is it"
      assert q.section.explanation =~ "Names Gallformers doesn't hold as Ashmead 1897 writes them"
      assert q.holds_approval == true

      not_held = %QueueItem{
        kind: :unresolved_name,
        statement_ref: "t9",
        subject: %{"name_as_written" => "Syrphidae", "rank" => "family"},
        proposal: %{"candidate_ids" => []}
      }

      assert present(not_held).section.id == :which_taxon
      assert present(not_held).topic == :not_held

      several = %QueueItem{
        kind: :ambiguous_match,
        statement_ref: "t3",
        subject: %{"name_as_written" => "ANDRICUS CHRYSOLEPIDIS", "rank" => "species"},
        proposal: %{"candidate_ids" => [10, 11]}
      }

      assert present(several).section.id == :which_taxon
      assert present(several).topic == :several_species

      act = %QueueItem{
        kind: :taxonomy_disagreement,
        statement_ref: "a2",
        subject: %{"kind" => "name", "taxon" => "t7"},
        proposal: %{}
      }

      q = present(act)
      assert q.section.id == :differ
      assert q.section.title == "Where Ashmead 1897 and the tree differ"
      assert q.topic == :acts
      refute q.holds_approval

      ids = Enum.map(Questions.sections(@who), & &1.id)
      assert Enum.take(ids, 3) == [:hosts, :which_taxon, :differ]
    end
  end

  describe "a taxon answer" do
    test "shows its identity line: family, its Galls and Hosts, a link to its page" do
      q = present(called_new(), %{statement: @new})
      use = choice(q, "Use Heteroecus dasydactyli")

      assert use.identity == %{
               family: "Cynipidae",
               galls: 2,
               hosts: ["Quercus chrysolepis"],
               host_count: 1,
               synonyms: [],
               path: "/admin/taxonomy/10",
               held: true
             }
    end

    test "says whether it already holds the Source's name" do
      q = present(called_new(), %{statement: @new})

      assert choice(q, "Use Heteroecus dasydactyli").holding == %{
               kind: :no,
               text: "Doesn't hold “Andricus dasydactyli”: matched on the species name only"
             }

      q =
        present(
          called_new(%{"candidate_ids" => [11], "proposed" => 11}),
          %{statement: @new}
        )

      assert choice(q, "Use Neuroterus quercicola").holding == %{
               kind: :near,
               text: "Holds “Andricus dasydactylus”: a close spelling of Ashmead 1897's name"
             }

      q =
        present(
          %{
            called_new(%{"candidate_ids" => [11], "proposed" => 11})
            | subject: %{"name_as_written" => "Cynips pacificus"}
          },
          %{statement: @new}
        )

      assert choice(q, "Use Neuroterus quercicola").holding.text ==
               "Holds “Neuroterus pacificus”: the same species name in another genus"

      q =
        present(
          %{
            called_new(%{"candidate_ids" => [11], "proposed" => 11})
            | subject: %{"name_as_written" => "Andricus wisliceni"}
          },
          %{statement: @new}
        )

      assert choice(q, "Use Neuroterus quercicola").holding == %{
               kind: :yes,
               text: "✓ Already holds “Andricus wisliceni” as a synonym"
             }
    end

    test "at most three candidates are answers; the others are listed in the search" do
      item = %QueueItem{
        kind: :ambiguous_match,
        statement_ref: "t3",
        subject: %{"name_as_written" => "ANDRICUS CHRYSOLEPIDIS", "rank" => "species"},
        proposal: %{"candidate_ids" => [10, 11, 12, 13, 14], "proposed" => 13}
      }

      q = present(item)

      assert Enum.filter(labels(q), &String.starts_with?(&1, "It's ")) == [
               "It's Andricus two",
               "It's Heteroecus dasydactyli",
               "It's Neuroterus quercicola"
             ]

      assert q.more == "2 more possible matches: choose “Another taxon” to see them all"
      assert q.others == [%{id: 12, name: "Andricus one"}, %{id: 14, name: "Andricus three"}]
    end
  end

  describe "creating and leaving out" do
    test "create says where the new taxon goes" do
      q = present(called_new(), %{statement: @new})
      create = choice(q, "It really is new: create Andricus dasydactyli")

      # The tree doesn't hold its genus: a search for its parent, or unplaced.
      assert create.decision == nil
      assert create.picker == {:parent, :species}
      assert create.prefill == nil

      assert create.note ==
               "Ashmead 1897 places it nowhere in this Source, so it is added unplaced: " <>
                 "place it under its genus, Andricus, from the taxonomy admin after."

      assert Questions.picked_decision(create, :unplaced) == %{"new" => true}

      assert Questions.picked_decision(create, {:taxon, 50}) ==
               %{"new" => true, "parent_id" => 50}

      content =
        Map.put(@content, "acts", [
          %{"id" => "a1", "kind" => "placement", "taxon" => "t7", "parent" => "t8"}
        ])

      q = present(called_new(), %{statement: @new, content: content})
      placed = choice(q, "It really is new: create Andricus dasydactyli")

      assert placed.note == "It goes under Andricus, where Ashmead 1897 places it."
      assert placed.decision == %{"new" => true}
      assert placed.picker == nil
    end

    test "create offers the genus the tree holds, named by the name's first word" do
      genera = %{"andricus" => %{id: 50, name: "Andricus"}}
      q = present(called_new(), %{statement: @new, held_genera: genera})
      create = choice(q, "It really is new: create Andricus dasydactyli")

      assert create.picker == {:parent, :species}
      assert create.prefill == %{id: 50, name: "Andricus"}

      assert Questions.picked_decision(create, {:taxon, 50}) ==
               %{"new" => true, "parent_id" => 50}
    end

    test "create of a family or higher searches for its place" do
      item = %QueueItem{
        kind: :unresolved_name,
        statement_ref: "t9",
        subject: %{"name_as_written" => "Syrphidae", "rank" => "family"},
        proposal: %{"candidate_ids" => []}
      }

      create = choice(present(item), "It's new: create Syrphidae")

      assert create.picker == {:parent, :family}
      assert create.prefill == nil

      assert create.note ==
               "Ashmead 1897 places it nowhere in this Source, so it is added unplaced: " <>
                 "place it in the tree from the taxonomy admin after."

      # A name with no rank can't be placed by rank: it is created as it is.
      no_rank = put_in(item.subject["rank"], nil)
      assert choice(present(no_rank), "It's new: create Syrphidae").decision == %{"new" => true}
    end

    test "leaving a name out says what it drops, with counts" do
      q = present(called_new(), %{statement: @new})
      leave = choice(q, "Leave this name out")

      assert leave.decision == %{"skip" => true}
      assert leave.hint == "Drops 1 statement: the Inducer of the gall of Andricus dasydactyli."

      q = present(%{called_new() | statement_ref: "t99"}, %{statement: @new})

      assert choice(q, "Leave this name out").hint ==
               "No statement in this Source uses the name, so nothing is dropped."
    end
  end

  describe "a Host" do
    @near %{
      "source" => "wcvp",
      "match" => "edit_distance",
      "name" => "Quercus chrysolepis var. vacciniifolia",
      "authors" => "(Hittell) Engelm.",
      "wcvp_id" => "1",
      "taxon_id" => 176,
      "accepted" => %{"name" => "Quercus vacciniifolia", "authors" => "Kellogg", "wcvp_id" => "2"}
    }

    defp host(proposal),
      do: %QueueItem{
        kind: :unresolved_host,
        statement_ref: "t2",
        subject: %{"name_as_written" => "Q. obtusiloba", "host" => true},
        proposal: proposal
      }

    test "a near spelling says which WCVP name was near, and that it is a synonym" do
      q = present(host(%{"suggestions" => [@near]}))

      assert q.proposal.why ==
               "WCVP's Quercus chrysolepis var. vacciniifolia (Hittell) Engelm., a near spelling " <>
                 "of Ashmead 1897's name, is a synonym of it: check it"

      refute q.proposal.firm
    end

    test "a plant Gallformers holds links to it; leaving it out says what it drops" do
      q = present(host(%{"suggestions" => [@near]}))
      use = choice(q, "Use Quercus vacciniifolia Kellogg")

      assert use.identity.path == "/admin/taxonomy/176"
      assert use.identity.held == true

      leave = choice(q, "Leave this Host out")
      assert leave.decision == %{"skip" => true}

      assert leave.hint ==
               "Drops 1 statement: the Host of the gall of Andricus dasydactyli. The Galls' " <>
                 "other statements go in."
    end
  end

  describe "a name the Source treats as valid that the tree holds as a synonym" do
    setup do
      item = %QueueItem{
        kind: :taxonomy_disagreement,
        statement_ref: "t9",
        subject: %{"name_as_written" => "RHODITES GRACILIS", "rank" => "species"},
        proposal: %{"candidate_ids" => [30], "proposed" => 30}
      }

      statement = %{method: "synonym", flags: ["synonym_held_valid"], detail: %{}}
      %{item: item, q: present(item, %{statement: statement, batch_type: :gall})}
    end

    test "asks in the Source's words, saying no Source is recorded for the synonymy", %{q: q} do
      assert q.section.id == :differ
      assert q.topic == :synonyms
      assert q.holds_approval == true

      assert q.question ==
               "Ashmead 1897 treats “RHODITES GRACILIS” as a valid species. Gallformers holds " <>
                 "it as a synonym of Diplolepis gracilis."

      assert q.scope =~ "No Source is recorded for Gallformers' synonymy"
    end

    test "offers following Gallformers, another taxon, changing the tree, or leaving it out",
         %{q: q} do
      assert labels(q) == [
               "Follow Gallformers: it's Diplolepis gracilis",
               "Another taxon…",
               "Ashmead 1897 is right: change the tree",
               "Leave this name out"
             ]

      follow = choice(q, "Follow Gallformers: it's Diplolepis gracilis")
      assert follow.proposed == true
      assert follow.decision == %{"taxon_id" => 30}
      assert follow.holding.kind == :yes

      change = choice(q, "Ashmead 1897 is right: change the tree")
      assert change.picker == :tree
      assert change.decision == nil

      assert change.hint ==
               "“Rhodites gracilis” stops being a synonym of Diplolepis gracilis, for every " <>
                 "Source. You choose what it becomes."

      assert Questions.picked_decision(change, :split) == %{"split" => true}
      assert Questions.picked_decision(change, {:synonym_of, 40}) == %{"synonym_of" => 40}
    end

    test "in a taxonomy batch it may still be noted only", %{item: item} do
      q = present(item, %{batch_type: :taxonomy})
      refute q.holds_approval
      assert choice(q, "Note the disagreement only").decision == %{}
    end
  end
end
