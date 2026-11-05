defmodule Gallformers.Import.VocabEditsTest do
  @moduledoc """
  The Trait vocabulary owned by the database (`6611` Task 1, `d213` Task
  A): a Trait value added, or a term placed, marked ambiguous or
  unambiguous, marked as fitting no category, moved or spot-checked, is
  recorded in the replay log, replays after the cutover data migration, and
  is published in the contract's files by the vocabulary generator.

  Not async: loading the vocabularies waits on concurrent loads.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Vocab.TraitTermMapping
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.Replay
  alias Gallformers.Import.Vocab

  setup :audit_test_metadata

  setup do
    {:ok, _counts} = Catalog.load_vocab(test_actor())
    :ok
  end

  @value %{
    trait: "shape",
    value: "lenticular",
    definition: "Shaped like a lens: round and flattened, convex on both faces."
  }

  @at ~U[2026-11-01 12:00:00Z]

  defp ordered(text), do: Jason.decode!(text, objects: :ordered_objects)

  defp term_state(trait, term) do
    case Catalog.get_term(trait, term) do
      nil -> nil
      t -> Map.take(t, [:status, :categories, :candidates, :placed_by, :spot_checked_at])
    end
  end

  # Puts a term row back as `before` (deleted when nil), as the cutover data
  # migration's database would hold it.
  defp restore(trait, term, nil), do: Repo.delete!(Catalog.get_term(trait, term))

  defp restore(trait, term, before) do
    trait
    |> Catalog.get_term(term)
    |> Ecto.Changeset.change(Map.to_list(before))
    |> Repo.update!()
  end

  test "adding a value records it in the replay log" do
    assert {:ok, %TraitValue{value: "lenticular"}} =
             Import.record_trait_value_added(test_actor(), @value)

    assert [
             %{
               kind: :trait_value_added,
               key: %{"trait" => "shape", "value" => "lenticular"},
               payload: %{"definition" => "Shaped like a lens" <> _}
             }
           ] = Import.list_replay_entries()
  end

  test "each term edit is recorded in the replay log by trait and term" do
    edits = [
      {:place, "shape", "Lens-shaped", "sphere", :agreement},
      {:mark_ambiguous, "shape", "roundish", ["globular", "sphere"], :curator},
      {:mark_unambiguous, "shape", "roundish", "globular", :superadmin},
      {:mark_no_fit, "texture", "crusty", :curator},
      {:move, "texture", "rough", "bumpy"},
      {:spot_check, "shape", "Lens-shaped"}
    ]

    for edit <- edits do
      assert {:ok, %TraitTermMapping{}} = Import.record_term_edit(test_actor(), edit, at: @at)
    end

    entries = Import.list_replay_entries()
    assert Enum.uniq(Enum.map(entries, & &1.kind)) == [:trait_term_edit]

    assert Enum.map(entries, &{&1.key, &1.payload}) == [
             {%{"op" => "place", "trait" => "shape", "term" => "Lens-shaped"},
              %{
                "category" => "sphere",
                "placed_by" => "agreement",
                "at" => "2026-11-01T12:00:00Z"
              }},
             {%{"op" => "mark_ambiguous", "trait" => "shape", "term" => "roundish"},
              %{
                "candidates" => ["globular", "sphere"],
                "placed_by" => "curator",
                "at" => "2026-11-01T12:00:00Z"
              }},
             {%{"op" => "mark_unambiguous", "trait" => "shape", "term" => "roundish"},
              %{
                "category" => "globular",
                "placed_by" => "superadmin",
                "at" => "2026-11-01T12:00:00Z"
              }},
             {%{"op" => "mark_no_fit", "trait" => "texture", "term" => "crusty"},
              %{"placed_by" => "curator", "at" => "2026-11-01T12:00:00Z"}},
             {%{"op" => "move", "trait" => "texture", "term" => "rough"},
              %{"category" => "bumpy", "from" => ["mealy"], "at" => "2026-11-01T12:00:00Z"}},
             {%{"op" => "spot_check", "trait" => "shape", "term" => "Lens-shaped"},
              %{"at" => "2026-11-01T12:00:00Z"}}
           ]
  end

  test "a term placed under several values records the set" do
    assert {:ok, %TraitTermMapping{categories: ["upper leaf", "lower leaf"]}} =
             Import.record_term_edit(
               test_actor(),
               {:place, "plant_part", "protruding from both sides", ["upper leaf", "lower leaf"],
                :agreement},
               at: @at
             )

    assert [
             %{
               key: %{"op" => "place", "term" => "protruding from both sides"},
               payload: %{
                 "categories" => ["upper leaf", "lower leaf"],
                 "placed_by" => "agreement",
                 "at" => "2026-11-01T12:00:00Z"
               }
             }
           ] = Import.list_replay_entries()

    refute Map.has_key?(hd(Import.list_replay_entries()).payload, "category")
  end

  test "a refused value or term edit writes nothing to the replay log" do
    assert {:error, _changeset} =
             Import.record_trait_value_added(test_actor(), %{@value | definition: nil})

    assert {:error, _changeset} =
             Import.record_term_edit(test_actor(), {:place, "shape", "orb", "cube", :curator})

    assert {:error, {:placed, _}} =
             Import.record_term_edit(test_actor(), {:place, "shape", "ovoid", "sphere", :curator})

    assert {:error, :not_found} =
             Import.record_term_edit(test_actor(), {:spot_check, "shape", "orb"})

    assert Import.list_replay_entries() == []
  end

  test "a value and a placed term are in the generated traits.json and traits.schema.json" do
    {:ok, _} = Import.record_trait_value_added(test_actor(), @value)

    {:ok, _} =
      Import.record_term_edit(
        test_actor(),
        {:place, "shape", "lens-shaped", "lenticular", :curator}
      )

    files = Vocab.render("2026-01-02")
    traits = ordered(files["traits.json"])

    assert List.last(traits["traits"]["shape"]["values"]).values == [
             {"value", "lenticular"},
             {"definition", @value.definition}
           ]

    assert List.last(traits["mappings"]).values == [
             {"term", "lens-shaped"},
             {"trait", "shape"},
             {"status", "placed"},
             {"categories", ["lenticular"]}
           ]

    assert "lenticular" in ordered(files["traits.schema.json"])["$defs"]["shape"]["enum"]
  end

  test "the value replays, and replaying it again is a no-op" do
    {:ok, value} = Import.record_trait_value_added(test_actor(), @value)
    entries = Import.list_replay_entries()

    Repo.delete!(value)

    assert {:ok, 1} = Replay.run(entries, actor: test_actor())
    assert Catalog.get_trait_value("shape", "lenticular").definition == @value.definition

    logged = length(Import.list_replay_entries())
    assert {:ok, 1} = Replay.run(entries, actor: test_actor())
    assert length(Import.list_replay_entries()) == logged
  end

  # Each edit: the term before it, then after recording it the database is
  # put back as it was before, the entry replayed, and replayed again.
  for {name, edit, trait, term} <- [
        {"place", {:place, "shape", "Lens-shaped", "sphere", :agreement}, "shape", "lens-shaped"},
        {"place under several", {:place, "color", "green-yellow", ["green", "yellow"], :curator},
         "color", "green-yellow"},
        {"mark_ambiguous", {:mark_ambiguous, "texture", "rough", ["mealy", "bumpy"], :curator},
         "texture", "rough"},
        {"mark_unambiguous", {:mark_unambiguous, "form", "swelling", "stem club", :superadmin},
         "form", "swelling"},
        {"mark_no_fit", {:mark_no_fit, "texture", "crusty", :curator}, "texture", "crusty"},
        {"move", {:move, "texture", "rough", "bumpy"}, "texture", "rough"},
        {"spot_check", {:spot_check, "shape", "ovoid"}, "shape", "ovoid"}
      ] do
    @edit edit
    @trait trait
    @term term

    test "#{name} replays, and replaying it again is a no-op" do
      before = term_state(@trait, @term)
      {:ok, _} = Import.record_term_edit(test_actor(), @edit, at: @at)
      after_edit = term_state(@trait, @term)
      assert after_edit != before

      entries = Import.list_replay_entries()
      restore(@trait, @term, before)
      assert term_state(@trait, @term) == before

      assert {:ok, 1} = Replay.run(entries, actor: test_actor())
      assert term_state(@trait, @term) == after_edit

      logged = length(Import.list_replay_entries())
      assert {:ok, 1} = Replay.run(entries, actor: test_actor())
      assert term_state(@trait, @term) == after_edit
      assert length(Import.list_replay_entries()) == logged
    end
  end

  describe "moving a term" do
    # A Gall whose mealy Fact two Sources support: one with the term
    # "rough", one with "mealy".
    defp rough_gall do
      gall = gall_fixture(name: "Rough gall #{System.unique_integer([:positive])}")
      rough = source_fixture("Rough", "1990")
      mealy = source_fixture("Mealy", "1991")
      key = %{gall_id: gall.id, trait: "texture", value: "mealy"}

      {:ok, _} = Catalog.assert_trait(test_actor(), key, confirm(rough, %{term: "Rough"}))
      {:ok, _} = Catalog.assert_trait(test_actor(), key, confirm(mealy, %{term: "mealy"}))
      %{gall: gall, rough: rough, mealy: mealy}
    end

    defp texture_sources(gall_id, value) do
      case Catalog.find_fact(:trait, %{gall_id: gall_id, trait: "texture", value: value}) do
        {:ok, nil} ->
          []

        {:ok, fact_id} ->
          fact_id
          |> Facts.list_attributions()
          |> Enum.map(&{&1.source_id, &1.term})
          |> Enum.sort()
      end
    end

    test "carries the attributions with the term to the new category's Facts" do
      %{gall: gall, rough: rough, mealy: mealy} = rough_gall()

      {:ok, _} = Import.record_term_edit(test_actor(), {:move, "texture", "rough", "bumpy"})

      assert texture_sources(gall.id, "bumpy") == [{rough.id, "Rough"}]
      assert texture_sources(gall.id, "mealy") == [{mealy.id, "mealy"}]
      assert Enum.sort(Catalog.gall_summary(gall.id).traits["texture"]) == ["bumpy", "mealy"]
    end

    test "a Fact left with no Source is no longer shown" do
      gall = gall_fixture(name: "Rough gall #{System.unique_integer([:positive])}")
      rough = source_fixture("Rough", "1990")
      key = %{gall_id: gall.id, trait: "texture", value: "mealy"}
      {:ok, _} = Catalog.assert_trait(test_actor(), key, confirm(rough, %{term: "rough"}))

      {:ok, _} = Import.record_term_edit(test_actor(), {:move, "texture", "rough", "bumpy"})
      assert Catalog.gall_summary(gall.id).traits["texture"] == ["bumpy"]
    end

    test "the attributions move again when the move is replayed" do
      %{gall: gall, rough: rough} = rough_gall()
      before = term_state("texture", "rough")

      entries =
        Repo.transaction(fn ->
          {:ok, _} = Import.record_term_edit(test_actor(), {:move, "texture", "rough", "bumpy"})
          Repo.rollback(Import.list_replay_entries())
        end)
        |> elem(1)

      assert term_state("texture", "rough") == before
      assert texture_sources(gall.id, "bumpy") == []

      assert {:ok, 1} = Replay.run(entries, actor: test_actor())
      assert texture_sources(gall.id, "bumpy") == [{rough.id, "Rough"}]
    end
  end

  test "a replayed placement keeps the time it was made" do
    {:ok, _} =
      Import.record_term_edit(test_actor(), {:place, "shape", "orb", "sphere", :agreement},
        at: @at
      )

    entries = Import.list_replay_entries()
    Repo.delete!(Catalog.get_term("shape", "orb"))

    assert {:ok, 1} = Replay.run(entries, actor: test_actor())

    assert %TraitTermMapping{placed_at: @at, placed_by: :agreement} =
             Catalog.get_term("shape", "orb")
  end

  test "a value or term already in the database is left as it is on replay" do
    entries = [
      %{
        kind: :trait_value_added,
        key: %{"trait" => "season", "value" => "Spring"},
        payload: %{"definition" => "Another definition."}
      },
      # 6611's term mappings, logged before terms were one per row.
      %{
        "kind" => "term_mapping_added",
        "key" => %{"trait" => "shape", "term" => "ovoid"},
        "payload" => %{"maps_to" => ["globular"], "candidates" => [], "rule" => nil}
      }
    ]

    assert {:ok, 2} = Replay.run(entries, actor: test_actor())

    assert Catalog.get_trait_value("season", "Spring").definition ==
             "The Gall forms and grows in spring."

    assert %TraitTermMapping{categories: ["globular"], placed_by: :seed} =
             Catalog.get_term("shape", "ovoid")
  end

  test "6611's term mappings replay as placed or ambiguous terms" do
    entries = [
      %{
        "kind" => "term_mapping_added",
        "key" => %{"trait" => "shape", "term" => "orb"},
        "payload" => %{"maps_to" => ["sphere"], "candidates" => [], "rule" => nil}
      },
      %{
        "kind" => "term_mapping_added",
        "key" => %{"trait" => "shape", "term" => "roundish"},
        "payload" => %{"maps_to" => [], "candidates" => ["globular", "sphere"], "rule" => nil}
      }
    ]

    assert {:ok, 2} = Replay.run(entries, actor: test_actor())

    assert %TraitTermMapping{status: :placed, categories: ["sphere"], placed_by: :curator} =
             Catalog.get_term("shape", "orb")

    assert %TraitTermMapping{status: :ambiguous, candidates: ["globular", "sphere"]} =
             Catalog.get_term("shape", "roundish")
  end
end
