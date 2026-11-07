defmodule Gallformers.Import.TaxonomicStatementsViewTest do
  @moduledoc """
  Showing taxonomic Facts (`f923` Task 10): a Source's taxonomic
  statements, each with its curator's mark (accepted: who and when;
  declined: who, when and why; awaiting a curator), as
  `Gallformers.Import.facts_for_source/1` gives them; and a taxon's
  position (`Gallformers.Import.taxonomic_position/1`): the Source its
  current placement and name come from, and the papers that disagree.

  Not async: loads the vocabularies.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Accounts
  alias Gallformers.Audit.Actor
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Sources
  alias Gallformers.Taxa

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        auth0_id: "auth0|statements-#{System.unique_integer([:positive])}",
        display_name: "Ada Curator"
      })

    :ok = put_test_actor(Actor.user(user.id, "Ada Curator"))
    :ok = audit_test_metadata(%{})
    load_vocab!()

    legacy = Sources.get_legacy_data_source()
    family = taxon_fixture(rank: :family, name: "Viewidae", kingdom: "Animalia")
    other = taxon_fixture(rank: :family, name: "Otherviewidae", kingdom: "Animalia")
    genus = taxon_fixture(rank: :genus, name: "Viewa", parent: family)

    for taxon <- [family, other, genus], do: legacy!(taxon, legacy)

    %{legacy: legacy, family: family, other: other, genus: genus, user: user}
  end

  defp legacy!(taxon, legacy) do
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

  defp placement!(taxon, parent, source, extra \\ %{}) do
    {:ok, %{attribution: attribution}} =
      Taxa.assert_placement(
        test_actor(),
        %{taxon_id: taxon.id, parent_id: parent.id},
        confirm(source, extra)
      )

    attribution
  end

  defp name!(taxon, name, source) do
    {:ok, %{attribution: attribution}} =
      Taxa.assert_name(
        test_actor(),
        %{taxon_id: taxon.id, name: name, rank: taxon.rank},
        confirm(source, %{status_as_written: "comb. nov."})
      )

    attribution
  end

  defp acts(source_id), do: Import.facts_for_source(source_id).taxonomy.acts

  describe "facts_for_source/1" do
    test "lists the Source's taxonomic statements, each with its mark", ctx do
      paper = source_fixture("Revision", "1990")
      moved = placement!(ctx.genus, ctx.other, paper)
      renamed = name!(ctx.genus, "Viewella", paper)
      {:ok, _} = Facts.accept(test_actor(), moved.id)
      {:ok, _} = Facts.decline(test_actor(), renamed.id, "A misspelling, not a new name")

      assert %{galls: [], taxonomy: %{new_taxa: [], acts: acts}} =
               Import.facts_for_source(paper.id)

      assert [placement, name] = Enum.sort_by(acts, & &1.fact_id)

      assert placement.kind == :placement
      assert placement.category == :taxonomy
      assert placement.value.taxon.taxon_id == ctx.genus.id
      assert placement.value.parent.name == "Otherviewidae"
      assert placement.standing == :current

      assert %{state: :accepted, by: "Ada Curator", at: %DateTime{}, reason: nil} =
               placement.decision

      assert name.kind == :name
      assert name.value.name == "Viewella"
      assert name.words.status_as_written == "comb. nov."
      assert name.standing == :unsupported

      assert %{
               state: :declined,
               by: "Ada Curator",
               at: %DateTime{},
               reason: "A misspelling, not a new name"
             } = name.decision
    end

    test "a statement no curator has decided awaits one", ctx do
      paper = source_fixture("Revision", "1990")
      placement!(ctx.genus, ctx.other, paper)

      assert [%{decision: %{state: :awaiting, by: nil, at: nil}}] = acts(paper.id)
    end

    test "Gallformers' own statements carry no mark", ctx do
      assert [_ | _] = legacy_acts = acts(ctx.legacy.id)
      assert Enum.reject(legacy_acts, &(&1.decision == nil)) == []
    end
  end

  describe "taxonomic_position/1" do
    test "credits the legacy data while no paper is accepted; lists papers awaiting", ctx do
      paper = source_fixture("Revision", "1990")
      placement!(ctx.genus, ctx.other, paper)

      position = Import.taxonomic_position(ctx.genus.id)

      assert position.placement.parent.taxon_id == ctx.family.id
      assert position.placement.source.source_id == ctx.legacy.id
      assert position.name.name == "Viewa"
      assert position.name.source.source_id == ctx.legacy.id

      assert [disagreeing] = position.disagreeing
      assert disagreeing.kind == :placement
      assert disagreeing.value.parent.taxon_id == ctx.other.id
      assert disagreeing.source.source_id == paper.id
      assert disagreeing.decision.state == :awaiting
    end

    test "credits the accepted paper; a declined one disagrees with its reason", ctx do
      followed = source_fixture("Revision", "1990")
      declined = source_fixture("Monograph", "2001")
      accepted = placement!(ctx.genus, ctx.other, followed)
      {:ok, _} = Facts.accept(test_actor(), accepted.id)
      refused = placement!(ctx.genus, ctx.family, declined)
      {:ok, _} = Facts.decline(test_actor(), refused.id, "Not followed")

      position = Import.taxonomic_position(ctx.genus.id)

      assert position.placement.parent.taxon_id == ctx.other.id
      assert position.placement.source.source_id == followed.id
      assert position.placement.source.name =~ "Weld"

      assert [%{source: %{source_id: id}, decision: %{state: :declined, reason: "Not followed"}}] =
               position.disagreeing

      assert id == declined.id
    end

    test "an agreeing paper awaiting a curator is not a disagreement", ctx do
      paper = source_fixture("Revision", "1990")
      placement!(ctx.genus, ctx.family, paper)

      assert Import.taxonomic_position(ctx.genus.id).disagreeing == []
    end

    test "a taxon no Fact places or names has no position" do
      lone = taxon_fixture(rank: :genus, name: "Lonea", kingdom: "Animalia")

      assert %{placement: nil, name: nil, disagreeing: []} = Import.taxonomic_position(lone.id)
    end
  end

  describe "taxon_splits/1" do
    setup ctx do
      species = taxon_fixture(name: "Viewa alba", parent: ctx.genus)
      a = taxon_fixture(name: "Viewa beta", parent: ctx.genus)
      b = taxon_fixture(name: "Viewa gamma", parent: ctx.genus)
      %{species: species, a: a, b: b}
    end

    defp split!(taxon, into, source) do
      key = %{taxon_id: taxon.id, into_taxon_ids: Enum.map(into, & &1.id)}
      {:ok, %{attribution: attribution}} = Taxa.assert_split(test_actor(), key, confirm(source))
      attribution
    end

    test "an accepted split, from the split taxon and from each daughter, with its Source",
         ctx do
      paper = source_fixture("Revision", "1990")
      {:ok, _} = Facts.accept(test_actor(), split!(ctx.species, [ctx.a, ctx.b], paper).id)

      assert [split] = Import.taxon_splits(ctx.species.id)
      assert split.taxon.taxon_id == ctx.species.id
      assert Enum.map(split.into, & &1.name) |> Enum.sort() == ["Viewa beta", "Viewa gamma"]
      assert split.source.source_id == paper.id
      assert split.source.name =~ "Weld"

      assert [from_a] = Import.taxon_splits(ctx.a.id)
      assert from_a.taxon.name == "Viewa alba"
    end

    test "a split awaiting a curator is not history (it disagrees)", ctx do
      split!(ctx.species, [ctx.a, ctx.b], source_fixture("Revision", "1990"))

      assert Import.taxon_splits(ctx.species.id) == []
      assert [%{kind: :split}] = Import.taxonomic_position(ctx.species.id).disagreeing
    end
  end
end
