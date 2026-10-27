defmodule Gallformers.Taxa.ActFactsTest do
  @moduledoc """
  Taxonomic-act Facts (`9449` §3, Task 7): the contract's five act kinds
  recorded as Facts with natural keys, attributed to Sources. Placement and
  accepted name compete in slots. In phase 1 they are recorded only: they
  never move the editorial tree.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.TaxaFixtures

  alias Gallformers.Facts
  alias Gallformers.Facts.Fact
  alias Gallformers.Sources
  alias Gallformers.Taxa
  alias Gallformers.Taxa.ActFacts.CommonNameFact
  alias Gallformers.Taxa.ActFacts.NameFact
  alias Gallformers.Taxa.ActFacts.PlacementFact
  alias Gallformers.Taxa.ActFacts.SplitFact
  alias Gallformers.Taxa.ActFacts.SynonymyFact

  defp source_fixture(title, authored) do
    {:ok, source} =
      Sources.create_source(%{
        title: title,
        author: "Weld, L. H.",
        pubyear: String.slice(authored, 0, 4),
        link: "https://example.com/#{System.unique_integer([:positive])}",
        citation: "#{title}.",
        license: "Public Domain / Copyright Expired"
      })

    {:ok, source} =
      Sources.update_source_details(test_actor(), source, %{
        kind: "publication",
        authored: authored
      })

    source
  end

  defp confirm(source, extra \\ %{}),
    do: Map.merge(%{source_id: source.id, stance: :confirm}, extra)

  defp standing(fact_id), do: Facts.get_fact!(fact_id).standing

  defp changes_for(table) do
    Repo.all(from c in test_audit_changes(), where: c.table_name == ^table, order_by: c.id)
  end

  setup do
    cynipidae = taxon_fixture(rank: :family, name: "Cynipidae")
    figitidae = taxon_fixture(rank: :family, name: "Figitidae")
    genus = taxon_fixture(rank: :genus, name: "Andricus", parent: cynipidae)
    species = taxon_fixture(rank: :species, name: "Andricus foo", parent: genus)

    %{cynipidae: cynipidae, figitidae: figitidae, genus: genus, species: species}
  end

  describe "acceptance: a placement is superseded" do
    test "the newer Source's placement is current, the older superseded, and the tree is unchanged",
         ctx do
      ancestors_before = Taxa.ancestors(ctx.species)

      {:ok, older} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: ctx.genus.id, parent_id: ctx.cynipidae.id},
          confirm(source_fixture("Kinsey", "1930"))
        )

      {:ok, newer} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: ctx.genus.id, parent_id: ctx.figitidae.id},
          confirm(source_fixture("Revision", "1990"))
        )

      assert newer.fact.id != older.fact.id
      assert standing(newer.fact.id) == :current
      assert standing(older.fact.id) == :superseded

      assert Taxa.get_taxon!(ctx.genus.id).parent_id == ctx.cynipidae.id
      assert Taxa.ancestors(ctx.species) == ancestors_before
    end

    test "the order the Sources arrive in does not matter", ctx do
      {:ok, newer} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: ctx.genus.id, parent_id: ctx.figitidae.id},
          confirm(source_fixture("Revision", "1990"))
        )

      {:ok, older} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: ctx.genus.id, parent_id: ctx.cynipidae.id},
          confirm(source_fixture("Kinsey", "1930"))
        )

      assert standing(newer.fact.id) == :current
      assert standing(older.fact.id) == :superseded
      assert Taxa.get_taxon!(ctx.genus.id).parent_id == ctx.cynipidae.id
    end
  end

  describe "assert_placement/3" do
    test "two Sources stating one placement make one Fact with two attributions", ctx do
      key = %{taxon_id: ctx.genus.id, parent_id: ctx.cynipidae.id}

      {:ok, first} =
        Taxa.assert_placement(test_actor(), key, confirm(source_fixture("A", "1900")))

      {:ok, second} =
        Taxa.assert_placement(test_actor(), key, confirm(source_fixture("B", "1910")))

      assert first.fact.id == second.fact.id
      assert %Fact{kind: "taxon_placement", standing: :current} = second.fact
      assert second.fact.slot == "taxon:#{ctx.genus.id}:placement"
      assert %PlacementFact{taxon_id: t, parent_id: p} = second.detail
      assert {t, p} == {ctx.genus.id, ctx.cynipidae.id}
      assert length(Facts.list_attributions(first.fact.id)) == 2
    end

    test "lists a taxon's placement Facts with their standings", ctx do
      {:ok, _} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: ctx.genus.id, parent_id: ctx.cynipidae.id},
          confirm(source_fixture("A", "1900"))
        )

      assert [%PlacementFact{fact: %Fact{standing: :current}}] =
               Taxa.list_placement_facts(ctx.genus)

      assert Taxa.list_placement_facts(ctx.species) == []
    end

    test "a taxon cannot be placed under itself", ctx do
      assert {:error, changeset} =
               Taxa.assert_placement(
                 test_actor(),
                 %{taxon_id: ctx.genus.id, parent_id: ctx.genus.id},
                 confirm(source_fixture("A", "1900"))
               )

      assert %{parent_id: [_]} = errors_on(changeset)
    end

    test "a failed attribution leaves no Fact behind", ctx do
      facts_before = Repo.aggregate(Fact, :count)

      assert {:error, changeset} =
               Taxa.assert_placement(
                 test_actor(),
                 %{taxon_id: ctx.genus.id, parent_id: ctx.figitidae.id},
                 %{source_id: -1, stance: :confirm}
               )

      assert %{source_id: ["does not exist"]} = errors_on(changeset)
      assert Repo.aggregate(Fact, :count) == facts_before
      assert Repo.aggregate(PlacementFact, :count) == 0
    end

    test "is audited", ctx do
      {:ok, %{fact: fact}} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: ctx.genus.id, parent_id: ctx.cynipidae.id},
          confirm(source_fixture("A", "1900"))
        )

      assert [%{op: :insert, table_pk: [pk]}] = changes_for("placement_facts")
      assert pk == to_string(fact.id)
    end
  end

  describe "assert_name/3" do
    test "a name is keyed by taxon, normalized name and rank, in the taxon's name slot", ctx do
      {:ok, first} =
        Taxa.assert_name(
          test_actor(),
          %{taxon_id: ctx.species.id, name: "Andricus foo", rank: :species},
          confirm(source_fixture("A", "1900"), %{authorship_as_written: "(Ashmead, 1881)"})
        )

      {:ok, same} =
        Taxa.assert_name(
          test_actor(),
          %{taxon_id: ctx.species.id, name: "ANDRICUS FOO", rank: "species"},
          confirm(source_fixture("B", "1910"), %{
            authorship_as_written: "Ashmead",
            status_as_written: "comb. nov."
          })
        )

      assert same.fact.id == first.fact.id
      assert %Fact{kind: "taxon_name"} = same.fact
      assert same.fact.slot == "taxon:#{ctx.species.id}:name"
      assert %NameFact{name: "Andricus foo", rank: :species} = same.detail

      # Authorship and status words are each Source's own, as written.
      assert [
               %{authorship_as_written: "(Ashmead, 1881)", status_as_written: nil},
               %{authorship_as_written: "Ashmead", status_as_written: "comb. nov."}
             ] =
               Facts.list_attributions(first.fact.id)
    end

    test "a different name for the taxon competes in its name slot", ctx do
      {:ok, old} =
        Taxa.assert_name(
          test_actor(),
          %{taxon_id: ctx.species.id, name: "Cynips foo", rank: :species},
          confirm(source_fixture("A", "1881"))
        )

      {:ok, new} =
        Taxa.assert_name(
          test_actor(),
          %{taxon_id: ctx.species.id, name: "Andricus foo", rank: :species},
          confirm(source_fixture("B", "1950"))
        )

      assert standing(new.fact.id) == :current
      assert standing(old.fact.id) == :superseded
      assert Taxa.accepted_name(ctx.species) == "Andricus foo"
    end
  end

  describe "assert_synonymy/3" do
    test "keyed by the synonym's normalized name and the accepted taxon", ctx do
      key = %{name: "Cynips foo", accepted_taxon_id: ctx.species.id}

      {:ok, first} = Taxa.assert_synonymy(test_actor(), key, confirm(source_fixture("A", "1900")))

      {:ok, same} =
        Taxa.assert_synonymy(
          test_actor(),
          %{key | name: "cynips  FOO"},
          confirm(source_fixture("B", "1910"), %{status_as_written: "syn. nov."})
        )

      other_accepted = taxon_fixture(name: "Andricus bar")

      {:ok, other} =
        Taxa.assert_synonymy(
          test_actor(),
          %{key | accepted_taxon_id: other_accepted.id},
          confirm(source_fixture("C", "1920"))
        )

      assert same.fact.id == first.fact.id
      assert other.fact.id != first.fact.id
      assert %Fact{kind: "taxon_synonymy", slot: nil} = first.fact
      assert %SynonymyFact{name: "Cynips foo"} = same.detail

      # Recorded only: the tree's names are untouched.
      assert Taxa.resolve_name("Cynips foo") == :none
    end
  end

  describe "assert_split/3" do
    test "keyed by the taxon and the set of daughters, in any order", ctx do
      a = taxon_fixture(name: "Andricus a")
      b = taxon_fixture(name: "Andricus b")
      c = taxon_fixture(name: "Andricus c")

      {:ok, first} =
        Taxa.assert_split(
          test_actor(),
          %{taxon_id: ctx.species.id, into_taxon_ids: [b.id, a.id]},
          confirm(source_fixture("A", "1990"))
        )

      {:ok, same} =
        Taxa.assert_split(
          test_actor(),
          %{taxon_id: ctx.species.id, into_taxon_ids: [a.id, b.id]},
          confirm(source_fixture("B", "1995"))
        )

      {:ok, other} =
        Taxa.assert_split(
          test_actor(),
          %{taxon_id: ctx.species.id, into_taxon_ids: [a.id, b.id, c.id]},
          confirm(source_fixture("C", "2000"))
        )

      assert same.fact.id == first.fact.id
      assert other.fact.id != first.fact.id
      assert %Fact{kind: "taxon_split", slot: nil} = first.fact
      assert %SplitFact{into_taxon_ids: into} = first.detail
      assert into == Enum.sort([a.id, b.id])

      assert Repo.all(
               from d in "split_fact_daughters",
                 where: d.fact_id == ^first.fact.id,
                 select: d.taxon_id,
                 order_by: d.taxon_id
             ) == into
    end

    test "needs two distinct daughters other than the taxon itself", ctx do
      a = taxon_fixture(name: "Andricus a")
      source = source_fixture("A", "1990")

      for into <- [[a.id], [a.id, a.id], [a.id, ctx.species.id]] do
        assert {:error, changeset} =
                 Taxa.assert_split(
                   test_actor(),
                   %{taxon_id: ctx.species.id, into_taxon_ids: into},
                   confirm(source)
                 )

        assert %{into_taxon_ids: [_]} = errors_on(changeset)
      end
    end

    test "a daughter must be a taxon", ctx do
      a = taxon_fixture(name: "Andricus a")

      assert {:error, changeset} =
               Taxa.assert_split(
                 test_actor(),
                 %{taxon_id: ctx.species.id, into_taxon_ids: [a.id, -1]},
                 confirm(source_fixture("A", "1990"))
               )

      assert %{into_taxon_ids: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "assert_common_name/3" do
    test "keyed by taxon and common name, ignoring case", ctx do
      key = %{taxon_id: ctx.species.id, common_name: "Woolly oak gall wasp"}

      {:ok, first} =
        Taxa.assert_common_name(test_actor(), key, confirm(source_fixture("A", "1900")))

      {:ok, same} =
        Taxa.assert_common_name(
          test_actor(),
          %{key | common_name: "woolly OAK gall wasp"},
          confirm(source_fixture("B", "1910"))
        )

      assert same.fact.id == first.fact.id
      assert %Fact{kind: "taxon_common_name", slot: nil} = first.fact
      assert %CommonNameFact{common_name: "Woolly oak gall wasp"} = same.detail

      # Recorded only: the taxon's editorial common names are untouched.
      assert Taxa.list_common_names(ctx.species) == []
    end
  end
end
