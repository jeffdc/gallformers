defmodule Gallformers.Taxa.SyncTest do
  @moduledoc """
  The tree follows the Facts (`f923` Task 5): when a taxonomic slot's
  winner changes (an acceptance, a decline, a retraction, a Gallformers
  statement), the tree rows are rewritten in the same transaction through
  the Taxa writers, and the Gall renames that follow are proposed. A change
  the tree refuses (a cycle, a rank inversion) fails the transaction with
  the reason. `Gallformers.Taxa.Sync.check/0` rebuilds the expected tree
  from the Facts and lists what differs.

  Not async: loads the vocabularies and makes the Gallformers Source.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Sources
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Sync
  alias Gallformers.Taxa.Taxon

  setup :audit_test_metadata

  setup do
    load_vocab!()
    legacy = Sources.get_legacy_data_source()
    weld = source_fixture("Weld", "1959")

    family = taxon_fixture(rank: :family, name: "Syncidae", kingdom: "Animalia")
    other = taxon_fixture(rank: :family, name: "Othersyncidae", kingdom: "Animalia")
    tribe = taxon_fixture(rank: :tribe, name: "Syncini", parent: family)
    genus = taxon_fixture(rank: :genus, name: "Synca", parent: tribe)
    species = taxon_fixture(name: "Synca alba", parent: genus)

    for taxon <- [family, other, tribe, genus, species], do: legacy!(taxon, legacy)

    %{
      legacy: legacy,
      weld: weld,
      family: family,
      other: other,
      tribe: tribe,
      genus: genus,
      species: species
    }
  end

  # The tree's own statements of `taxon`, as the cutover makes them.
  defp legacy!(taxon, legacy) do
    taxon = Taxa.get_taxon!(taxon.id)
    attribution = %{source_id: legacy.id, stance: :confirm, stated: nil}

    {:ok, _} =
      Taxa.assert_placement(
        test_actor(),
        %{taxon_id: taxon.id, parent_id: taxon.parent_id},
        attribution
      )

    {:ok, _} =
      Taxa.assert_name(
        test_actor(),
        %{taxon_id: taxon.id, name: Taxa.accepted_name(taxon), rank: taxon.rank},
        attribution
      )
  end

  defp accept!({:ok, %{attribution: attribution}}) do
    assert {:ok, _} = Facts.accept(test_actor(), attribution.id)
    attribution
  end

  defp parent_id(taxon), do: Taxa.get_taxon!(taxon.id).parent_id

  defp gall!(name, inducer, source, attrs) do
    gall = attrs |> Map.new() |> Map.put(:name, name) |> gall_fixture()

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: inducer.id, object_gall_id: gall.id},
        confirm(source)
      )

    gall
  end

  defp proposals(gall),
    do: Enum.filter(Import.list_gall_renames(), &(&1.subject["gall_id"] == gall.id))

  describe "placements" do
    test "an unaccepted newer placement leaves the tree as it is", ctx do
      {:ok, _} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: ctx.tribe.id, parent_id: ctx.other.id},
          confirm(ctx.weld)
        )

      assert parent_id(ctx.tribe) == ctx.family.id
      assert Sync.check() |> for_taxa([ctx.tribe]) == []
    end

    test "accepting a placement moves the taxon and proposes the Gall renames", ctx do
      unknown =
        gall!("Unknown (Syncidae) q-alba-cup-gall", ctx.tribe, ctx.weld,
          descriptor: "q-alba-cup-gall"
        )

      Taxa.assert_placement(
        test_actor(),
        %{taxon_id: ctx.tribe.id, parent_id: ctx.other.id},
        confirm(ctx.weld)
      )
      |> accept!()

      assert parent_id(ctx.tribe) == ctx.other.id

      assert [%{proposal: %{"to" => "Unknown (Othersyncidae) q-alba-cup-gall"}}] =
               proposals(unknown)

      assert Sync.check() |> for_taxa([ctx.tribe]) == []
    end

    test "a retraction of the accepted Source moves it back", ctx do
      Taxa.assert_placement(
        test_actor(),
        %{taxon_id: ctx.tribe.id, parent_id: ctx.other.id},
        confirm(ctx.weld)
      )
      |> accept!()

      notice = source_fixture("Retraction", "2001")
      {:ok, _} = Sources.retract_source(test_actor(), ctx.weld, notice, ~D[2001-01-01])
      {:ok, _} = Facts.recompute_for_source(test_actor(), ctx.weld.id)

      assert parent_id(ctx.tribe) == ctx.family.id
    end

    test "declining an accepted placement moves it back", ctx do
      statement =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: ctx.tribe.id, parent_id: ctx.other.id},
          confirm(ctx.weld)
        )
        |> accept!()

      {:ok, _} = Facts.decline(test_actor(), statement.id, "Not followed.")
      assert parent_id(ctx.tribe) == ctx.family.id
    end

    test "an acceptance that would form a cycle is refused, with the reason", ctx do
      {:ok, %{attribution: statement}} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: ctx.family.id, parent_id: ctx.genus.id},
          confirm(ctx.weld)
        )

      assert {:error, {:rejected, Sync, {:tree, taxon_id, :cycle, message}}} =
               Facts.accept(test_actor(), statement.id)

      assert taxon_id == ctx.family.id
      assert message =~ "under itself"
      assert Facts.get_attribution(statement.id).accepted_at == nil
      assert parent_id(ctx.family) == nil
    end

    test "a rank inversion is refused", ctx do
      {:ok, %{attribution: statement}} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: ctx.other.id, parent_id: ctx.genus.id},
          confirm(ctx.weld)
        )

      assert {:error, {:rejected, Sync, {:tree, _id, :rank_inversion, _message}}} =
               Facts.accept(test_actor(), statement.id)
    end

    test "a Gallformers statement counts without acceptance", ctx do
      gallformers = gallformers_source()

      {:ok, _} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: ctx.tribe.id, parent_id: ctx.other.id},
          confirm(gallformers, %{stated: "2026-01-01", statement_text: "No paper places it."})
        )

      assert parent_id(ctx.tribe) == ctx.other.id
    end
  end

  describe "names" do
    test "an accepted new name renames the taxon; the old name is a synonym", ctx do
      gall = gall!("Synca alba (agamic)", ctx.species, ctx.weld, generation: "agamic")

      Taxa.assert_name(
        test_actor(),
        %{
          taxon_id: ctx.species.id,
          name: "Synca nigra",
          rank: :species,
          authorship: "Weld, 1959"
        },
        confirm(ctx.weld)
      )
      |> accept!()

      species = Taxa.get_taxon!(ctx.species.id)
      assert Taxa.accepted_name(species) == "Synca nigra"
      assert [%{name: "Synca alba", status: :synonym}] = Taxa.list_synonyms(species)

      assert [%{authorship: "Weld, 1959"}] =
               Enum.filter(species.names, &(&1.status == :accepted))

      assert [%{proposal: %{"to" => "Synca nigra (agamic)"}}] = proposals(gall)
      assert Sync.check() |> for_taxa([ctx.species]) == []
    end

    test "an accepted rank changes the rank", ctx do
      Taxa.assert_name(
        test_actor(),
        %{taxon_id: ctx.genus.id, name: "Synca", rank: :subtribe},
        confirm(ctx.weld)
      )
      |> accept!()

      assert Taxa.get_taxon!(ctx.genus.id).rank == :subtribe
    end

    test "a refused rank fails the acceptance", ctx do
      {:ok, %{attribution: statement}} =
        Taxa.assert_name(
          test_actor(),
          %{taxon_id: ctx.genus.id, name: "Synca", rank: :family},
          confirm(ctx.weld)
        )

      assert {:error, {:rejected, Sync, {:tree, _id, :rank_inversion, _}}} =
               Facts.accept(test_actor(), statement.id)
    end

    test "retracting the renaming Source restores the old name", ctx do
      Taxa.assert_name(
        test_actor(),
        %{taxon_id: ctx.species.id, name: "Synca nigra", rank: :species},
        confirm(ctx.weld)
      )
      |> accept!()

      notice = source_fixture("Retraction", "2001")
      {:ok, _} = Sources.retract_source(test_actor(), ctx.weld, notice, ~D[2001-01-01])
      {:ok, _} = Facts.recompute_for_source(test_actor(), ctx.weld.id)

      species = Taxa.get_taxon!(ctx.species.id)
      assert Taxa.accepted_name(species) == "Synca alba"
      assert Taxa.list_synonyms(species) == []
      assert Sync.check() |> for_taxa([ctx.species]) == []
    end
  end

  describe "synonymy" do
    test "an accepted synonymy of a name the tree lacks adds the synonym; declining removes it",
         ctx do
      statement =
        Taxa.assert_synonymy(
          test_actor(),
          %{name: "Cynips alba", accepted_taxon_id: ctx.species.id},
          confirm(ctx.weld)
        )
        |> accept!()

      assert [%{name: "Cynips alba"}] = Taxa.list_synonyms(ctx.species)

      {:ok, _} = Facts.decline(test_actor(), statement.id, "Misread.")
      assert Taxa.list_synonyms(ctx.species) == []
    end

    test "an accepted synonymy of another taxon's accepted name merges it (a lump)", ctx do
      nigra = taxon_fixture(name: "Synca nigra", parent: ctx.genus)
      legacy!(nigra, ctx.legacy)
      gall = gall!("Synca nigra (agamic)", nigra, ctx.weld, generation: "agamic")

      Taxa.assert_synonymy(
        test_actor(),
        %{name: "Synca nigra", accepted_taxon_id: ctx.species.id},
        confirm(ctx.weld)
      )
      |> accept!()

      assert Taxa.get_taxon(nigra.id) == nil
      assert Taxa.taxon_redirect(nigra.id) == ctx.species.id
      assert "Synca nigra" in Enum.map(Taxa.list_synonyms(ctx.species), & &1.name)
      assert [%{proposal: %{"to" => "Synca alba (agamic)"}}] = proposals(gall)
      assert Sync.check() |> for_taxa([ctx.species]) == []
    end
  end

  describe "a lump and the absorbed taxon's synonym at once" do
    test "both come into effect in one change", ctx do
      nigra = taxon_fixture(name: "Synca nigra", parent: ctx.genus)
      legacy!(nigra, ctx.legacy)
      {:ok, _} = Taxa.add_synonym(test_actor(), nigra, "Zynips nigra")

      # Accepted while the paper is retracted, so neither counts yet.
      notice = source_fixture("Retraction", "2001")
      {:ok, weld} = Sources.retract_source(test_actor(), ctx.weld, notice, ~D[2001-01-01])

      for name <- ["Synca nigra", "Zynips nigra"] do
        Taxa.assert_synonymy(
          test_actor(),
          %{name: name, accepted_taxon_id: ctx.species.id},
          confirm(ctx.weld)
        )
        |> accept!()
      end

      assert %Taxon{} = Taxa.get_taxon(nigra.id)

      {:ok, _} = Sources.unretract_source(test_actor(), weld)
      {:ok, _} = Facts.recompute_for_source(test_actor(), ctx.weld.id)

      assert Taxa.get_taxon(nigra.id) == nil

      assert Enum.sort(Enum.map(Taxa.list_synonyms(ctx.species), & &1.name)) ==
               ["Synca nigra", "Zynips nigra"]
    end
  end

  describe "common names and splits" do
    test "an accepted common name is added", ctx do
      Taxa.assert_common_name(
        test_actor(),
        %{taxon_id: ctx.species.id, common_name: "white sync wasp"},
        confirm(ctx.weld)
      )
      |> accept!()

      assert [%{name: "white sync wasp"}] = Taxa.list_common_names(ctx.species)
    end

    test "an accepted split emits the split; the tree is unchanged", ctx do
      a = taxon_fixture(name: "Synca beta", parent: ctx.genus)
      b = taxon_fixture(name: "Synca gamma", parent: ctx.genus)

      Taxa.assert_split(
        test_actor(),
        %{taxon_id: ctx.species.id, into_taxon_ids: [a.id, b.id]},
        confirm(ctx.weld)
      )
      |> accept!()

      assert %Taxon{} = Taxa.get_taxon(ctx.species.id)
    end
  end

  describe "plants" do
    test "a plant's statements never move it" do
      family = taxon_fixture(rank: :family, name: "Syncaceae", kingdom: "Plantae", origin: :powo)

      other =
        taxon_fixture(rank: :family, name: "Othersyncaceae", kingdom: "Plantae", origin: :powo)

      genus = taxon_fixture(rank: :genus, name: "Syncus", parent: family, origin: :powo)
      gallformers = gallformers_source()

      {:ok, _} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: genus.id, parent_id: other.id},
          confirm(gallformers, %{stated: "2026-01-01", statement_text: "Moved."})
        )

      assert parent_id(genus) == family.id
      assert Sync.check() |> for_taxa([genus]) == []
    end
  end

  describe "check/0" do
    test "finds a hand-edited drift", ctx do
      {:ok, _} = Taxa.place(test_actor(), ctx.tribe, ctx.other)
      {:ok, _} = Taxa.add_synonym(test_actor(), ctx.species, "Cynips albella")

      assert [
               %{taxon_id: t, aspect: :placement, expected: e, actual: a},
               %{taxon_id: s, aspect: :synonym, expected: nil, actual: "Cynips albella"}
             ] = Sync.check() |> for_taxa([ctx.tribe, ctx.species])

      assert {t, e, a} == {ctx.tribe.id, ctx.family.id, ctx.other.id}
      assert s == ctx.species.id
    end

    test "a taxon no Fact places or names is listed" do
      bare = taxon_fixture(rank: :family, name: "Baridae", kingdom: "Animalia")

      assert [%{aspect: :placement, expected: :none}, %{aspect: :name, expected: :none}] =
               Sync.check() |> for_taxa([bare])
    end
  end

  defp for_taxa(differences, taxa) do
    ids = Enum.map(taxa, & &1.id)
    Enum.filter(differences, &(&1.taxon_id in ids))
  end
end
