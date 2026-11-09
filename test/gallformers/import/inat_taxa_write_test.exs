defmodule Gallformers.Import.InatTaxaWriteTest do
  @moduledoc """
  Bringing an iNaturalist taxon in (matter `cb28` Task 4,
  `Gallformers.Import.record_inat_taxon/3`), all of it or nothing, every
  edit in the replay log:

    * a plant is edited directly, as plants are: each taxon added marked
      `:inaturalist`, the moves, names and authorship editorial, no
      statements;
    * any other taxon's placements, names, synonyms and common names are the
      day's iNaturalist Source's statements, accepted by the curator;
    * every taxon added or matched keeps its iNaturalist ID, so a second
      import of the same taxon matches it and adds nothing twice.

  Not async: the day's iNaturalist Source has a unique title, and the
  replay log is read whole.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures, only: [plant_fixture: 1]
  import Gallformers.INaturalistFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Accounts
  alias Gallformers.Audit.Actor
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.Replay
  alias Gallformers.Sources
  alias Gallformers.Sources.Source
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Sync

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        auth0_id: "auth0|inat-#{System.unique_integer([:positive])}",
        display_name: "Cora Curator"
      })

    actor = Actor.user(user.id, "Cora Curator")
    :ok = put_test_actor(actor)
    Repo.query!("DELETE FROM replay_log")
    %{actor: actor, user: user}
  end

  defp rubus_tree do
    rosaceae = plant_fixture(rank: :family, name: "Rosaceae")
    rubus = plant_fixture(rank: :genus, name: "Rubus", parent: rosaceae)
    frondosus = plant_fixture(name: "Rubus frondosus", parent: rubus)
    %{rosaceae: rosaceae, rubus: rubus, frondosus: frondosus}
  end

  defp key_of(rows, name, rank), do: Enum.find(rows, &(&1.name == name and &1.rank == rank)).key

  defp choices(plan, extra \\ [], opts \\ []) do
    %{
      ticked: Enum.reduce(extra, plan.ticked, &MapSet.put(&2, &1)),
      rank: opts[:rank],
      authorship: opts[:authorship] || %{}
    }
  end

  defp find(name, rank, kingdom) do
    {:ok, taxon} = Taxa.resolve_name(name, rank: rank, kingdom: kingdom)
    Taxa.get_taxon!(taxon.id)
  end

  defp kinds, do: Enum.map(Import.list_replay_entries(), & &1.kind)

  describe "a plant: Arguti" do
    setup do
      tree = rubus_tree()
      plan = Import.plan_inat_taxon(inat_taxon(1_449_402), "Rubus pensilvanicus")
      Map.put(tree, :plan, plan)
    end

    test "adds what is ticked, directly, marked as from iNaturalist, with iNaturalist IDs", ctx do
      %{plan: plan} = ctx
      argutus = key_of(plan.children, "Rubus argutus", "species")
      frondosus = key_of(plan.children, "Rubus frondosus", "species")

      choices =
        choices(plan, [argutus, frondosus], authorship: %{"t" => "Focke", argutus => "Bailey"})

      assert {:ok, %{taxon_id: arguti_id, added: 3, moved: 1}} =
               Import.record_inat_taxon(ctx.actor, plan, choices)

      subgenus = find("Rubus", :subgenus, "Plantae")
      arguti = Taxa.get_taxon!(arguti_id)

      assert subgenus.parent_id == ctx.rubus.id
      assert subgenus.origin == :inaturalist
      assert Taxa.inat_id(subgenus) == 1_360_636

      assert Taxa.accepted_name(arguti) == "Arguti"
      assert arguti.rank == :section
      assert arguti.parent_id == subgenus.id
      assert arguti.origin == :inaturalist
      assert Taxa.inat_id(arguti) == 1_449_402
      assert Enum.find(arguti.names, &(&1.status == :accepted)).authorship == "Focke"

      assert Taxa.get_taxon!(ctx.frondosus.id).parent_id == arguti.id
      assert Taxa.inat_id(ctx.frondosus) == 168_056

      argutus = find("Rubus argutus", :species, "Plantae")
      assert argutus.parent_id == arguti.id
      assert argutus.origin == :inaturalist
      assert Enum.find(argutus.names, &(&1.status == :accepted)).authorship == "Bailey"

      assert Enum.map(Taxa.list_synonyms(arguti), & &1.name) == ["Rubus pensilvanicus"]

      assert Enum.map(Taxa.list_common_names(arguti), & &1.name) == [
               "Field Highbush Blackberries"
             ]

      # The ranks we hold, matched by name, linked too.
      assert Taxa.inat_id(ctx.rosaceae) == 47_148
      assert Taxa.inat_id(ctx.rubus) == 47_544

      # Plants: no statements, no iNaturalist Source.
      refute :taxonomic_statement in kinds()
      assert Sources.inaturalist_source(Date.utc_today()) == nil
    end

    test "replays to the same tree", ctx do
      %{plan: plan} = ctx
      argutus = key_of(plan.children, "Rubus argutus", "species")

      {:ok, %{taxon_id: arguti_id}} =
        Import.record_inat_taxon(ctx.actor, plan, choices(plan, [argutus]))

      entries = Import.list_replay_entries()

      # As after the cutover: the tree without them.
      argutus_taxon = find("Rubus argutus", :species, "Plantae")
      subgenus = find("Rubus", :subgenus, "Plantae")

      for t <- [argutus_taxon.id, arguti_id, subgenus.id],
          do: {:ok, _} = Taxa.delete_taxon(ctx.actor, t)

      Repo.query!("DELETE FROM taxon_inaturalist")

      assert {:ok, n} = Replay.run(entries, actor: ctx.actor)
      assert n == length(entries)

      arguti = find("Arguti", :section, "Plantae")
      assert arguti.origin == :inaturalist
      assert Taxa.inat_id(arguti) == 1_449_402
      assert find("Rubus argutus", :species, "Plantae").parent_id == arguti.id
      assert Taxa.inat_id(ctx.rubus) == 47_544

      Gallformers.ImportFixtures.assert_replays_again(entries, ctx.actor)
    end

    test "a second import of the same taxon matches it and adds nothing twice", ctx do
      %{plan: plan} = ctx
      {:ok, first} = Import.record_inat_taxon(ctx.actor, plan, choices(plan))
      logged = length(Import.list_replay_entries())

      again = Import.plan_inat_taxon(inat_taxon(1_449_402), "Rubus pensilvanicus")
      assert again.held.id == first.taxon_id
      assert {"Rubus", :held} in Enum.map(again.lineage, &{&1.name, &1.state})
      refute Enum.any?(again.synonyms, &(&1.name == "Rubus pensilvanicus"))

      assert {:ok, %{taxon_id: id, added: 0, moved: 0}} =
               Import.record_inat_taxon(ctx.actor, again, choices(again))

      assert id == first.taxon_id
      assert length(Import.list_replay_entries()) == logged
    end

    test "unticking a needed rank attaches it to the nearest one ticked or held", ctx do
      %{plan: plan} = ctx
      subgenus = key_of(plan.lineage, "Rubus", "subgenus")
      rosoideae = key_of(plan.lineage, "Rosoideae", "subfamily")
      ticked = plan.ticked |> MapSet.delete(subgenus) |> MapSet.put(rosoideae)

      assert {:ok, %{taxon_id: id, added: 2}} =
               Import.record_inat_taxon(ctx.actor, plan, %{choices(plan) | ticked: ticked})

      assert Taxa.get_taxon!(id).parent_id == ctx.rubus.id
      assert find("Rosoideae", :subfamily, "Plantae").parent_id == ctx.rosaceae.id
      # A rank added above one we hold leaves that one where it is.
      assert Taxa.get_taxon!(ctx.rubus.id).parent_id == ctx.rosaceae.id
    end
  end

  describe "a rank we don't use: Alleghenienses" do
    test "is added at the rank the curator picks; none picked is refused" do
      tree = rubus_tree()
      plan = Import.plan_inat_taxon(inat_taxon(1_449_411), nil)
      section = key_of(plan.lineage, "Rubus", "section")
      ticked = MapSet.delete(plan.ticked, section)

      assert {:error, :rank_required} =
               Import.record_inat_taxon(test_actor(), plan, %{choices(plan) | ticked: ticked})

      assert {:ok, %{taxon_id: id}} =
               Import.record_inat_taxon(test_actor(), plan, %{
                 choices(plan, [], rank: :section)
                 | ticked: ticked
               })

      taxon = Taxa.get_taxon!(id)
      assert taxon.rank == :section
      assert Taxa.get_taxon!(taxon.parent_id).rank == :subgenus
      assert Taxa.get_taxon!(taxon.parent_id).parent_id == tree.rubus.id
    end

    test "all or nothing: a rank the tree refuses leaves nothing behind" do
      rubus_tree()
      plan = Import.plan_inat_taxon(inat_taxon(1_449_411), nil)
      before = length(Import.list_replay_entries())

      # A genus can't go under the section it needs.
      assert {:error, _reason} =
               Import.record_inat_taxon(test_actor(), plan, choices(plan, [], rank: :genus))

      assert Taxa.resolve_name("Alleghenienses") == :none
      assert Taxa.resolve_name("Rubus", rank: :subgenus) == :none
      assert length(Import.list_replay_entries()) == before
    end
  end

  describe "an animal: Syrphidae" do
    setup %{actor: actor} do
      # An order we hold, from the tree's own (legacy) data.
      legacy = Sources.get_legacy_data_source()
      diptera = taxon_fixture(rank: :order, name: "Diptera", kingdom: "Animalia")
      elsewhere = taxon_fixture(rank: :family, name: "Elsewhereidae", kingdom: "Animalia")
      pipizinae = taxon_fixture(rank: :subfamily, name: "Pipizinae", parent: elsewhere)

      for t <- [diptera, elsewhere, pipizinae] do
        t = Taxa.get_taxon!(t.id)
        attribution = %{source_id: legacy.id, stance: :confirm, stated: nil}

        {:ok, _} =
          Taxa.assert_placement(actor, %{taxon_id: t.id, parent_id: t.parent_id}, attribution)

        name = %{taxon_id: t.id, name: Taxa.accepted_name(t), rank: t.rank}
        {:ok, _} = Taxa.assert_name(actor, name, attribution)
      end

      plan = Import.plan_inat_taxon(inat_taxon(49_995), "Syrphidae")
      %{diptera: diptera, pipizinae: pipizinae, plan: plan}
    end

    test "each placement and name is the day's iNaturalist statement, accepted by the curator",
         ctx do
      %{plan: plan} = ctx
      syrphinae = key_of(plan.children, "Syrphinae", "subfamily")
      pipizinae = key_of(plan.children, "Pipizinae", "subfamily")
      assert Enum.find(plan.children, &(&1.key == pipizinae)).state == :move

      # Brachycera and Cyclorrhapha (needed), Syrphidae, Syrphinae.
      assert {:ok, %{taxon_id: id, added: 4, moved: 1}} =
               Import.record_inat_taxon(
                 ctx.actor,
                 plan,
                 choices(plan, [syrphinae, pipizinae], authorship: %{"t" => "Latreille, 1802"})
               )

      assert %Source{} = source = Sources.inaturalist_source(Date.utc_today())

      syrphidae = Taxa.get_taxon!(id)
      assert syrphidae.origin == :curated
      assert syrphidae.kingdom == "Animalia"
      assert Taxa.inat_id(syrphidae) == 49_995
      assert Enum.find(syrphidae.names, &(&1.status == :accepted)).authorship == "Latreille, 1802"

      # Brachycera and Cyclorrhapha were needed between Diptera and it.
      cyclorrhapha = Taxa.get_taxon!(syrphidae.parent_id)
      assert Taxa.accepted_name(cyclorrhapha) == "Cyclorrhapha"
      brachycera = Taxa.get_taxon!(cyclorrhapha.parent_id)
      assert Taxa.accepted_name(brachycera) == "Brachycera"
      assert brachycera.parent_id == ctx.diptera.id

      assert Taxa.get_taxon!(ctx.pipizinae.id).parent_id == syrphidae.id
      assert find("Syrphinae", :subfamily, "Animalia").parent_id == syrphidae.id
      assert Enum.map(Taxa.list_common_names(syrphidae), & &1.name) == ["Hover Flies"]

      # Credited to the day's iNaturalist Source, accepted by the curator.
      {:ok, fact_id} =
        Taxa.find_act_fact(:placement, %{taxon_id: ctx.pipizinae.id, parent_id: syrphidae.id})

      statement = Facts.get_attribution(fact_id, source.id)
      assert statement.stance == :confirm
      assert statement.stated_on == Date.utc_today()
      assert statement.accepted_by_user_id == ctx.user.id
      assert Facts.get_fact!(fact_id).standing == :current

      assert :taxonomic_statement in kinds()
      assert :taxonomic_decision in kinds()
      assert hd(kinds()) == :source_edit
      assert Sync.check() |> Enum.filter(&(&1.taxon_id == id)) == []
    end

    test "a needed rank unticked: it goes under the one we hold", ctx do
      %{plan: plan} = ctx
      ticked = for k <- plan.ticked, not String.starts_with?(k, "a"), into: MapSet.new(), do: k

      assert {:ok, %{taxon_id: id, added: 1}} =
               Import.record_inat_taxon(ctx.actor, plan, %{choices(plan) | ticked: ticked})

      assert Taxa.get_taxon!(id).parent_id == ctx.diptera.id
    end
  end

  test "an animal with nothing held above it goes in at the top", %{actor: actor} do
    plan = Import.plan_inat_taxon(inat_taxon(49_995), "Syrphidae")
    refute plan.held_any?

    assert {:ok, %{taxon_id: id, added: 1}} = Import.record_inat_taxon(actor, plan, choices(plan))
    assert Taxa.get_taxon!(id).parent_id == nil
    assert Taxa.get_taxon!(id).kingdom == "Animalia"
  end

  test "an inactive taxon is refused: bring in the one that replaced it" do
    plan = Import.plan_inat_taxon(inat_taxon(78_894), "Rubus pensilvanicus")
    assert {:error, :inactive} = Import.record_inat_taxon(test_actor(), plan, choices(plan))
  end
end
