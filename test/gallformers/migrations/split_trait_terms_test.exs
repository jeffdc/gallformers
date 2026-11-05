defmodule Gallformers.Migrations.SplitTraitTermsTest do
  @moduledoc """
  The migration that makes `trait_term_mappings` the term table (`d213`
  Task A): today's rows, several packing many terms in one, become one term
  per row. The migration's `split/1` is tested on the rows the table held
  before it (the seeded `traits.json` mappings and the generation values'
  other names).
  """
  # The migration module is loaded by Code.require_file/2 in setup_all
  # (priv/repo/migrations is not on the Mix elixir paths), so its functions
  # are called with apply/3.
  # credo:disable-for-this-file Credo.Check.Refactor.Apply
  use ExUnit.Case, async: true

  @migration_path "priv/repo/migrations/20261102200000_split_trait_terms.exs"
  @migration_module Gallformers.Repo.Migrations.SplitTraitTerms

  setup_all do
    # Running the migrations (the `mix test` alias) may have loaded it already.
    unless Code.ensure_loaded?(@migration_module),
      do: Code.require_file(@migration_path, File.cwd!())

    :ok
  end

  @swelling_rule "Choose the candidate whose definition the Source's description fits. When " <>
                   "nothing distinguishes them, record the term in unmapped and name the " <>
                   "candidates."

  # The table's rows before the migration, in ID order.
  @old_rows [
    {"form", "swelling", [], ["tapered swelling", "abrupt swelling", "stem club"],
     @swelling_rule},
    {"plant_part", "inflorescence, raceme, catkin, ament", ["flower"], [], nil},
    {"texture", "woody, hard", ["stiff"], [], nil},
    {"alignment", "perpendicular", ["erect"], [], nil},
    {"texture", "smooth, glossy, polished, glabrous", ["hairless"], [], nil},
    {"texture", "rough", ["mealy"], [], nil},
    {"texture", "fleshy", ["succulent"], [], nil},
    {"walls", "pithy, pith-filled", ["spongy"], [], nil},
    {"cells", "a single central larval cell, one chamber", ["monothalamous"], [], nil},
    {"plant_part", "on the leaf, with no side, vein or midrib stated",
     ["upper leaf", "lower leaf"], [], nil},
    {"shape", "oval, ovate, ovoid, ellipsoid, egg-shaped", ["globular"], [], nil},
    {"generation", "stem mother", ["fundatrix"], [], nil},
    {"generation", "apterae fundatrigeniae", ["apterae"], [], nil},
    {"generation", "alienicolae, virginoparae", ["exules"], [], nil}
  ]

  defp old_rows do
    for {trait, term, maps_to, candidates, rule} <- @old_rows,
        do: %{trait: trait, term: term, maps_to: maps_to, candidates: candidates, rule: rule}
  end

  defp split, do: apply(@migration_module, :split, [old_rows()])

  test "splits each row listing several terms into one row per term, in order" do
    placed =
      for %{status: "placed", categories: [category]} = row <- split(),
          do: {row.trait, row.term, category}

    assert placed == [
             {"plant_part", "inflorescence", "flower"},
             {"plant_part", "raceme", "flower"},
             {"plant_part", "catkin", "flower"},
             {"plant_part", "ament", "flower"},
             {"texture", "woody", "stiff"},
             {"texture", "hard", "stiff"},
             {"alignment", "perpendicular", "erect"},
             {"texture", "smooth", "hairless"},
             {"texture", "glossy", "hairless"},
             {"texture", "polished", "hairless"},
             {"texture", "glabrous", "hairless"},
             {"texture", "rough", "mealy"},
             {"texture", "fleshy", "succulent"},
             {"walls", "pithy", "spongy"},
             {"walls", "pith-filled", "spongy"},
             {"cells", "a single central larval cell", "monothalamous"},
             {"cells", "one chamber", "monothalamous"},
             {"shape", "oval", "globular"},
             {"shape", "ovate", "globular"},
             {"shape", "ovoid", "globular"},
             {"shape", "ellipsoid", "globular"},
             {"shape", "egg-shaped", "globular"},
             {"generation", "stem mother", "fundatrix"},
             {"generation", "apterae fundatrigeniae", "apterae"},
             {"generation", "alienicolae", "exules"},
             {"generation", "virginoparae", "exules"}
           ]

    assert length(split()) == 28
  end

  test "a term with candidates becomes ambiguous, keeping its candidates; its rule is v4's" do
    assert [swelling | _] = split()

    assert swelling == %{
             trait: "form",
             term: "swelling",
             normalized_term: "swelling",
             status: "ambiguous",
             categories: [],
             candidates: ["tapered swelling", "abrupt swelling", "stem club"],
             rule:
               "The category depends on the gall: suggest the candidate whose definition " <>
                 "this gall's description fits, and set depends_on_gall; when nothing " <>
                 "distinguishes them, give category null with depends_on_gall."
           }

    # A rule edited since the seed is kept.
    [edited] =
      apply(@migration_module, :split, [
        [%{trait: "form", term: "knot", maps_to: [], candidates: ["stem club"], rule: "Mine."}]
      ])

    assert edited.rule == "Mine."
  end

  test "the leaf rule stays one term under its two categories, its condition kept as the rule" do
    assert [leaf] = Enum.filter(split(), &(&1.trait == "plant_part" and &1.rule))

    assert leaf == %{
             trait: "plant_part",
             term: "on the leaf",
             normalized_term: "on the leaf",
             status: "placed",
             categories: ["upper leaf", "lower leaf"],
             candidates: [],
             rule:
               "On the leaf, with no side, vein or midrib stated: the Gall is on both " <>
                 "sides, so the term gives two Facts, upper leaf and lower leaf."
           }

    # The only term under two categories.
    assert [^leaf] = Enum.filter(split(), &(length(&1.categories) > 1))
  end

  test "each term's normalized key is lowercased with its whitespace collapsed, unique per trait" do
    rows =
      apply(@migration_module, :split, [
        [
          %{
            trait: "shape",
            term: "Egg  Shaped, egg shaped",
            maps_to: ["globular"],
            candidates: [],
            rule: nil
          }
        ]
      ])

    assert [%{term: "Egg  Shaped", normalized_term: "egg shaped"}] = rows

    keys = for row <- split(), do: {row.trait, row.normalized_term}
    assert keys == Enum.uniq(keys)
  end
end
