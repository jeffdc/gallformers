defmodule Gallformers.Import.TermCandidatesTest do
  @moduledoc """
  Seeding the term table (matter `d213`, Task F): the (Source term,
  suggested category) uses gathered from producer packages
  (`Gallformers.Import.gather_term_candidates/2`), stored as seed
  candidates for a superadmin, and decided one at a time or in bulk
  (`Gallformers.Import.decide_term_candidate/3`,
  `Gallformers.Import.place_term_candidates/2`), each decision a term edit
  recorded for replay.

  Not async: the Catalog vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog
  alias Gallformers.Import
  alias Gallformers.Import.Replay
  alias Gallformers.Import.TermCandidate

  setup :audit_test_metadata

  setup do
    load_vocab!()
    root = Path.join(System.tmp_dir!(), "term_candidates_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(root) end)
    %{root: root}
  end

  # -- fixture packages --------------------------------------------------------

  defp quote_of(text), do: [%{"item" => "#/texts/1", "quote" => text}]

  defp v3(id, gall, trait, value, as_written, quote) do
    %{
      "id" => id,
      "stance" => "confirm",
      "kind" => "trait",
      "gall" => gall,
      "trait" => trait,
      "value" => %{"value" => value, "as_written" => as_written},
      "evidence" => quote_of(quote)
    }
  end

  defp v4(id, gall, trait, term, category, quote) do
    %{
      "id" => id,
      "stance" => "confirm",
      "kind" => "trait",
      "gall" => gall,
      "trait" => trait,
      "term" => term,
      "category" => category && %{"value" => category},
      "evidence" => quote_of(quote)
    }
  end

  defp galls(refs), do: for(ref <- refs, do: %{"ref" => ref, "name_as_written" => "Gall #{ref}"})

  defp write_package!(dir, content) do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "gall.json"), Jason.encode!(content))
  end

  # pkg-a (format 3): "rounded" globular twice and set aside once, "rough"
  # (seeded under mealy) suggested bumpy, "globular" (a category's name).
  # nested/pkg-b (format 4): "Rounded" globular, "lens-like" with no
  # category.
  defp write_packages!(root) do
    write_package!(Path.join(root, "pkg-a"), %{
      "format_version" => 3,
      "galls" => galls(~w(g1 g2 g3)),
      "facts" => [
        v3("f1", "g1", "shape", "globular", "rounded", "a rounded gall"),
        v3("f2", "g2", "shape", "globular", "rounded", "rounded, smooth"),
        v3("f3", "g1", "texture", "bumpy", "rough", "rough to the touch"),
        v3("f4", "g2", "shape", "globular", "globular", "globular"),
        %{"id" => "f5", "kind" => "host", "gall" => "g1", "host" => "t1"}
      ],
      "unmapped" => [
        %{
          "slot" => "shape",
          "term" => "rounded",
          "gall" => "g3",
          "note" => "rounded, or lumpy?",
          "evidence" => quote_of("roughly rounded")
        },
        %{"slot" => "host", "term" => "an oak", "gall" => "g3"}
      ]
    })

    write_package!(Path.join([root, "nested", "pkg-b"]), %{
      "format_version" => 4,
      "galls" => galls(~w(g1)),
      "facts" => [
        v4("f1", "g1", "shape", "Rounded", "globular", "Rounded above"),
        v4("f2", "g1", "shape", "lens-like", nil, "flat and lens-like")
      ]
    })
  end

  defp gather!(dirs) do
    assert {:ok, summary} = Import.gather_term_candidates(test_actor(), dirs)
    summary
  end

  defp candidate(trait, term) do
    Enum.find(Import.list_term_candidates(decided: true), fn c ->
      c.trait == trait and c.normalized_term == term
    end)
  end

  # -- gathering -----------------------------------------------------------------

  describe "gathering" do
    test "groups format 3, format 4 and set-aside uses by Trait and normalized term",
         %{root: root} do
      write_packages!(root)
      summary = gather!([root])

      assert summary.packages == ["pkg-a", "pkg-b"]
      assert summary.created == 2

      rounded = candidate("shape", "rounded")
      assert rounded.term == "rounded"
      assert rounded.total == 4

      assert rounded.suggestions == [
               %{"category" => "globular", "count" => 3},
               %{"category" => nil, "count" => 1}
             ]

      assert TermCandidate.sources(rounded) == ["pkg-a", "pkg-b"]

      assert [_ | _] = rounded.uses

      assert rounded.uses |> Enum.map(& &1["source"]) |> Enum.uniq() |> Enum.sort() == [
               "pkg-a",
               "pkg-b"
             ]

      assert %{"gall" => "Gall g3", "quote" => "roughly rounded"} =
               Enum.find(rounded.uses, &is_nil(&1["category"]))

      lens = candidate("shape", "lens-like")
      assert lens.total == 1
      assert lens.suggestions == [%{"category" => nil, "count" => 1}]
    end

    test "skips the terms the term table holds, reporting producers' other categories",
         %{root: root} do
      write_packages!(root)
      summary = gather!([root])

      assert candidate("texture", "rough") == nil
      assert candidate("shape", "globular") == nil

      assert %{status: :placed, categories: ["mealy"], conflicts: conflicts} =
               Enum.find(summary.held, &(&1.trait == "texture" and &1.term == "rough"))

      assert conflicts == [%{"category" => "bumpy", "count" => 1}]

      assert %{status: :placed, categories: ["globular"], conflicts: []} =
               Enum.find(summary.held, &(&1.trait == "shape" and &1.term == "globular"))
    end

    test "gathering again updates an open candidate, counting each package once",
         %{root: root} do
      write_packages!(root)
      gather!([root])
      summary = gather!([Path.join(root, "pkg-a"), root])

      assert summary.created == 0
      assert summary.updated == 2
      assert candidate("shape", "rounded").total == 4
    end

    test "never overwrites a decided candidate", %{root: root} do
      write_packages!(root)
      gather!([root])

      {:ok, _} =
        Import.decide_term_candidate(test_actor(), candidate("shape", "lens-like"), :no_fit)

      write_package!(Path.join(root, "pkg-c"), %{
        "format_version" => 4,
        "galls" => galls(~w(g1)),
        "facts" => [v4("f1", "g1", "shape", "lens-like", "globular", "lens-like")]
      })

      # The ruling put the term in the table: it is held now.
      summary = gather!([root])
      assert %{status: :no_fit} = Enum.find(summary.held, &(&1.term == "lens-like"))
      assert %{total: 1, decision: %{"no_fit" => true}} = candidate("shape", "lens-like")

      # And on a database whose table lacks it, the decided candidate stays as it is.
      Repo.delete!(Catalog.get_term("shape", "lens-like"))
      assert gather!([root]).decided == 1
      assert %{total: 1, decision: %{"no_fit" => true}} = candidate("shape", "lens-like")
    end
  end

  # -- deciding ------------------------------------------------------------------

  describe "deciding" do
    setup %{root: root} do
      write_packages!(root)
      gather!([root])
      :ok
    end

    test "places a term under a category, for every Source, recorded for replay" do
      rounded = candidate("shape", "rounded")
      assert TermCandidate.agreed_category(rounded) == nil

      assert {:ok, decided} =
               Import.decide_term_candidate(test_actor(), rounded, {:place, "globular"})

      assert %TermCandidate{decision: %{"place" => "globular"}, decided_at: %DateTime{}} = decided

      assert %{status: :placed, categories: ["globular"], placed_by: :superadmin} =
               Catalog.get_term("shape", "rounded")

      assert [%{key: %{"op" => "place", "term" => "rounded"}, payload: payload}] =
               term_edits()

      assert payload["placed_by"] == "superadmin"
      assert Import.list_term_candidates() |> Enum.map(& &1.normalized_term) == ["lens-like"]
    end

    test "marks a term ambiguous between categories" do
      {:ok, _} =
        Import.decide_term_candidate(
          test_actor(),
          candidate("shape", "rounded"),
          {:ambiguous, ["globular", "sphere"]}
        )

      assert %{status: :ambiguous, candidates: candidates} = Catalog.get_term("shape", "rounded")
      assert Enum.sort(candidates) == ["globular", "sphere"]
      assert [%{key: %{"op" => "mark_ambiguous"}}] = term_edits()
    end

    test "marks a term as fitting no category" do
      {:ok, _} =
        Import.decide_term_candidate(test_actor(), candidate("shape", "lens-like"), :no_fit)

      assert %{status: :no_fit} = Catalog.get_term("shape", "lens-like")
      assert [%{key: %{"op" => "mark_no_fit"}}] = term_edits()
    end

    test "a refused term edit leaves the candidate open" do
      {:ok, _} =
        Import.record_term_edit(test_actor(), {:place, "shape", "rounded", "sphere", :curator})

      assert {:error, {:placed, _}} =
               Import.decide_term_candidate(
                 test_actor(),
                 candidate("shape", "rounded"),
                 {:place, "globular"}
               )

      assert candidate("shape", "rounded").decided_at == nil
    end

    test "places in bulk only the candidates whose uses all agree", %{root: root} do
      write_package!(Path.join(root, "pkg-d"), %{
        "format_version" => 4,
        "galls" => galls(~w(g1 g2)),
        "facts" => [
          v4("f1", "g1", "shape", "pear-shaped", "globular", "pear-shaped"),
          v4("f2", "g2", "shape", "pear-shaped", "globular", "pear-shaped too")
        ]
      })

      gather!([root])
      egg = candidate("shape", "pear-shaped")
      assert TermCandidate.agreed_category(egg) == "globular"

      candidates = [egg, candidate("shape", "rounded"), candidate("shape", "lens-like")]

      assert {:ok, %{placed: 1, skipped: 2, failed: []}} =
               Import.place_term_candidates(test_actor(), candidates)

      assert %{status: :placed, categories: ["globular"]} =
               Catalog.get_term("shape", "pear-shaped")

      assert Catalog.get_term("shape", "rounded") == nil
      assert candidate("shape", "pear-shaped").decision == %{"place" => "globular"}
    end

    test "a placement replays on a database without it" do
      {:ok, _} =
        Import.decide_term_candidate(
          test_actor(),
          candidate("shape", "rounded"),
          {:place, "globular"}
        )

      entries = term_edits()
      Repo.delete!(Catalog.get_term("shape", "rounded"))

      assert {:ok, 1} = Replay.run(entries, actor: test_actor())
      Gallformers.ImportFixtures.assert_replays_again(entries, test_actor())
      assert %{status: :placed, categories: ["globular"]} = Catalog.get_term("shape", "rounded")
    end
  end

  defp term_edits, do: Enum.filter(Import.list_replay_entries(), &(&1.kind == :trait_term_edit))
end
