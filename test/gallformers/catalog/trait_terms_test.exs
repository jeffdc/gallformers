defmodule Gallformers.Catalog.TraitTermsTest do
  @moduledoc """
  The term table (`d213` Task A): a Source's term per Trait, one per row,
  placed under one category (a value of its Trait), or under each value its
  words name ("green-yellow": green and yellow, d213), ambiguous with
  candidates, or fitting no category; how and when it was placed, and when
  it was spot-checked.

  Not async: the vocabulary tables are unique on their values, so concurrent
  sandbox transactions loading them wait on each other.
  """
  use Gallformers.DataCase, async: false

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Vocab.TraitTermMapping
  alias Gallformers.Import.TraitTerms

  setup do
    {:ok, _} = Catalog.load_vocab(test_actor())
    :ok
  end

  defp audit_change_count, do: Repo.aggregate(test_audit_changes(), :count)

  @at ~U[2026-11-01 12:00:00Z]

  # A term naming two values, under both.
  defp two_category_term! do
    row = %{
      trait: "color",
      term: "green-yellow",
      normalized_term: "green-yellow",
      status: :placed,
      categories: ["green", "yellow"],
      placed_by: :curator,
      placed_at: @at
    }

    {1, _} = Repo.insert_all(TraitTermMapping, [row])
    :ok
  end

  describe "get_term/2" do
    test "finds a term by its normalized key: case and whitespace don't matter" do
      assert %TraitTermMapping{term: "ovoid", categories: ["globular"]} =
               Catalog.get_term("shape", "  Ovoid ")

      assert %TraitTermMapping{term: "a single central larval cell"} =
               Catalog.get_term("cells", "A single  central\nlarval cell")

      assert Catalog.get_term("color", "ovoid") == nil
      assert Catalog.get_term("shape", "lens-shaped") == nil
    end

    # `c8c3` item 10: Nastasi & Davis's "swelling" and "swellings" were two questions.
    test "a word's plural is the same term: a Source writing either form takes it" do
      assert %TraitTermMapping{term: "ovoid"} = Catalog.get_term("shape", "Ovoids")

      for {plural, singular} <- [
            {"swellings", "swelling"},
            {"covered in short hairs", "covered in short hair"},
            {"many chambers", "many chamber"},
            {"berries", "berry"},
            {"patches of hairs", "patch of hair"},
            {"masses", "mass"}
          ] do
        assert TraitTermMapping.normalize(plural) == TraitTermMapping.normalize(singular)
      end

      # Words that only look plural stay as they are.
      for word <- ["hairless", "glabrous", "various", "species", "this", "gas"] do
        assert TraitTermMapping.normalize(word) == word
      end
    end

    test "normalizes as the import's questions about terms do" do
      for term <- ["Pale  Tan", " ovoid", "ÉCLAT"] do
        assert TraitTerms.statement_ref("color", term) ==
                 "u:color:" <> TraitTermMapping.normalize(term)
      end
    end
  end

  describe "one category, or several" do
    test "the database takes a term under each value its words name, however placed" do
      :ok = two_category_term!()

      assert %TraitTermMapping{categories: ["green", "yellow"], placed_by: :curator} =
               Catalog.get_term("color", "green-yellow")

      row = %{
        trait: "plant_part",
        term: "protruding from both sides",
        normalized_term: "protruding from both sides",
        status: :placed,
        categories: ["upper leaf", "lower leaf"],
        placed_by: :agreement,
        placed_at: @at
      }

      assert {1, _} = Repo.insert_all(TraitTermMapping, [row])
    end

    test "a placed term has its category; an ambiguous one candidates; neither holds the other" do
      base = %{
        trait: "shape",
        term: "x",
        normalized_term: "x",
        placed_by: :curator,
        placed_at: @at
      }

      for {attrs, constraint} <- [
            {%{status: :placed, categories: []}, "trait_term_mappings_status_check"},
            {%{status: :ambiguous, categories: ["globular"], candidates: ["sphere"]},
             "trait_term_mappings_status_check"},
            {%{status: :no_fit, categories: [], candidates: ["sphere"]},
             "trait_term_mappings_status_check"}
          ] do
        assert_raise Postgrex.Error, ~r/#{constraint}/, fn ->
          Repo.transaction(fn ->
            Repo.insert_all(TraitTermMapping, [Map.merge(base, attrs)])
          end)
        end
      end
    end
  end

  describe "place_term/6" do
    test "places a new term under a category for every Source, audited" do
      changes = audit_change_count()

      assert {:ok,
              %TraitTermMapping{
                trait: "shape",
                term: "Lens-shaped",
                normalized_term: "lens-shaped",
                status: :placed,
                categories: ["sphere"],
                candidates: [],
                placed_by: :agreement,
                placed_at: @at,
                spot_checked_at: nil
              }} =
               Catalog.place_term(test_actor(), "shape", "Lens-shaped", "sphere", :agreement,
                 at: @at
               )

      assert Catalog.get_term("shape", "lens-shaped").categories == ["sphere"]
      assert audit_change_count() == changes + 1
    end

    test "places a new term under each value its words name" do
      assert {:ok,
              %TraitTermMapping{
                status: :placed,
                categories: ["green", "yellow"],
                placed_by: :agreement
              }} =
               Catalog.place_term(
                 test_actor(),
                 "color",
                 "green-yellow",
                 ["green", "yellow", "green"],
                 :agreement
               )

      assert {:ok, %TraitTermMapping{categories: ["upper leaf", "lower leaf"]}} =
               Catalog.place_term(
                 test_actor(),
                 "plant_part",
                 "protruding from both sides",
                 ["upper leaf", "lower leaf"],
                 :curator
               )

      assert {:ok, %TraitTermMapping{categories: ["tan"]}} =
               Catalog.place_term(test_actor(), "color", "pale tan", ["tan"], :curator)
    end

    test "several categories: each a value of the Trait, at least one" do
      for categories <- [["green", "sphere"], []] do
        assert {:error, changeset} =
                 Catalog.place_term(test_actor(), "color", "odd", categories, :curator)

        assert %{categories: [_]} = errors_on(changeset)
      end

      refute Catalog.get_term("color", "odd")
    end

    test "placing a term again under its categories writes nothing" do
      :ok = two_category_term!()
      changes = audit_change_count()

      assert {:ok, %TraitTermMapping{categories: ["globular"], placed_by: :seed}} =
               Catalog.place_term(test_actor(), "shape", "Ovoid", "globular", :agreement)

      # The same values in any order are the same placement.
      assert {:ok, %TraitTermMapping{categories: ["green", "yellow"], placed_by: :curator}} =
               Catalog.place_term(
                 test_actor(),
                 "color",
                 "green-yellow",
                 ["yellow", "green"],
                 :agreement
               )

      assert audit_change_count() == changes
    end

    test "refuses another set of categories for a placed term" do
      :ok = two_category_term!()

      for categories <- ["yellow", ["green", "yellow", "white"]] do
        assert {:error, {:placed, %TraitTermMapping{categories: ["green", "yellow"]}}} =
                 Catalog.place_term(test_actor(), "color", "green-yellow", categories, :curator)
      end

      assert {:error, {:placed, %TraitTermMapping{}}} =
               Catalog.place_term(
                 test_actor(),
                 "shape",
                 "ovoid",
                 ["globular", "sphere"],
                 :curator
               )
    end

    test "refuses a second category, and an ambiguous term" do
      assert {:error, {:placed, %TraitTermMapping{categories: ["globular"]}}} =
               Catalog.place_term(test_actor(), "shape", "ovoid", "sphere", :agreement)

      assert {:error, {:ambiguous, %TraitTermMapping{term: "swelling"}}} =
               Catalog.place_term(test_actor(), "form", "swelling", "stem club", :curator)

      assert Catalog.get_term("shape", "ovoid").categories == ["globular"]
    end

    test "places a term that fit no category, once a category fits" do
      {:ok, _} = Catalog.mark_term_no_fit(test_actor(), "shape", "lumpy", :curator)

      assert {:ok,
              %TraitTermMapping{status: :placed, categories: ["globular"], placed_by: :superadmin}} =
               Catalog.place_term(test_actor(), "shape", "lumpy", "globular", :superadmin)
    end

    test "takes only a value of the term's Trait, a known Trait and a known way of placing" do
      for {args, field} <- [
            {["shape", "orb", "cube", :curator], :categories},
            {["shape", "orb", "leaf curl", :curator], :categories},
            {["size", "big", "sphere", :curator], :trait},
            {["shape", "orb", "sphere", :guess], :placed_by},
            {["shape", "  ", "sphere", :curator], :term}
          ] do
        assert {:error, changeset} = apply(Catalog, :place_term, [test_actor() | args])
        assert Map.has_key?(errors_on(changeset), field), "#{inspect(args)}: #{field}"
      end

      refute Catalog.get_term("shape", "orb")
    end

    test "places a generation value's other name" do
      assert {:ok, %TraitTermMapping{categories: ["sexual"]}} =
               Catalog.place_term(
                 test_actor(),
                 "generation",
                 "bisexual generation",
                 "sexual",
                 :superadmin
               )

      assert {:error, changeset} =
               Catalog.place_term(test_actor(), "generation", "orb", "sphere", :superadmin)

      assert %{categories: [_]} = errors_on(changeset)
    end
  end

  describe "mark_term_ambiguous/6 and mark_term_unambiguous/6" do
    test "a new term is marked ambiguous with its candidates" do
      assert {:ok,
              %TraitTermMapping{
                status: :ambiguous,
                categories: [],
                candidates: ["globular", "sphere"],
                placed_by: :curator
              }} =
               Catalog.mark_term_ambiguous(
                 test_actor(),
                 "shape",
                 "roundish",
                 ["globular", "sphere"],
                 :curator
               )
    end

    test "a placed term marked ambiguous loses its category" do
      assert {:ok,
              %TraitTermMapping{
                status: :ambiguous,
                categories: [],
                candidates: ["mealy", "bumpy"]
              }} =
               Catalog.mark_term_ambiguous(
                 test_actor(),
                 "texture",
                 "rough",
                 ["mealy", "bumpy"],
                 :agreement
               )

      assert Catalog.get_term("texture", "rough").status == :ambiguous
    end

    test "needs candidates, each a value of the Trait" do
      for candidates <- [[], ["cube"]] do
        assert {:error, changeset} =
                 Catalog.mark_term_ambiguous(
                   test_actor(),
                   "shape",
                   "roundish",
                   candidates,
                   :curator
                 )

        assert %{candidates: [_]} = errors_on(changeset)
      end
    end

    test "an ambiguous term marked unambiguous is placed under one category" do
      assert {:ok,
              %TraitTermMapping{
                status: :placed,
                categories: ["tapered swelling"],
                candidates: [],
                placed_by: :superadmin,
                placed_at: @at
              }} =
               Catalog.mark_term_unambiguous(
                 test_actor(),
                 "form",
                 "swelling",
                 "tapered swelling",
                 :superadmin,
                 at: @at
               )
    end

    test "only an ambiguous term is marked unambiguous" do
      assert {:error, {:not_ambiguous, %TraitTermMapping{}}} =
               Catalog.mark_term_unambiguous(
                 test_actor(),
                 "shape",
                 "ovoid",
                 "sphere",
                 :superadmin
               )

      assert {:error, :not_found} =
               Catalog.mark_term_unambiguous(test_actor(), "shape", "orb", "sphere", :superadmin)
    end
  end

  describe "mark_term_no_fit/5" do
    test "a new or ambiguous term fits no category" do
      assert {:ok, %TraitTermMapping{status: :no_fit, categories: [], candidates: []}} =
               Catalog.mark_term_no_fit(test_actor(), "texture", "velvety-crusted", :curator)

      assert {:ok, %TraitTermMapping{status: :no_fit, candidates: []}} =
               Catalog.mark_term_no_fit(test_actor(), "form", "swelling", :superadmin)
    end

    test "refuses a placed term" do
      assert {:error, {:placed, %TraitTermMapping{}}} =
               Catalog.mark_term_no_fit(test_actor(), "shape", "ovoid", :curator)
    end
  end

  describe "move_term/5" do
    test "moves a placed term to another category, saying what must move" do
      assert {:ok, %{term: term, from: ["mealy"], to: "bumpy"}} =
               Catalog.move_term(test_actor(), "texture", "rough", "bumpy", at: @at)

      assert %TraitTermMapping{
               status: :placed,
               categories: ["bumpy"],
               placed_by: :superadmin,
               placed_at: @at
             } = term

      assert Catalog.get_term("texture", "rough").categories == ["bumpy"]
    end

    test "moves a two-category term to one category" do
      :ok = two_category_term!()

      assert {:ok, %{from: ["green", "yellow"], to: "yellow"}} =
               Catalog.move_term(test_actor(), "color", "green-yellow", "yellow")
    end

    test "refuses a term not placed, an unknown term and another Trait's value" do
      assert {:error, {:not_placed, %TraitTermMapping{}}} =
               Catalog.move_term(test_actor(), "form", "swelling", "stem club")

      assert {:error, :not_found} = Catalog.move_term(test_actor(), "shape", "orb", "sphere")

      assert {:error, changeset} = Catalog.move_term(test_actor(), "texture", "rough", "sphere")
      assert %{categories: [_]} = errors_on(changeset)
    end
  end

  describe "record_term_spot_check/4" do
    test "records when a placement was spot-checked" do
      assert {:ok, %TraitTermMapping{spot_checked_at: @at, categories: ["globular"]}} =
               Catalog.record_term_spot_check(test_actor(), "shape", "ovoid", at: @at)

      assert Catalog.get_term("shape", "ovoid").spot_checked_at == @at
      assert {:error, :not_found} = Catalog.record_term_spot_check(test_actor(), "shape", "orb")
    end
  end
end
