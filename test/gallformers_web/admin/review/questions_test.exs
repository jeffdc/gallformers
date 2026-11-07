defmodule GallformersWeb.Admin.Review.QuestionsTest do
  use ExUnit.Case, async: true

  alias Gallformers.Import.QueueItem
  alias GallformersWeb.Admin.Review.Questions

  # A batch-local ref (t24, g1, f5, a2) as a word.
  @ref ~r/\b[tgfa]\d+\b/
  @codes ~w(edit_distance epithet_in_family spelling_variant cynips_name held_valid
            synonym_held_valid identified_by unresolved_host ambiguous_match)

  @names %{
    taxa: %{
      1 => "Disholandricus chrysolepidis",
      2 => "Heteroecus chrysolepidis",
      10 => "Heteroecus dasydactyli",
      30 => "Diplolepis gracilis",
      40 => "Aprostocetus smilax",
      175 => "Quercus stellata",
      176 => "Quercus imbricaria",
      200 => "Andricus chrysolepidicola"
    },
    galls: %{
      501 => "Callirhytis morrisoni (sexgen)",
      502 => "Andricus chrysolepidicola (agamic)",
      503 => "Andricus chrysolepidicola (sexgen)",
      600 => "Pemphigus betae",
      700 => "Quercus lobata spindle gall",
      701 => "Quercus lobata midrib gall"
    },
    sources: %{3 => "Descriptions of new cynipidous galls", 4 => "Cynipidous galls (abstract)"}
  }

  defp present(item, context \\ %{}),
    do: Questions.present(item, Map.merge(%{source: "Ashmead", names: @names}, context))

  defp choice(question, label), do: Enum.find(question.choices, &(&1.label == label))

  defp labels(question), do: Enum.map(question.choices, & &1.label)

  defp assert_plain(question) do
    for text <- [question.question, question.written, question.context] ++ labels(question),
        is_binary(text) do
      refute text =~ @ref, "#{inspect(text)} shows a ref"
      for code <- @codes, do: refute(text =~ code, "#{inspect(text)} shows #{code}")
    end

    assert question.technical =~ to_string(question.ref || "")
  end

  # -- Host names ---------------------------------------------------------------

  defp host(proposal),
    do: %QueueItem{
      kind: :unresolved_host,
      statement_ref: "t24",
      subject: %{"name_as_written" => "Q. obtusiloba", "rank" => "species", "host" => true},
      proposal: proposal,
      reason: "no plant has this name or synonym; suggested (1): ..."
    }

  @stellata %{
    "source" => "wcvp",
    "match" => "synonym",
    "name" => "Quercus obtusiloba",
    "authors" => "Michx.",
    "wcvp_id" => "174159",
    "wcvp_status" => "Synonym",
    "taxon_id" => 175,
    "action" => "add_synonym",
    "synonym" => "Q. obtusiloba",
    "accepted" => %{"name" => "Quercus stellata", "authors" => "Wangenh.", "wcvp_id" => "175243"}
  }

  describe "a Host name with a proposed plant" do
    setup do
      item =
        host(%{"candidate_ids" => [175], "proposed" => 175, "suggestions" => [@stellata]})

      %{q: present(item)}
    end

    test "is in the Host names section, which holds approval", %{q: q} do
      assert q.section.id == :hosts
      assert q.section.title == "Host plants"
      assert q.section.explanation =~ "Which plant does Ashmead mean?"
      assert q.section.explanation =~ "adds Ashmead's spelling as a synonym"
      assert q.holds_approval == true
      assert q.leave =~ "every Gall statement in this Source waits"
    end

    test "asks in the Source's words", %{q: q} do
      assert q.question == "Which plant does Ashmead mean by “Q. obtusiloba”?"
      assert q.written == "Q. obtusiloba"
      assert_plain(q)
    end

    test "proposes the plant, adding the spelling as a synonym", %{q: q} do
      assert q.proposal.label == "Quercus stellata Wangenh."
      assert q.proposal.why == "WCVP lists Quercus obtusiloba Michx. as a synonym of it"
      assert q.proposal.firm == true
      assert q.proposal.decision == %{"taxon_id" => 175, "add_synonym" => true}
      refute q.proposal.pending
    end

    test "offers the plant, a search and leaving it out", %{q: q} do
      assert labels(q) == [
               "Use Quercus stellata Wangenh.",
               "Another plant…",
               "Leave this Host out"
             ]

      use = choice(q, "Use Quercus stellata Wangenh.")
      assert use.hint == "Adds “Q. obtusiloba” to it as a synonym."
      assert use.proposed == true
      refute use.pending

      another = choice(q, "Another plant…")
      assert another.picker == :plant
      assert another.decision == nil
      refute another.pending

      assert Questions.picked_decision(another, {:taxon, 9}) ==
               %{"taxon_id" => 9, "add_synonym" => true}

      assert Questions.picked_decision(another, {:wcvp, "123"}) == %{"wcvp_id" => "123"}

      leave = choice(q, "Leave this Host out")
      assert leave.decision == %{"skip" => true}
      assert leave.hint =~ "The Galls' other statements go in."
      refute leave.pending
    end

    test "keeps the technical details for the tucked-away view", %{q: q} do
      assert q.technical =~ "unresolved_host"
      assert q.technical =~ "t24"
    end
  end

  test "a plant Gallformers doesn't hold says accepting adds it from WCVP" do
    pensilvanicus = %{
      "source" => "wcvp",
      "match" => "synonym",
      "name" => "Rubus villosus var. frondosus",
      "authors" => "Bigelow ex Torr.",
      "wcvp_id" => "2990347",
      "wcvp_status" => "Synonym",
      "taxon_id" => nil,
      "action" => "add_from_wcvp",
      "accepted" => %{
        "name" => "Rubus pensilvanicus",
        "authors" => "Poir.",
        "wcvp_id" => "2985327"
      }
    }

    exact = %{
      "source" => "wcvp",
      "match" => "exact",
      "name" => "Rubus ellipticus",
      "authors" => "Sm.",
      "wcvp_id" => "2979630",
      "wcvp_status" => "Accepted",
      "taxon_id" => nil,
      "action" => "add_from_wcvp"
    }

    for {s, why} <- [
          {pensilvanicus,
           "WCVP lists Rubus villosus var. frondosus Bigelow ex Torr. as a synonym of it"},
          {exact, "the name as WCVP holds it"}
        ] do
      q = present(host(%{"candidate_ids" => [], "suggestions" => [s]}))
      assert q.proposal.firm == false
      assert q.proposal.why == why <> ". Not in Gallformers yet: accepting adds it from WCVP"
    end
  end

  test "a Host covering several Galls says so in its choice" do
    item = host(%{"candidate_ids" => [175], "proposed" => 175, "suggestions" => [@stellata]})
    q = present(item, %{covers: 2})

    assert q.covers == 2
    assert choice(q, "Use Quercus stellata Wangenh.").hint =~ "settles the Host of all 2 Galls"
  end

  describe "a Host with only a weak suggestion" do
    test "a near spelling in the tree is a suggestion to check" do
      near = %{
        "source" => "wcvp",
        "match" => "edit_distance",
        "name" => "Quercus imbricaria",
        "authors" => "Michx.",
        "wcvp_id" => "176",
        "wcvp_status" => "Accepted",
        "taxon_id" => 176,
        "action" => "add_synonym",
        "synonym" => "Quercus imbrecaria"
      }

      q = present(host(%{"candidate_ids" => [176], "suggestions" => [near]}))

      assert q.proposal.label == "Quercus imbricaria Michx."
      refute q.proposal.firm
      assert q.proposal.why =~ "likely misspelling, so check it"
      assert q.proposal.decision == %{"taxon_id" => 176, "add_synonym" => true}
      assert_plain(q)
    end

    test "a plant Gallformers doesn't hold is added from WCVP" do
      near = %{
        "source" => "wcvp",
        "match" => "edit_distance",
        "name" => "Quercus imbricaria",
        "authors" => "Michx.",
        "wcvp_id" => "x1",
        "wcvp_status" => "Accepted",
        "taxon_id" => nil,
        "action" => "add_from_wcvp"
      }

      q = present(host(%{"candidate_ids" => [], "suggestions" => [near]}))

      refute q.proposal.firm
      assert q.proposal.decision == %{"wcvp_id" => "x1"}

      add = choice(q, "Add Quercus imbricaria Michx. from WCVP")
      assert add.decision == %{"wcvp_id" => "x1"}
      refute add.pending
    end

    test "a plant WCVP leaves unplaced is not offered to add" do
      unplaced = %{
        "source" => "wcvp",
        "match" => "synonym",
        "name" => "Rubus villosus var. frondosus",
        "authors" => "Bigelow ex Torr.",
        "wcvp_id" => "x2",
        "wcvp_status" => "Synonym",
        "taxon_id" => nil,
        "accepted" => %{"name" => "Rubus pensilvanicus", "authors" => "Poir.", "wcvp_id" => "x3"}
      }

      q = present(host(%{"candidate_ids" => [], "suggestions" => [unplaced]}))

      assert q.proposal == nil
      assert labels(q) == ["Another plant…", "Leave this Host out"]
    end

    test "with no suggestion there is no proposal" do
      q = present(host(%{"candidate_ids" => []}))

      assert q.proposal == nil
      assert q.undecided.label == "No proposal"
      assert labels(q) == ["Another plant…", "Leave this Host out"]
    end
  end

  # -- a Host named by its common name (d213 Task 6) ------------------------------

  defp common_host(proposal),
    do: %QueueItem{
      kind: :unresolved_host,
      statement_ref: "t7",
      subject: %{"name_as_written" => "the black oak", "host" => true, "common_name" => true},
      proposal: proposal,
      reason: "a common name, so a curator decides which plant"
    }

  defp black_oak(id, name, common, genus_id \\ 900),
    do: %{
      "source" => "tree",
      "match" => "common_name",
      "name" => name,
      "common_name" => common,
      "taxon_id" => id,
      "genus" => %{"taxon_id" => genus_id, "name" => "Quercus"}
    }

  describe "a Host named by its common name" do
    setup do
      velutina = black_oak(177, "Quercus velutina", "Black Oak")
      %{q: present(common_host(%{"candidate_ids" => [177], "suggestions" => [velutina]}))}
    end

    test "asks which plant the Source means by its words", %{q: q} do
      assert q.section.id == :hosts
      assert q.question == "Which plant does Ashmead mean by “the black oak”?"
      assert q.written == "the black oak"
      assert_plain(q)
    end

    test "offers Gallformers' plant of that common name, another plant, the genus or none",
         %{q: q} do
      assert labels(q) == [
               "Use Quercus velutina: Gallformers' “Black Oak”",
               "Another plant…",
               "Only the genus: Quercus",
               "Leave this Host out"
             ]

      use = choice(q, "Use Quercus velutina: Gallformers' “Black Oak”")
      assert use.decision == %{"taxon_id" => 177}
      refute use.hint =~ "synonym"

      assert choice(q, "Only the genus: Quercus").decision == %{"taxon_id" => 900}
    end

    test "suggests the plant only to check, never firmly", %{q: q} do
      assert q.proposal.decision == %{"taxon_id" => 177}
      assert q.proposal.firm == false
      assert q.proposal.why =~ "common name"
    end

    test "another plant takes no synonym", %{q: q} do
      another = choice(q, "Another plant…")
      assert another.picker == :plant
      assert Questions.picked_decision(another, {:taxon, 9}) == %{"taxon_id" => 9}
      assert Questions.picked_decision(another, {:wcvp, "123"}) == %{"wcvp_id" => "123"}
    end
  end

  # The genus a common name points to and its sections, as the resolver
  # stores them (`Gallformers.Import.HostSuggestions.suggest_common_name/1`).
  @quercus %{"taxon_id" => 900, "name" => "Quercus"}
  @sections [
    %{"taxon_id" => 910, "name" => "Lobatae", "common_name" => "Red Oaks"},
    %{"taxon_id" => 911, "name" => "Quercus"}
  ]

  describe "a common-name Host whose genus has sections" do
    test "offers a section first, then its plants, another plant, the genus last" do
      q =
        present(
          common_host(%{
            "candidate_ids" => [177],
            "suggestions" => [black_oak(177, "Quercus velutina", "Black Oak")],
            "genus" => @quercus,
            "sections" => @sections
          })
        )

      assert labels(q) == [
               "A section of Quercus",
               "Use Quercus velutina: Gallformers' “Black Oak”",
               "Another plant…",
               "Only the genus: Quercus",
               "Leave this Host out"
             ]

      # The black oak is still the suggestion to check.
      assert q.proposal.decision == %{"taxon_id" => 177}
      assert_plain(q)
    end

    test "the section is picked from the genus's sections, each with its common name" do
      q =
        present(
          common_host(%{"candidate_ids" => [], "genus" => @quercus, "sections" => @sections})
        )

      section = choice(q, "A section of Quercus")

      assert section.decision == nil
      assert section.picker == :section

      assert section.sections == [
               %{id: 910, name: "Lobatae", common_name: "Red Oaks"},
               %{id: 911, name: "Quercus", common_name: nil}
             ]

      assert section.hint ==
               "Ashmead's Host statements go on the section you pick: an unnamed plant of a " <>
                 "genus is usually placed in one of its sections."

      assert section.effect == "Ashmead's Host statements go on %{taxon}, not a species."
      assert Questions.picked_decision(section, {:taxon, 910}) == %{"taxon_id" => 910}
    end

    test "a bare common name (“an unknown oak”), no plant of its own: the sections, the genus" do
      item = %{
        common_host(%{"candidate_ids" => [], "genus" => @quercus, "sections" => @sections})
        | subject: %{"name_as_written" => "an unknown oak", "host" => true, "common_name" => true}
      }

      q = present(item)

      assert q.question == "Which plant does Ashmead mean by “an unknown oak”?"
      assert q.proposal == nil

      assert labels(q) == [
               "A section of Quercus",
               "Another plant…",
               "Only the genus: Quercus",
               "Leave this Host out"
             ]

      genus = choice(q, "Only the genus: Quercus")
      assert genus.decision == %{"taxon_id" => 900}
      assert genus.hint =~ "only when no section fits"
    end

    test "the genus's own common name (“on oaks”) is not offered or proposed ahead of it" do
      oaks = %{black_oak(900, "Quercus", "Oaks") | "genus" => @quercus}

      q =
        present(
          common_host(%{
            "candidate_ids" => [900],
            "suggestions" => [oaks],
            "genus" => @quercus,
            "sections" => @sections
          })
        )

      assert q.proposal == nil

      assert labels(q) == [
               "A section of Quercus",
               "Another plant…",
               "Only the genus: Quercus",
               "Leave this Host out"
             ]
    end

    test "a genus with no sections: no section choice" do
      q = present(common_host(%{"candidate_ids" => [], "genus" => @quercus}))

      assert labels(q) == ["Another plant…", "Only the genus: Quercus", "Leave this Host out"]
    end
  end

  test "a common-name Host whose suggestions are in different genera picks the genus" do
    q =
      present(
        common_host(%{
          "candidate_ids" => [177, 178],
          "suggestions" => [
            black_oak(177, "Quercus velutina", "Black Oak"),
            black_oak(178, "Nyssa sylvatica", "Black Gum", 901)
          ]
        })
      )

    genus = choice(q, "Only the genus…")
    assert genus.picker == :taxon
    assert Questions.picked_decision(genus, {:taxon, 900}) == %{"taxon_id" => 900}
    assert q.proposal == nil
  end

  test "a common-name Host with no suggestion offers another plant, a genus or none" do
    q = present(common_host(%{"candidate_ids" => []}))

    assert q.proposal == nil

    assert labels(q) == [
             "Another plant…",
             "Only the genus…",
             "Leave this Host out"
           ]
  end

  # -- names called new that Gallformers holds -----------------------------------

  describe "a name the Source calls new that Gallformers holds" do
    setup do
      item = %QueueItem{
        kind: :ambiguous_match,
        statement_ref: "t7",
        subject: %{"name_as_written" => "ANDRICUS DASYDACTYLI", "rank" => "species"},
        proposal: %{"candidate_ids" => [10], "proposed" => 10},
        reason: "the Source presents it as new (sp. nov.), but the tree holds ..."
      }

      statement = %{
        method: "epithet_in_family",
        flags: [],
        detail: %{"new_status" => "new species"}
      }

      %{q: present(item, %{statement: statement})}
    end

    test "is asked in Which taxon is it", %{q: q} do
      assert q.topic == :called_new
      assert q.section.title == "Which taxon is it"
      assert q.section.holds == "Holds approval"
      assert q.holds_approval == true
    end

    test "asks whether it is the held taxon", %{q: q} do
      assert q.question ==
               "Is Ashmead's new species “ANDRICUS DASYDACTYLI” the one Gallformers holds as " <>
                 "Heteroecus dasydactyli?"

      assert_plain(q)
    end

    test "proposes the held taxon", %{q: q} do
      assert q.proposal.label == "Heteroecus dasydactyli"
      assert q.proposal.why == "the same species name, in the same family"
      assert q.proposal.decision == %{"taxon_id" => 10}
      assert q.proposal.firm == true
      refute q.proposal.pending
    end

    test "offers the taxon, a new one, a search and leaving it out", %{q: q} do
      assert labels(q) == [
               "Use Heteroecus dasydactyli",
               "It really is new: create Andricus dasydactyli",
               "Another taxon…",
               "Leave this name out"
             ]

      assert choice(q, "Use Heteroecus dasydactyli").hint ==
               "No new taxon is created; Ashmead's name is kept as the original combination."

      create = choice(q, "It really is new: create Andricus dasydactyli")
      assert create.picker == {:parent, :species}
      assert Questions.picked_decision(create, :unplaced) == %{"new" => true}

      another = choice(q, "Another taxon…")
      assert another.picker == :taxon
      assert Questions.picked_decision(another, {:taxon, 44}) == %{"taxon_id" => 44}

      assert choice(q, "Leave this name out").decision == %{"skip" => true}
    end
  end

  test "another spelling's why says so" do
    item = %QueueItem{
      kind: :ambiguous_match,
      statement_ref: "t8",
      subject: %{"name_as_written" => "BASSETTIA GEMMA", "rank" => "species"},
      proposal: %{"candidate_ids" => [10], "proposed" => 10}
    }

    statement = %{method: "spelling_variant", flags: [], detail: %{"new_status" => "sp. nov."}}
    q = present(item, %{statement: statement})

    assert q.topic == :called_new
    assert q.proposal.why == "another spelling or ending of the same name"
  end

  test "a name Gallformers doesn't hold is offered as new" do
    item = %QueueItem{
      kind: :unresolved_name,
      statement_ref: "t40",
      subject: %{"name_as_written" => "Syrphidae", "rank" => "family"},
      proposal: %{"candidate_ids" => []},
      reason: "no taxon has this name or synonym"
    }

    q = present(item)

    assert q.topic == :not_held

    assert q.question ==
             "Which taxon does Ashmead mean by “Syrphidae”? Gallformers holds none by that name."

    assert q.proposal == nil
    assert choice(q, "It's new: create Syrphidae").picker == {:parent, :family}
    assert choice(q, "It's new: create Syrphidae").hint == "Adds a new family to the tree."
    assert_plain(q)
  end

  # -- names held by several species ---------------------------------------------

  describe "a name held by several species" do
    setup do
      item = %QueueItem{
        kind: :ambiguous_match,
        statement_ref: "t3",
        subject: %{"name_as_written" => "ANDRICUS CHRYSOLEPIDIS", "rank" => "species"},
        proposal: %{"candidate_ids" => [1, 2]},
        reason: "2 taxa have this name"
      }

      %{q: present(item, %{statement: %{method: "synonym", flags: [], detail: %{}}})}
    end

    test "asks which species it is, with no proposal", %{q: q} do
      assert q.topic == :several_species
      assert q.question == "Which species is Ashmead's “ANDRICUS CHRYSOLEPIDIS”?"
      assert q.proposal == nil
      assert q.undecided.label == "No proposal: 2 candidates"
      assert q.undecided.why == "Disholandricus chrysolepidis or Heteroecus chrysolepidis"

      assert q.candidates == [
               %{id: 1, name: "Disholandricus chrysolepidis"},
               %{id: 2, name: "Heteroecus chrysolepidis"}
             ]

      assert_plain(q)
    end

    test "offers each species", %{q: q} do
      it = choice(q, "It's Disholandricus chrysolepidis")
      assert it.decision == %{"taxon_id" => 1}

      assert it.hint ==
               "Records that Ashmead's “Andricus chrysolepidis” means this species, so the name " <>
                 "is no longer ambiguous for this Source."

      assert choice(q, "It's Heteroecus chrysolepidis").decision == %{"taxon_id" => 2}
      assert choice(q, "It really is new: create Andricus chrysolepidis")
      assert choice(q, "Leave this name out")
    end
  end

  test "a name held by several, one by its accepted name, proposes that one" do
    item = %QueueItem{
      kind: :ambiguous_match,
      statement_ref: "t3",
      subject: %{"name_as_written" => "ANDRICUS CHRYSOLEPIDIS", "rank" => "species"},
      proposal: %{"candidate_ids" => [1, 2], "proposed" => 2}
    }

    q = present(item)

    assert q.topic == :several_species
    assert q.proposal.label == "Heteroecus chrysolepidis"
    assert q.proposal.decision == %{"taxon_id" => 2}
  end

  # -- names now treated as synonyms ---------------------------------------------

  describe "a name the Source treats as valid that Gallformers holds as a synonym" do
    setup do
      item = %QueueItem{
        kind: :taxonomy_disagreement,
        statement_ref: "t9",
        subject: %{"name_as_written" => "RHODITES GRACILIS", "rank" => "species"},
        proposal: %{"candidate_ids" => [30], "proposed" => 30},
        reason: "the tree holds Rhodites gracilis as a synonym of Diplolepis gracilis, ..."
      }

      statement = %{method: "synonym", flags: ["synonym_held_valid"], detail: %{}}
      %{item: item, q: present(item, %{statement: statement, batch_type: :gall})}
    end

    test "asks whether to follow Gallformers", %{q: q} do
      assert q.topic == :synonyms
      assert q.section.title == "Where Ashmead and the tree differ"

      assert q.question ==
               "Ashmead treats “RHODITES GRACILIS” as a valid species. Gallformers holds it " <>
                 "as a synonym of Diplolepis gracilis."

      assert q.holds_approval == true
      assert_plain(q)
    end

    test "proposes following Gallformers", %{q: q} do
      assert q.proposal.label == "Diplolepis gracilis"
      assert q.proposal.firm == true
      assert q.proposal.decision == %{"taxon_id" => 30}

      follow = choice(q, "Follow Gallformers: it's Diplolepis gracilis")
      assert follow.decision == %{"taxon_id" => 30}

      assert follow.hint ==
               "Ashmead's statements go on Diplolepis gracilis. Ashmead's name is kept as the " <>
                 "original combination."

      assert choice(q, "Another taxon…").picker == :taxon
      assert choice(q, "Leave this name out").decision == %{"skip" => true}
    end

    test "without a proposal the synonymy is only a suggestion to check", %{item: item} do
      q = present(%{item | proposal: %{"candidate_ids" => [40]}})

      refute q.proposal.firm
      assert q.proposal.label == "Aprostocetus smilax"

      assert choice(q, "Follow Gallformers: it's Aprostocetus smilax").hint ==
               "Ashmead's statements go on Aprostocetus smilax. Only once the synonymy has been " <>
                 "checked."
    end

    test "in a taxonomy batch it holds nothing and may be noted only", %{item: item} do
      q = present(item, %{batch_type: :taxonomy})

      refute q.holds_approval
      assert choice(q, "Note the disagreement only").decision == %{}
    end
  end

  # -- Galls ---------------------------------------------------------------------

  describe "a Gall whose generation the Source doesn't name" do
    setup do
      item = %QueueItem{
        kind: :ambiguous_match,
        statement_ref: "g3",
        subject: %{"name_as_written" => "the gall of ANDRICUS MORRISONI", "new" => false},
        proposal: %{"candidate_ids" => [501], "proposed" => 501},
        reason: "one Gall of this Inducer, of the sexgen generation, ..."
      }

      %{q: present(item, %{statement: %{method: "identified_by", flags: [], detail: %{}}})}
    end

    test "asks which Gall it is", %{q: q} do
      assert q.topic == :gall_generation
      assert q.section.title == "Galls of named species"

      assert q.question ==
               "Which Gall is Ashmead's “the gall of ANDRICUS MORRISONI”?"

      assert_plain(q)
    end

    test "proposes the one Gall Gallformers holds", %{q: q} do
      assert q.proposal.label == "Callirhytis morrisoni (sexgen)"
      assert q.proposal.why == "the only Gall Gallformers holds for the species"
      assert q.proposal.decision == %{"gall_id" => 501}
    end

    test "offers the Gall, another generation's, a search and leaving it out", %{q: q} do
      assert labels(q) == [
               "It's Callirhytis morrisoni (sexgen)",
               "It's another generation's Gall: create it",
               "Another Gall…",
               "Leave this Gall out"
             ]

      create = choice(q, "It's another generation's Gall: create it")
      assert create.decision == %{"new" => true}

      assert create.hint ==
               "A new Gall of this species, of a generation Gallformers doesn't hold a Gall for yet."

      another = choice(q, "Another Gall…")
      assert another.picker == :gall
      assert Questions.picked_decision(another, {:gall, 9}) == %{"gall_id" => 9}
      assert choice(q, "Leave this Gall out").decision == %{"skip" => true}
    end
  end

  test "a Gall with both generations held has no proposal" do
    item = %QueueItem{
      kind: :ambiguous_match,
      statement_ref: "g4",
      subject: %{"name_as_written" => "the gall of CYNIPS CHRYSOLEPIDICOLA"},
      proposal: %{"candidate_ids" => [502, 503]}
    }

    q = present(item)

    assert q.topic == :gall_generation
    assert q.proposal == nil
    assert choice(q, "It's Andricus chrysolepidicola (agamic)").decision == %{"gall_id" => 502}
    assert choice(q, "It's Andricus chrysolepidicola (sexgen)").decision == %{"gall_id" => 503}
  end

  describe "a generation pair" do
    setup do
      item = %QueueItem{
        kind: :ambiguous_match,
        statement_ref: "g1",
        subject: %{"name_as_written" => "the fundatrix gall", "generation" => "fundatrix"},
        proposal: %{
          "candidate_ids" => [600],
          "pair" => %{
            "ref" => "g2",
            "name_as_written" => "the apterae gall",
            "generation" => "apterae"
          }
        },
        reason: "g1 (fundatrix) and g2 (apterae) both match this entry, ..."
      }

      %{q: present(item, %{source: "Floate"})}
    end

    test "asks which of the two is the entry; it covers both Galls", %{q: q} do
      assert q.topic == :generation_pairs
      assert q.covers == 2

      assert q.question ==
               "Which of Floate's Galls is Pemphigus betae: “the fundatrix gall” (fundatrix) or " <>
                 "“the apterae gall” (apterae)? The other becomes a new Gall."

      assert q.proposal == nil
      assert_plain(q)
    end

    test "picking one makes the other new", %{q: q} do
      assert choice(q, "It's “the fundatrix gall” (fundatrix)").decision == %{"gall_id" => 600}
      assert choice(q, "It's “the apterae gall” (apterae)").decision == %{"new" => true}

      assert choice(q, "It's “the apterae gall” (apterae)").hint ==
               "Its statements go on Pemphigus betae; “the fundatrix gall” becomes a new Gall."
    end
  end

  test "an undescribed Gall suggests the entry Gallformers holds, to confirm" do
    item = %QueueItem{
      kind: :undescribed_gall,
      statement_ref: "g5",
      subject: %{"name_as_written" => "a small spindle gall on the midrib"},
      proposal: %{"candidate_ids" => [700, 701], "proposed" => 700}
    }

    q = present(item)

    assert q.topic == :undescribed
    assert q.section.holds_approval == true

    assert q.question ==
             "Is Ashmead's “a small spindle gall on the midrib” a Gall Gallformers holds?"

    # An undescribed match is never firm: a curator confirms it.
    assert q.proposal.label == "Quercus lobata spindle gall"
    refute q.proposal.firm
    assert q.proposal.check == "Best match: confirm it"
    assert q.proposal.decision == %{"gall_id" => 700}
    assert choice(q, "It's Quercus lobata midrib gall").decision == %{"gall_id" => 701}

    assert choice(q, "It's a Gall Gallformers doesn't hold: create it").decision == %{
             "new" => true
           }

    assert_plain(q)
  end

  test "a Gall Gallformers doesn't hold proposes creating it" do
    item = %QueueItem{
      kind: :unresolved_name,
      statement_ref: "g7",
      subject: %{"name_as_written" => "a woolly leaf gall"},
      proposal: %{"candidate_ids" => [], "proposed" => "new"}
    }

    q = present(item)

    assert q.topic == :new_galls
    assert q.proposal.label == "Create it as a new Gall"
    assert q.proposal.decision == %{"new" => true}
    assert choice(q, "Another Gall…").picker == :gall
    assert_plain(q)
  end

  # -- disputes (matter d213, Disputes step) ---------------------------------------

  @dispute_findings [
    %{
      "problem" => "unsupported",
      "reason" => "No gall was seen on Ambrosia.",
      "reviewer" => "model-b",
      "response" => %{"decision" => "disagree", "reason" => "Ashmead corrects only the role."}
    }
  ]

  defp host_dispute(ref, gall, findings \\ @dispute_findings),
    do:
      %QueueItem{
        kind: :dispute,
        statement_ref: ref,
        subject: %{"findings" => findings, "group" => "host_of:ambrosia"},
        proposal: %{},
        reason: "reviewer: ...; producer: ..."
      }
      |> then(&{&1, host_fact(ref, gall)})

  defp host_fact(ref, gall),
    do: %{
      "id" => ref,
      "kind" => "relationship",
      "type" => "host_of",
      "stance" => "confirm",
      "subject" => "t3",
      "object" => gall
    }

  @dispute_written %{
    "t3" => "Ambrosia",
    "g2" => "AULAX AMBROSIÆCOLA",
    "g3" => "the pith galls"
  }

  defp present_dispute({item, fact}),
    do: present(item, %{fact: fact, written: @dispute_written})

  test "a disputed statement asks whether it goes in, both sides in a sentence" do
    q = present_dispute(host_dispute("f12", "g2"))

    assert q.section.id == :disputes

    assert q.question ==
             "Should this statement go in: AULAX AMBROSIÆCOLA has Ambrosia as its Host?"

    # No Recommended on a dispute: the readers disagree.
    assert q.proposal == nil
    assert q.undecided.label == "Keep or drop?"
    assert q.undecided.why == "The producer and a checker disagree"

    assert q.sides == %{
             producer: ["Ashmead corrects only the role."],
             checker: ["No gall was seen on Ambrosia."]
           }

    # The full arguments, for the disclosure.
    assert q.voices.checker == ["No gall was seen on Ambrosia."]
    assert q.voices.producer == ["Ashmead corrects only the role."]

    assert labels(q) == ["Keep it", "Keep it, as another plant", "Drop it"]
    assert choice(q, "Keep it").decision == %{"keep" => true}

    assert choice(q, "Keep it").hint ==
             "It goes in as the producer wrote it, credited to Ashmead."

    # A Host dispute may be kept with the Host read as another plant.
    other = choice(q, "Keep it, as another plant")
    assert other.decision == nil
    assert other.picker == {:reading, "Ambrosia"}

    assert other.hint ==
             "Ashmead means another plant by “Ambrosia”: it goes in on the plant you pick."

    assert other.effect ==
             "It goes in on %{taxon}. Ashmead's “Ambrosia” is read as %{taxon} throughout this " <>
               "Source, and the tree records it as a synonym of %{taxon} in Ashmead's sense."

    assert Questions.picked_decision(other, {:taxon, 44}) == %{
             "keep" => true,
             "host_reading" => %{"name" => "Ambrosia", "taxon_id" => 44}
           }

    assert choice(q, "Drop it").decision == %{"skip" => true}

    assert choice(q, "Drop it").hint ==
             "It is left out; Ashmead's words stay in the Source's text."

    assert q.holds_approval == true
    assert_plain(q)
  end

  test "a Host dispute whose Host is a genus with sections lists them first in its search" do
    {item, fact} = host_dispute("f12", "g2")

    sections = [
      %{id: 910, name: "Lobatae", common_name: "Red Oaks"},
      %{id: 911, name: "Quercus", common_name: nil}
    ]

    q = present(item, %{fact: fact, written: @dispute_written, host_sections: sections})

    other = choice(q, "Keep it, as another plant")
    assert other.picker == {:reading, "Ambrosia"}
    assert other.sections == sections

    grouped = Questions.group([q, q])
    assert choice(grouped, "Keep it for these 2 Galls, as another plant").sections == sections

    # Without sections, none.
    assert choice(present_dispute(host_dispute("f12", "g2")), "Keep it, as another plant").sections ==
             []
  end

  test "a Host dispute whose Host is a genus is kept on the plant picked, for its Galls only" do
    {item, fact} = host_dispute("f12", "g2")
    q = present(item, %{fact: fact, written: @dispute_written, host_rank: :genus})

    other = choice(q, "Keep it, as another plant")
    assert other.picker == {:reading, "Ambrosia"}

    assert other.hint ==
             "Ashmead names only “Ambrosia” here: it goes in on the plant you pick."

    assert other.effect ==
             "It goes in on %{taxon}, for this Gall only. Ashmead's other “Ambrosia” " <>
               "statements stay as they are."

    # The plant chosen for this statement: no reading of the genus's name.
    assert Questions.picked_decision(other, {:taxon, 44}) == %{
             "keep" => true,
             "host_taxon_id" => 44
           }

    grouped = Questions.group([q, q])
    group_other = choice(grouped, "Keep it for these 2 Galls, as another plant")

    assert group_other.hint ==
             "The Source names only “Ambrosia” here: it goes in for every Gall, on the plant " <>
               "you pick."

    assert group_other.effect ==
             "It goes in on %{taxon}, for these 2 Galls only. The Source's other “Ambrosia” " <>
               "statements stay as they are."

    assert Questions.picked_decision(group_other, {:taxon, 44}) == %{
             "keep" => true,
             "host_taxon_id" => 44
           }

    # A species-level Host keeps the reading.
    species = present(item, %{fact: fact, written: @dispute_written, host_rank: :species})

    assert Questions.picked_decision(choice(species, "Keep it, as another plant"), {:taxon, 44}) ==
             %{"keep" => true, "host_reading" => %{"name" => "Ambrosia", "taxon_id" => 44}}
  end

  test "each side's one-sentence summary, else its first sentence" do
    findings = [
      %{
        "reason" =>
          "The Host is only an unknown oak in Utah. The red oak pairing is about another Gall.",
        "summary" => "An unnamed oak is never paired with a scientific name.",
        "reviewer" => "model-b",
        "response" => %{
          "decision" => "disagree",
          "reason" => "Ashmead uses oak for the genus throughout. He pairs it with Quercus."
        }
      }
    ]

    q = present_dispute(host_dispute("f2", "g2", findings))

    assert q.sides == %{
             producer: ["Ashmead uses oak for the genus throughout."],
             checker: ["An unnamed oak is never paired with a scientific name."]
           }

    assert q.voices.checker == [
             "The Host is only an unknown oak in Utah. The red oak pairing is about another Gall."
           ]
  end

  test "identical disputes are one question, every Gall kept or dropped together" do
    one = present_dispute(host_dispute("f12", "g2"))
    two = present_dispute(host_dispute("f14", "g3"))

    assert one.about == "AULAX AMBROSIÆCOLA"
    assert one.statement == "Ambrosia is the Host"

    q = Questions.group([one, two])

    assert q.section.id == :disputes
    assert q.written == "Ambrosia is the Host"
    assert q.covers == 2
    assert q.context == "AULAX AMBROSIÆCOLA and the pith galls"
    assert q.question == "Should this statement go in for these 2 Galls: Ambrosia is the Host?"
    assert q.proposal == nil
    assert q.sides == one.sides

    assert labels(q) == [
             "Keep it: Ambrosia is the Host, for these 2 Galls",
             "Keep it for these 2 Galls, as another plant",
             "Drop it for both"
           ]

    other = choice(q, "Keep it for these 2 Galls, as another plant")
    assert other.picker == {:reading, "Ambrosia"}

    assert other.hint ==
             "The Source means another plant by “Ambrosia”: it goes in for every Gall, on the " <>
               "plant you pick."

    assert Questions.picked_decision(other, {:taxon, 44}) == %{
             "keep" => true,
             "host_reading" => %{"name" => "Ambrosia", "taxon_id" => 44}
           }

    keep = choice(q, "Keep it: Ambrosia is the Host, for these 2 Galls")
    assert keep.picker == :keep_galls
    assert keep.hint == "Untick any Gall to drop its statement on its own."

    assert Questions.picked_decision(keep, {:except, [7]}) == %{
             "keep" => true,
             "except" => [7]
           }

    assert choice(q, "Drop it for both").decision == %{"skip" => true}
    assert_plain(q)
  end

  test "a dispute about a Trait Fact is a disputed statement" do
    item = %QueueItem{
      kind: :dispute,
      statement_ref: "f19",
      subject: %{
        "findings" => [%{"problem" => "wrong_value", "reason" => "A purse is a pocket."}],
        "fact" => %{
          "kind" => "trait",
          "gall" => "g4",
          "trait" => "form",
          "value" => %{"value" => "leaf curl"}
        },
        "suggested_value" => "pocket"
      },
      proposal: %{}
    }

    q = present(item, %{written: %{"g4" => "the purse gall"}})

    assert q.section.id == :disputes
    assert q.statement == "form is leaf curl"
    assert labels(q) == ["Keep it", "Drop it"]
    assert_plain(q)
  end

  test "a dispute about a Trait term is a disputed term on Traits, holding nothing" do
    item = %QueueItem{
      kind: :dispute,
      statement_ref: "f7",
      subject: %{
        "findings" => @dispute_findings,
        "trait" => "detachable",
        "term" => "attached by a small point",
        "group" => "trait:detachable:attached by a small point"
      },
      proposal: %{}
    }

    fact = %{
      "id" => "f7",
      "kind" => "trait",
      "gall" => "g2",
      "trait" => "detachable",
      "term" => "attached by a small point"
    }

    q = present(item, %{fact: fact, written: @dispute_written})

    assert q.section.id == :trait_terms
    assert q.topic == :trait_dispute
    assert q.holds_approval == false
    assert q.trait == "detachable"
    assert q.written == "attached by a small point"
    assert q.tag == "Disputed"
    assert q.context == "AULAX AMBROSIÆCOLA"

    assert q.question ==
             "Should “attached by a small point” go in as AULAX AMBROSIÆCOLA's detachable?"

    assert q.proposal == nil
    assert q.sides.checker == ["No gall was seen on Ambrosia."]
    assert labels(q) == ["Keep it", "Drop it"]

    assert choice(q, "Drop it").hint ==
             "The Gall keeps “attached by a small point” as text, with no detachable value."

    assert_plain(q)
  end

  # -- Trait terms to settle (matter d213, Traits step) -----------------------------

  @color %{
    "color" => %{
      "tan" => "Light brown.",
      "white" => "White or nearly so.",
      "red" => "Red to pink.",
      "green" => "Green.",
      "yellow" => "Yellow."
    }
  }

  @form %{
    "form" => %{
      "abrupt swelling" => "A swelling with abrupt ends.",
      "tapered swelling" => "A swelling tapering at both ends.",
      "stem club" => "A club-shaped swelling at a stem's tip.",
      "globular" => "Round."
    }
  }

  @cells %{
    "cells" => %{
      "monothalamous" => "One larval chamber.",
      "polythalamous" => "More than one chamber."
    }
  }

  defp term_cover(gall, name, opts) do
    %{
      "gall" => gall,
      "name_as_written" => name,
      "term" => Keyword.get(opts, :term, "pale tan"),
      "facts" => [Keyword.get(opts, :fact, "f6")],
      "evidence" => [%{"quote" => Keyword.get(opts, :quote, "pale tan, rough")}],
      "suggestions" =>
        List.wrap(Keyword.get(opts, :suggested)) |> then(&if(&1 == [], do: [nil], else: &1)),
      "depends_on_gall" => Keyword.get(opts, :depends, false),
      "placements" => Keyword.get(opts, :placements, []),
      "findings" => Keyword.get(opts, :findings, []),
      "note" => opts[:note],
      "position" => 0
    }
  end

  defp term_item(trait, term, status, covers, opts \\ []),
    do: %QueueItem{
      kind: :trait_term,
      statement_ref: "u:#{trait}:#{term}",
      subject: %{
        "trait" => trait,
        "term" => term,
        "normalized_term" => term,
        "status" => status,
        "candidates" => Keyword.get(opts, :candidates, []),
        "format_version" => 4,
        "covers" => covers
      },
      proposal: Keyword.get(opts, :proposal, %{}),
      reason: "\"#{term}\" is a new #{trait} term the readers didn't place alike"
    }

  # The two checkers' placements of a cover: `[c1, c2]` (nil for none).
  defp checkers(categories) do
    for {c, i} <- Enum.with_index(categories, 1) do
      %{"reviewer" => "model-#{i}"}
      |> then(&if(c, do: Map.put(&1, "category", c), else: &1))
    end
  end

  describe "a new Trait term the readers didn't place alike" do
    setup do
      item =
        term_item("color", "pale tan", "new", [
          term_cover("g1", "the large stem galls",
            suggested: "tan",
            placements: [%{"reviewer" => "checker", "category" => "white", "reason" => "pale"}]
          ),
          term_cover("g2", "the small bud galls",
            fact: "f7",
            quote: "pale tan, lumpy",
            suggested: "tan",
            placements: [%{"reviewer" => "checker", "category" => "tan"}]
          )
        ])

      %{item: item, q: present(item, %{source: "Floate", definitions: @color})}
    end

    test "is in the Trait terms section, which holds nothing", %{q: q} do
      assert q.section.id == :trait_terms
      assert q.section.title == "Trait terms to settle"
      assert q.section.explanation =~ "Floate"
      assert q.section.explanation =~ "the producer, the AI that read the Source"
      assert q.section.explanation =~ "You can approve the Source with terms still open."
      refute q.section.holds_approval
      refute q.holds_approval
    end

    test "asks what the words mean, and what the answer sets", %{q: q} do
      assert q.written == "pale tan"
      assert q.trait == "color"
      assert q.tag == "New term"
      assert q.covers == 2
      assert q.context == "the large stem galls and the small bud galls"
      assert q.question == "What color value is “pale tan”?"

      assert q.scope ==
               "You're deciding what these words mean. The 2 Galls here that use them get " <>
                 "the value now, and any Source that writes “pale tan” later gets it " <>
                 "automatically. Galls described in other words don't change."

      assert q.leave == nil
      assert_plain(q)
    end

    test "with the readers split on a Gall, nothing is recommended", %{q: q} do
      assert q.proposal == nil
      assert q.undecided == %{label: "No recommendation", why: "The readers split"}
      refute Enum.any?(q.choices, & &1.proposed)
    end

    test "shows each Gall: its quote, what the readers said, what most chose", %{q: q} do
      assert [g1, g2] = q.galls
      assert %{ref: "g1", name: "the large stem galls", quotes: [%{text: "pale tan, rough"}]} = g1

      assert g1.said == [
               "The producer suggested tan.",
               "The checker placed it under white: pale."
             ]

      assert g1.default == nil
      assert g2.said == ["The producer suggested tan.", "The checker placed it under tan."]
      assert g2.default == "tan"
    end

    test "offers each value a reader chose, with who chose it", %{q: q} do
      assert labels(q) == [
               "tan",
               "white",
               "Another color",
               "More than one color",
               "It depends on the Gall",
               "Fits no color",
               "Keep as text"
             ]

      tan = choice(q, "tan")
      assert tan.hint == "Light brown."
      assert tan.decision == %{"place" => "tan"}
      assert tan.tally == "Most readers chose it for 1 of the 2 Galls"

      assert tan.effect ==
               "The 2 Galls here get tan. From now on, “pale tan” means tan in every Source."

      assert choice(q, "white").tally == "Chosen for 1 of the 2 Galls"
    end

    test "another value, several values, or a value per Gall", %{q: q} do
      another = choice(q, "Another color")
      assert another.picker == {:trait_value, "color"}

      assert another.hint ==
               "The words mean a color value no reader chose; pick it from the list."

      assert Questions.picked_decision(another, {:trait_value, "red"}) == %{"place" => "red"}
      assert another.effect =~ "The 2 Galls here get %{value}."

      several = choice(q, "More than one color")
      assert several.picker == {:trait_values, "color"}
      refute several.pending
      assert several.hint =~ "green-yellow"
      # The readers' values first.
      assert several.values == ["tan", "white"]

      assert Questions.picked_decision(several, {:trait_values, ["green", "yellow"]}) ==
               %{"place" => ["green", "yellow"]}

      per_gall = choice(q, "It depends on the Gall")
      assert per_gall.picker == :galls
      assert per_gall.hint =~ "nothing is set for other Sources"

      assert per_gall.effect ==
               "“pale tan” stays undecided for every Source: each new Gall that uses it is " <>
                 "asked again."

      assert Questions.picked_decision(per_gall, {:galls, %{"g1" => "white", "g2" => nil}}) ==
               %{"categories" => %{"g1" => "white", "g2" => nil}}

      # The values to choose from per Gall: the readers', with their definitions.
      assert Enum.map(q.definitions, &{&1.value, &1.definition}) == [
               {"tan", "Light brown."},
               {"white", "White or nearly so."}
             ]
    end

    test "fits none, or keep as text", %{q: q} do
      no_fit = choice(q, "Fits no color")
      assert no_fit.decision == %{"no_fit" => true}

      assert no_fit.effect ==
               "Both Galls keep the Source's words. “pale tan” goes to the superadmins' list " <>
                 "of terms that fit no color, where one may be added."

      keep = choice(q, "Keep as text")
      assert keep.decision == %{"keep" => true}

      assert keep.effect ==
               "Both Galls show “pale tan” in Floate's words, with no color value. Nothing " <>
                 "changes for other Sources."
    end
  end

  test "most readers' value is recommended, the readers named" do
    covers =
      for {g, name} <- [
            {"g1", "the cup plant gall"},
            {"g2", "the dock gall"},
            {"g3", "the rosinweed gall"}
          ] do
        term_cover(g, name,
          term: "each with a single insect",
          suggested: "monothalamous",
          placements: checkers(["monothalamous", "polythalamous"])
        )
      end

    q =
      present(term_item("cells", "each with a single insect", "new", covers), %{
        definitions: @cells
      })

    assert q.proposal.label == "monothalamous"
    assert q.proposal.why == "Chosen by the producer and checker 1, for all 3 Galls"
    assert q.proposal.decision == %{"place" => "monothalamous"}
    assert choice(q, "monothalamous").proposed == true
    assert choice(q, "polythalamous").tally == "Chosen by checker 2, for all 3 Galls"
    refute choice(q, "polythalamous").proposed
    assert Enum.map(q.galls, & &1.default) == ["monothalamous", "monothalamous", "monothalamous"]
  end

  test "a silent producer gives way to two agreeing checkers, Gall by Gall" do
    covers = [
      term_cover("g1", "the knot gall",
        term: "round",
        placements: checkers(["globular", "globular"])
      ),
      term_cover("g2", "the bramble gall", term: "round", placements: checkers([nil, nil]))
    ]

    q = present(term_item("form", "round", "new", covers), %{definitions: @form})

    assert Enum.map(q.galls, & &1.default) == ["globular", :text]

    assert q.proposal.label == "It depends on the Gall"
    assert q.proposal.why == "The readers chose differently for different Galls"
    assert q.proposal.decision == %{"categories" => %{"g1" => "globular", "g2" => nil}}
    assert choice(q, "It depends on the Gall").proposed == true

    assert choice(q, "It depends on the Gall").tally ==
             "The readers chose differently for different Galls"

    assert choice(q, "globular").tally == "Most readers chose it for 1 of the 2 Galls"
  end

  test "no reader placing it recommends keeping it as text" do
    covers = [term_cover("g1", "the knot gall", term: "odd", placements: checkers([nil, nil]))]
    q = present(term_item("form", "odd", "new", covers), %{definitions: @form})

    assert q.proposal.label == "Keep as text"
    assert q.proposal.why == "No reader placed it"
    assert choice(q, "Keep as text").proposed == true
  end

  test "most readers naming two values recommends both" do
    covers = [
      term_cover("g1", "the leaf gall",
        term: "green-yellow",
        suggested: ["green", "yellow"],
        placements:
          checkers(["green", "green"]) ++ [%{"reviewer" => "model-1", "category" => "yellow"}]
      )
    ]

    q = present(term_item("color", "green-yellow", "new", covers), %{definitions: @color})

    assert q.proposal.label == "green and yellow"
    assert q.proposal.decision == %{"place" => ["green", "yellow"]}
    assert choice(q, "green and yellow").proposed == true
    assert choice(q, "green and yellow").decision == %{"place" => ["green", "yellow"]}
  end

  describe "a term used in more than one sense" do
    setup do
      item =
        term_item(
          "form",
          "swelling",
          "ambiguous",
          [
            term_cover("g1", "the stem galls",
              term: "swelling",
              quote: "an abrupt swelling",
              suggested: "abrupt swelling",
              depends: true,
              placements: [
                %{
                  "reviewer" => "checker",
                  "category" => "abrupt swelling",
                  "depends_on_gall" => true
                }
              ]
            )
          ],
          candidates: ["abrupt swelling", "tapered swelling", "stem club"],
          proposal: %{"category" => "abrupt swelling"}
        )

      %{q: present(item, %{definitions: @form})}
    end

    test "says so, and is decided Gall by Gall", %{q: q} do
      assert q.tag == "Used in more than one sense"
      assert q.question == "What form value does “swelling” mean, Gall by Gall?"

      assert q.scope ==
               "“swelling” is used in more than one sense, so it is never placed for every Source."

      assert labels(q) == ["Choose for each Gall", "Keep as text"]
      assert choice(q, "Choose for each Gall").picker == :galls
    end

    test "recommends choosing for each Gall, each with what most readers chose", %{q: q} do
      assert q.proposal.label == "It depends on the Gall"
      assert q.proposal.why == "Used in more than one sense"
      assert q.proposal.decision == %{"categories" => %{"g1" => "abrupt swelling"}}
      assert choice(q, "Choose for each Gall").proposed == true

      assert hd(q.galls).said == [
               "The producer suggested abrupt swelling, and says it depends on the gall.",
               "The checker placed it under abrupt swelling, and says it depends on the gall."
             ]
    end

    test "defines every sense once", %{q: q} do
      assert Enum.map(q.definitions, & &1.value) == [
               "abrupt swelling",
               "tapered swelling",
               "stem club"
             ]
    end
  end

  test "a format 3 term set aside, and a checker's finding, read plainly" do
    item =
      term_item("walls", "hollow", "new", [
        term_cover("g1", "Mordwilkoja vagabunda",
          term: "hollow",
          note: "no walls value says hollow",
          findings: [%{"reason" => "hollow is thin", "suggestion" => "walls thin"}]
        )
      ])

    item = put_in(item.subject["format_version"], 3)
    q = present(item, %{source: "Floate"})

    assert hd(q.galls).said == [
             "The producer set it aside: no walls value says hollow.",
             "The checker: hollow is thin."
           ]

    assert q.undecided.label == "No recommendation"
  end

  test "a Trait term set aside before terms were settled is only acknowledged" do
    item = %QueueItem{
      kind: :set_aside_term,
      statement_ref: "u:walls:hollow",
      subject: %{
        "term" => "hollow",
        "slot" => "walls",
        "covers" => [cover("g1", "Mordwilkoja vagabunda", "hollow")]
      },
      proposal: %{"keep" => true}
    }

    q = present(item, %{source: "Floate"})
    assert q.section.id == :trait_terms
    assert labels(q) == ["Acknowledge"]
    assert hd(q.choices).decision == %{}
    assert_plain(q)
  end

  # -- what producers set aside as hedged (matter d213, Hedges step) ----------------

  defp cover(gall, name, term, opts \\ []),
    do: %{
      "gall" => gall,
      "name_as_written" => name,
      "term" => term,
      "evidence" => [%{"quote" => "a #{term} structure", "page" => "3"}],
      "note" => opts[:note],
      "position" => 0
    }

  describe "a statement set aside" do
    setup do
      item = %QueueItem{
        kind: :set_aside_statement,
        statement_ref: "u:other:rose",
        subject: %{
          "term" => "rose",
          "slot" => "other",
          "topic" => "host",
          "covers" => [
            cover("g5", "RHODITES GRACILIS", "rose", note: "Hedged Host (\"probably\")."),
            cover("g6", "RHODITES SIMILIS", "an unknown wild rose")
          ]
        },
        proposal: %{"keep" => true}
      }

      %{item: item, q: present(item)}
    end

    test "is grouped by what it is about, holding nothing", %{q: q} do
      assert q.section.id == :hedge_host
      assert q.section.title == "About Hosts"
      assert q.section.explanation == "Which plants the Gall is on."
      assert q.topic == :set_aside_statements
      refute q.holds_approval
      assert q.leave == "If you leave it: it stays out; approval doesn't wait on it."
      assert q.covers == 2
    end

    test "with no topic it is under Other", %{item: item} do
      q = present(%{item | subject: Map.delete(item.subject, "topic")})
      assert q.section.id == :hedge_other
      assert q.section.title == "Other"
    end

    test "names its Galls and the producer's note", %{q: q} do
      assert q.written == "rose"
      assert q.context == "RHODITES GRACILIS and RHODITES SIMILIS. Hedged Host (\"probably\")."
    end

    test "recommends leaving it out, or stating it", %{q: q} do
      assert q.question == "Should this hedged statement go in as a Fact?"
      assert q.proposal.label == "Leave it out"
      assert q.proposal.why == "A hedge stays out unless you state it"
      assert q.proposal.decision == %{"keep" => true}

      assert labels(q) == ["Leave it out", "State it…"]
      assert choice(q, "Leave it out").proposed == true

      assert choice(q, "Leave it out").hint ==
               "It stays out; the words remain in the Source's text."

      state = choice(q, "State it…")
      assert state.picker == :statement

      assert state.hint ==
               "Use this when you judge the Source states it outright. You choose what it says."

      assert Questions.picked_decision(state, {:host, 5}) ==
               %{"state" => %{"kind" => "host_of", "taxon_id" => 5}}

      assert Questions.picked_decision(state, {:place, "US-MO"}) ==
               %{"state" => %{"kind" => "occurrence", "place" => "US-MO"}}

      assert Questions.picked_decision(state, {:trait, "cells", "monothalamous"}) ==
               %{"state" => %{"kind" => "trait", "trait" => "cells", "value" => "monothalamous"}}

      assert_plain(q)
    end
  end

  test "a set-aside place is stated by picking the place" do
    item = %QueueItem{
      kind: :set_aside_statement,
      statement_ref: "u:place:probably taken at kirkwood, missouri",
      subject: %{
        "term" => "probably taken at Kirkwood, Missouri",
        "slot" => "place",
        "topic" => "range",
        "covers" => [cover("g3", "ANDRICUS MURTFELDTÆ", "probably taken at Kirkwood, Missouri")]
      },
      proposal: %{"keep" => true}
    }

    q = present(item)
    assert q.section.id == :hedge_range
    state = choice(q, "State it…")
    assert state.picker == :place
    assert q.context == "ANDRICUS MURTFELDTÆ"

    assert Questions.picked_decision(state, {:place, "US-MO"}) ==
             %{"state" => %{"kind" => "occurrence", "place" => "US-MO"}}
  end

  test "a set-aside statement about no Gall can only be left out" do
    item = %QueueItem{
      kind: :set_aside_statement,
      statement_ref: "u:taxonomic_act:x",
      subject: %{
        "term" => "x",
        "slot" => "taxonomic_act",
        "topic" => "names",
        "covers" => [cover(nil, nil, "x")]
      },
      proposal: %{"keep" => true}
    }

    q = present(item)
    assert q.section.id == :hedge_names
    assert q.section.title == "About names and species"
    assert labels(q) == ["Leave it out"]
  end

  # -- acknowledged after the fact -----------------------------------------------

  test "a same-date conflict is acknowledged, holding nothing" do
    item = %QueueItem{
      kind: :same_date_conflict,
      statement_ref: "f3",
      subject: %{"type" => "trait", "fact_id" => 7, "fact_ids" => [7, 8]}
    }

    q = present(item)

    assert q.section.id == :same_date
    refute q.holds_approval
    assert labels(q) == ["Acknowledge"]
    assert choice(q, "Acknowledge").decision == %{}
    assert q.leave =~ "nothing waits"
    assert_plain(q)
  end

  test "a same-date conflict a merge left names the Gall, the Facts and the merge" do
    item = %QueueItem{
      kind: :same_date_conflict,
      statement_ref: "merge:detachable: detachable | detachable: integral",
      subject: %{
        "type" => "trait",
        "fact_id" => 7,
        "fact_ids" => [7, 8],
        "gall_id" => 501,
        "merge" => %{"type" => "gall", "absorbed_id" => 9, "survivor_id" => 501}
      },
      reason:
        "Merging Andricus foo into Callirhytis morrisoni (sexgen): Sources with the same date disagree"
    }

    q = present(item)

    assert q.section.id == :same_date

    assert q.written ==
             "Callirhytis morrisoni (sexgen): detachable: detachable · detachable: integral"

    assert q.question =~ "Merging Andricus foo into Callirhytis morrisoni (sexgen)"
    assert labels(q) == ["Acknowledge"]
  end

  test "a generation outside its group names the Gall, Inducer and generation" do
    item = %QueueItem{
      kind: :generation_outside_group,
      statement_ref: "g3",
      subject: %{"gall_id" => 501, "inducer_id" => 200, "generation" => "fundatrix"}
    }

    q = present(item)

    assert q.section.id == :generation_outside

    assert q.question ==
             "Callirhytis morrisoni (sexgen) has the fundatrix generation, which isn't among " <>
               "those that apply to its Inducer, Andricus chrysolepidicola."

    assert choice(q, "Acknowledge").decision == %{}
    refute q.holds_approval
    assert_plain(q)
  end

  test "a taxonomic act that differs from the tree is acknowledged" do
    item = %QueueItem{
      kind: :taxonomy_disagreement,
      statement_ref: "a5",
      subject: %{"kind" => "placement", "stance" => "confirm", "taxon" => "t3", "parent" => "t1"},
      reason: "the tree places Andricus foo under Andricus"
    }

    q =
      present(item, %{
        written: %{"t3" => "Andricus foo", "t1" => "Callirhytis"},
        batch_type: :taxonomy
      })

    assert q.topic == :acts

    assert q.question ==
             "Ashmead places Andricus foo under Callirhytis. The tree places Andricus foo under Andricus."

    assert labels(q) == ["Acknowledge"]
    refute q.holds_approval
    assert_plain(q)
  end

  describe "a taxonomic statement to accept or decline (f923 Task 6)" do
    defp acceptance(subject) do
      %QueueItem{
        kind: :taxonomy_acceptance,
        statement_ref: "a5",
        subject:
          Map.merge(
            %{"stance" => "confirm", "fact_id" => 9, "attribution_id" => 8, "source_id" => 3},
            subject
          ),
        reason: "the tree places Andricus foo under Andricus"
      }
    end

    test "asks whether to follow the Source, recommending it, holding nothing" do
      item =
        acceptance(%{
          "kind" => "placement",
          "taxon_id" => 1,
          "parent_id" => 2,
          "written" => %{"taxon" => "Andricus foo", "parent" => "Callirhytis"}
        })

      q = present(item)

      assert q.section.id == :taxonomy_acceptance
      refute q.holds_approval
      assert q.written == "Andricus foo under Callirhytis"

      assert q.question ==
               "Ashmead places Andricus foo under Callirhytis. The tree places Andricus foo " <>
                 "under Andricus. Follow Ashmead?"

      assert labels(q) == ["Accept: follow Ashmead", "Decline"]
      assert choice(q, "Accept: follow Ashmead").proposed == true
      assert choice(q, "Accept: follow Ashmead").decision == %{"accept" => true}
      assert choice(q, "Accept: follow Ashmead").hint =~ "moves Andricus foo under Callirhytis"
      assert %{decision: nil, picker: :reason} = choice(q, "Decline")
      assert_plain(q)
    end

    test "what the tree holds now, when the page reads it, replaces the reason" do
      item =
        acceptance(%{
          "kind" => "synonymy",
          "name" => "Andricus foo",
          "accepted_taxon_id" => 2,
          "now" => "the tree holds Andricus foo as a species of its own"
        })

      q = present(item)
      assert q.written == "Andricus foo, a synonym of Heteroecus chrysolepidis"
      assert q.question =~ "The tree holds Andricus foo as a species of its own."
    end

    test "a decline needs its reason" do
      q = present(acceptance(%{"kind" => "common_name", "taxon_id" => 1, "common_name" => "x"}))

      assert Questions.picked_decision(choice(q, "Decline"), {:reason, "  Not followed. "}) ==
               %{"decline" => true, "reason" => "Not followed."}
    end
  end

  describe "a Gall whose Inducer was split (f923 Task 7)" do
    defp split_question(proposal) do
      %QueueItem{
        kind: :split_inducer,
        subject: %{
          "gall_id" => 501,
          "taxon_id" => 1,
          "into_taxon_ids" => [1, 2],
          "fact_id" => 9,
          "source_id" => 3
        },
        proposal: proposal,
        reason: "Ashmead split Disholandricus chrysolepidis into it and another."
      }
    end

    test "asks which taxon induces the Gall now: each daughter, or not known yet" do
      q = present(split_question(%{}))

      assert q.section.id == :split_inducer
      refute q.holds_approval
      assert q.written == "Callirhytis morrisoni (sexgen)"

      assert q.question ==
               "Ashmead splits Disholandricus chrysolepidis into Disholandricus chrysolepidis " <>
                 "and Heteroecus chrysolepidis. Which taxon induces Callirhytis morrisoni " <>
                 "(sexgen) now?"

      assert labels(q) == [
               "Disholandricus chrysolepidis, in its narrow sense",
               "Heteroecus chrysolepidis",
               "Not known yet"
             ]

      assert choice(q, "Heteroecus chrysolepidis").decision == %{"taxon_id" => 2}
      assert choice(q, "Heteroecus chrysolepidis").hint =~ "rename proposal"
      assert choice(q, "Not known yet").decision == %{"not_known" => true}
      assert choice(q, "Not known yet").hint =~ "old broad sense"
      assert q.proposal == nil
      refute Enum.any?(q.choices, & &1.proposed)
      assert_plain(q)
    end

    test "a daughter the Source's Galls share a Host with is recommended, to check" do
      q = present(split_question(%{"taxon_id" => 2, "why" => "Its Galls are on Quercus."}))

      assert %{firm: false, why: "Its Galls are on Quercus."} = q.proposal
      assert choice(q, "Heteroecus chrysolepidis").proposed == true
    end
  end

  # -- the Source, and renames ---------------------------------------------------

  test "a Source match picks a Source Gallformers holds or adds a new one" do
    item = %QueueItem{
      kind: :ambiguous_match,
      statement_ref: "source",
      subject: %{"title" => "Descriptions of new cynipidous galls", "citation" => "Ashmead 1897"},
      proposal: %{"candidate_ids" => [3, 4]}
    }

    q = present(item)

    assert q.section.id == :source
    assert q.holds_approval == true

    assert q.question ==
             "Is “Descriptions of new cynipidous galls” a Source Gallformers already holds?"

    assert choice(q, "It's Descriptions of new cynipidous galls").decision == %{"source_id" => 3}
    assert choice(q, "It's Cynipidous galls (abstract)").decision == %{"source_id" => 4}
    assert choice(q, "It's a new Source: add it").decision == %{"new" => true}
  end

  test "a retraction's Source may be left out" do
    item = %QueueItem{
      kind: :unresolved_name,
      statement_ref: "retracts",
      subject: %{"citation_as_written" => "Smith 1950"},
      proposal: %{}
    }

    q = present(item)

    assert q.section.id == :source
    assert q.question == "Which Source does this notice retract: “Smith 1950”?"
    assert choice(q, "Leave the retraction out").decision == %{"skip" => true}
  end

  describe "a Gall rename proposal" do
    test "proposes the new name" do
      item = %QueueItem{
        kind: :gall_rename,
        subject: %{"gall_id" => 501},
        proposal: %{
          "gall_id" => 501,
          "from" => "Callirhytis morrisoni (sexgen)",
          "to" => "Andricus morrisoni (sexgen)",
          "collision" => false
        }
      }

      q = present(item)

      assert q.section.id == :gall_rename
      refute q.holds_approval

      assert q.question ==
               "A change in the tree renames Callirhytis morrisoni (sexgen) to Andricus " <>
                 "morrisoni (sexgen). Rename the Gall?"

      assert q.proposal.label == "Rename it to Andricus morrisoni (sexgen)"
      assert q.proposal.decision == %{"accept" => true}

      assert choice(q, "Keep the name Callirhytis morrisoni (sexgen)").decision == %{
               "reject" => true
             }

      assert q.leave == "If you leave it: the Gall keeps its name."
    end

    test "a name another Gall has is not proposed, and says why" do
      item = %QueueItem{
        kind: :gall_rename,
        subject: %{"gall_id" => 501},
        proposal: %{"gall_id" => 501, "from" => "A", "to" => "B", "collision" => true}
      }

      q = present(item)

      assert q.proposal == nil

      assert q.warning ==
               "B is already another Gall's name: renaming is refused until that Gall's name changes."
    end
  end

  # -- sections ------------------------------------------------------------------

  test "the sections come in the steps' order" do
    assert Enum.map(Questions.sections("Ashmead"), & &1.id) == [
             :hosts,
             :which_taxon,
             :differ,
             :named_galls,
             :undescribed_galls,
             :generation_outside,
             :gall_rename,
             :disputes,
             :same_date,
             :trait_terms,
             :hedge_names,
             :hedge_inducer,
             :hedge_host,
             :hedge_range,
             :hedge_gall,
             :hedge_other,
             :taxonomy_acceptance,
             :split_inducer,
             :source
           ]
  end

  test "with no Source name the copy says “the Source”" do
    q = present(host(%{}), %{source: nil})

    assert q.question == "Which plant does the Source mean by “Q. obtusiloba”?"

    assert Questions.section(:synonyms, nil).title ==
             "The Source's names that Gallformers now treats as synonyms"
  end
end
