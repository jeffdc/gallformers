defmodule Gallformers.Taxa.OperationsTest do
  @moduledoc """
  The Taxa operations the tree's sync with the Facts needs (`f923` Task
  4): rank, authorship and sensu, synonym events, a lump (merge) and a
  split. Each is audited and emits its "taxon changed" event.

  Not async: listeners are registered in the application environment.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures, only: [source_fixture: 2, confirm: 1, confirm: 2]
  import Gallformers.TaxaFixtures

  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Sources
  alias Gallformers.Taxa
  alias Gallformers.Taxa.ActFacts.PlacementFact
  alias Gallformers.Taxa.ActFacts.SynonymyFact
  alias Gallformers.Taxa.Event

  defmodule Recorder do
    @moduledoc false
    @behaviour Gallformers.Taxa.Events

    @impl true
    def taxon_changed(%Event{} = event) do
      case Process.get(__MODULE__) do
        nil -> :ok
        pid -> send(pid, {__MODULE__, event})
      end

      :ok
    end
  end

  setup do
    previous = Application.get_env(:gallformers, Gallformers.Taxa.Events)
    listeners = Keyword.get(previous || [], :listeners, [])
    Application.put_env(:gallformers, Gallformers.Taxa.Events, listeners: listeners ++ [Recorder])
    on_exit(fn -> Application.put_env(:gallformers, Gallformers.Taxa.Events, previous) end)
    Process.put(Recorder, self())

    family = taxon_fixture(rank: :family, name: "Opsidae", kingdom: "Animalia")
    genus = taxon_fixture(rank: :genus, name: "Opsa", parent: family)
    species = taxon_fixture(rank: :species, name: "Opsa alba", parent: genus)

    %{family: family, genus: genus, species: species}
  end

  defp changes_for(table),
    do: Repo.all(from c in test_audit_changes(), where: c.table_name == ^table)

  describe "set_rank/3" do
    test "changes the rank, audited, and emits :rank", ctx do
      assert {:ok, %{rank: :subgenus}} = Taxa.set_rank(test_actor(), ctx.genus, :subgenus)

      assert_received {Recorder,
                       %Event{type: :rank, taxon_id: id, old_rank: :genus, new_rank: :subgenus}}

      assert id == ctx.genus.id
      assert [_ | _] = changes_for("taxa")
    end

    test "refuses a rank not below the parent's", ctx do
      assert {:error, changeset} = Taxa.set_rank(test_actor(), ctx.genus, :family)
      assert {_, [validation: :rank_inversion]} = changeset.errors[:rank]
      assert Taxa.get_taxon!(ctx.genus.id).rank == :genus
    end

    test "refuses a rank not above a child's", ctx do
      assert {:error, changeset} = Taxa.set_rank(test_actor(), ctx.genus, :subspecies)
      assert {_, [validation: :rank_inversion]} = changeset.errors[:rank]
    end

    test "the same rank changes nothing", ctx do
      assert {:ok, _} = Taxa.set_rank(test_actor(), ctx.genus, :genus)
      refute_received {Recorder, _}
    end
  end

  describe "set_authorship/3 and set_sensu/3" do
    test "set the accepted name's, audited", ctx do
      assert {:ok, _} = Taxa.set_authorship(test_actor(), ctx.species, "(Ashmead, 1881)")
      assert {:ok, _} = Taxa.set_sensu(test_actor(), ctx.species, "Weld 1959")

      assert [%{status: :accepted, authorship: "(Ashmead, 1881)", sensu: "Weld 1959"}] =
               Taxa.get_taxon!(ctx.species.id).names

      assert [_ | _] = changes_for("taxon_names")
    end
  end

  describe "synonym events" do
    test "add_synonym emits :add_synonym and remove_synonym :remove_synonym", ctx do
      {:ok, synonym} = Taxa.add_synonym(test_actor(), ctx.species, "Cynips alba")
      assert_received {Recorder, %Event{type: :add_synonym, new_name: "Cynips alba"}}

      {:ok, _} = Taxa.remove_synonym(test_actor(), synonym)
      assert_received {Recorder, %Event{type: :remove_synonym, old_name: "Cynips alba"}}
    end
  end

  describe "split/3" do
    test "emits :split for daughters that exist as taxa", ctx do
      a = taxon_fixture(name: "Opsa beta", parent: ctx.genus)
      b = taxon_fixture(name: "Opsa gamma", parent: ctx.genus)

      assert {:ok, _} = Taxa.split(test_actor(), ctx.species, [b.id, a.id])

      assert_received {Recorder, %Event{type: :split, taxon_id: id, into_taxon_ids: into}}
      assert id == ctx.species.id
      assert Enum.sort(into) == Enum.sort([a.id, b.id])
    end

    test "refuses daughters that are not taxa, or fewer than two", ctx do
      a = taxon_fixture(name: "Opsa delta", parent: ctx.genus)
      assert {:error, :needs_two_daughters} = Taxa.split(test_actor(), ctx.species, [a.id])
      assert {:error, :not_found} = Taxa.split(test_actor(), ctx.species, [a.id, -1])
      refute_received {Recorder, %Event{type: :split}}
    end
  end

  describe "merge/3 (a lump)" do
    setup ctx do
      absorbed = taxon_fixture(rank: :species, name: "Opsa nigra", parent: ctx.genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), absorbed, "Cynips nigra")
      Process.delete(Recorder)
      %{absorbed: absorbed}
    end

    test "the absorbed taxon's names become the survivor's synonyms; it redirects", ctx do
      Process.put(Recorder, self())
      assert {:ok, survivor} = Taxa.merge(test_actor(), ctx.absorbed, ctx.species)

      assert Taxa.accepted_name(survivor) == "Opsa alba"
      assert Enum.map(Taxa.list_synonyms(survivor), & &1.name) == ["Opsa nigra", "Cynips nigra"]
      assert Taxa.get_taxon(ctx.absorbed.id) == nil
      assert Taxa.taxon_redirect(ctx.absorbed.id) == ctx.species.id

      assert_received {Recorder, %Event{type: :merge, taxon_id: a, into_taxon_id: s}}
      assert {a, s} == {ctx.absorbed.id, ctx.species.id}
    end

    test "act Facts naming it are re-pointed, keeping their Sources", ctx do
      paper = source_fixture("Weld", "1959")
      child = taxon_fixture(rank: :subspecies, name: "Opsa nigra minor", parent: ctx.genus)

      {:ok, %{fact: into}} =
        Taxa.assert_synonymy(
          test_actor(),
          %{name: "Cynips nigrella", accepted_taxon_id: ctx.absorbed.id},
          confirm(paper)
        )

      {:ok, %{fact: under}} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: child.id, parent_id: ctx.absorbed.id},
          confirm(paper)
        )

      {:ok, _} = Taxa.merge(test_actor(), ctx.absorbed, ctx.species)

      assert %SynonymyFact{accepted_taxon_id: s} =
               Repo.one!(from d in SynonymyFact, where: d.normalized_name == "cynips nigrella")

      assert s == ctx.species.id

      assert %PlacementFact{parent_id: ^s} =
               Repo.one!(from d in PlacementFact, where: d.taxon_id == ^child.id)

      for fact <- [into, under] do
        assert Repo.get(Facts.Fact, fact.id) == nil
      end

      assert Repo.aggregate(
               from(a in Attribution, where: a.source_id == ^paper.id),
               :count
             ) == 2
    end

    test "its own placement and name statements are kept as declined history", ctx do
      paper = source_fixture("Weld", "1959")
      other_family = taxon_fixture(rank: :family, name: "Elsidae", kingdom: "Animalia")
      other_genus = taxon_fixture(rank: :genus, name: "Elsa", parent: other_family)

      {:ok, %{attribution: placed}} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: ctx.absorbed.id, parent_id: other_genus.id},
          confirm(paper)
        )

      {:ok, _} = Facts.accept(test_actor(), placed.id)

      # The tree's own statement of it, by the legacy Source, goes with it.
      {:ok, %{attribution: legacy}} =
        Taxa.assert_name(
          test_actor(),
          %{taxon_id: ctx.absorbed.id, name: "Opsa nigra", rank: :species},
          confirm(Sources.get_legacy_data_source(), %{stated: nil})
        )

      {:ok, _} = Taxa.merge(test_actor(), ctx.absorbed, ctx.species)

      moved = Repo.get!(Attribution, placed.id)
      assert moved.declined_at && moved.decline_reason =~ "merged into Opsa alba"
      assert %PlacementFact{taxon_id: s} = Facts.get_fact!(moved.fact_id) |> placement_of()
      assert s == ctx.species.id
      assert Repo.get(Attribution, legacy.id) == nil

      # The survivor stays where the tree has it.
      assert Taxa.get_taxon!(ctx.species.id).parent_id == ctx.genus.id
    end

    test "refuses a taxon with taxa under it", ctx do
      taxon_fixture(rank: :subspecies, name: "Opsa nigra nigra", parent: ctx.absorbed)
      assert {:error, :has_children} = Taxa.merge(test_actor(), ctx.absorbed, ctx.species)
    end

    test "refuses merging a taxon into itself, or plants", ctx do
      assert {:error, :same_taxon} = Taxa.merge(test_actor(), ctx.species, ctx.species)

      plant = taxon_fixture(name: "Quercus ops", kingdom: "Plantae", origin: :powo)
      other = taxon_fixture(name: "Quercus opsa", kingdom: "Plantae", origin: :powo)
      assert {:error, :plant} = Taxa.merge(test_actor(), plant, other)
    end
  end

  defp placement_of(%Facts.Fact{id: id}), do: Repo.get_by!(PlacementFact, fact_id: id)
end
