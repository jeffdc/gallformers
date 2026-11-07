defmodule Gallformers.Import.TaxonomyStatementsTest do
  @moduledoc """
  The taxonomy admin's non-plant edits credited to the Source they follow
  (matter `f923` Task 8, "The taxonomy admin no longer edits non-plant
  taxa directly"): a move, a name (rename, rank, authorship), a synonym or
  common name added or removed, a new taxon — each is recorded as that
  Source's taxonomic statement, dated by the Source, and accepted at once
  by the curator, so the tree follows it. An edit an accepted newer paper
  outranks changes nothing and says why. A new citation is created as a
  Source on the spot (audited, logged). "No Source" is a Gallformers
  statement with a reason. The statements and acceptances replay; plants
  keep their direct edits.

  Not async: import packages create the Source "T" (titles are unique).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures, only: [source_fixture: 2, confirm: 1, plant_fixture: 1]
  import Gallformers.ImportFixtures
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
        auth0_id: "auth0|statements-#{System.unique_integer([:positive])}",
        display_name: "Cora Curator"
      })

    actor = Actor.user(user.id, "Cora Curator")
    :ok = put_test_actor(actor)

    legacy = Sources.get_legacy_data_source()
    family = taxon_fixture(rank: :family, name: "Basisidae", kingdom: "Animalia")
    other = taxon_fixture(rank: :family, name: "Otherbasisidae", kingdom: "Animalia")
    genus = taxon_fixture(rank: :genus, name: "Basa", parent: family)
    species = taxon_fixture(name: "Basa alba", parent: genus)
    for taxon <- [family, other, genus, species], do: legacy!(taxon, legacy)

    %{
      actor: actor,
      user: user,
      weld: source_fixture("Weld", "1959"),
      family: family,
      other: other,
      genus: genus,
      species: species
    }
  end

  # The tree's own statements of `taxon`, as the cutover makes them.
  defp legacy!(taxon, legacy) do
    taxon = Taxa.get_taxon!(taxon.id)
    attribution = %{source_id: legacy.id, stance: :confirm, stated: nil}
    key = %{taxon_id: taxon.id, parent_id: taxon.parent_id}
    {:ok, _} = Taxa.assert_placement(test_actor(), key, attribution)
    name = %{taxon_id: taxon.id, name: Taxa.accepted_name(taxon), rank: taxon.rank}
    {:ok, _} = Taxa.assert_name(test_actor(), name, attribution)
  end

  defp parent_id(taxon), do: Taxa.get_taxon!(taxon.id).parent_id

  defp kinds, do: Enum.map(Import.list_replay_entries(), & &1.kind)

  defp placement_attribution(taxon, parent, source) do
    {:ok, fact_id} =
      Taxa.find_act_fact(:placement, %{taxon_id: taxon.id, parent_id: parent && parent.id})

    fact_id && Facts.get_attribution(fact_id, source.id)
  end

  defp for_taxa(differences, taxa) do
    ids = Enum.map(taxa, & &1.id)
    Enum.filter(differences, &(&1.taxon_id in ids))
  end

  describe "a change credited to a Source" do
    test "a move is the Source's placement statement, accepted, and the tree follows", ctx do
      assert {:ok, _} =
               Import.record_taxonomy_change(
                 ctx.actor,
                 {:source, ctx.weld.id},
                 {:place, ctx.genus.id, ctx.other.id}
               )

      assert parent_id(ctx.genus) == ctx.other.id

      statement = placement_attribution(ctx.genus, ctx.other, ctx.weld)
      assert statement.stance == :confirm
      assert statement.stated_on == ~D[1959-01-01]
      assert statement.stated_precision == :year
      assert %DateTime{} = statement.accepted_at
      assert statement.accepted_by_user_id == ctx.user.id
      assert Facts.get_fact!(statement.fact_id).standing == :current

      assert kinds() == [:taxonomic_statement, :taxonomic_decision]
      assert Sync.check() |> for_taxa([ctx.genus]) == []
    end

    test "a name gives the accepted name, rank and authorship; the old name stays a synonym",
         ctx do
      assert {:ok, _} =
               Import.record_taxonomy_change(
                 ctx.actor,
                 {:source, ctx.weld.id},
                 {:name, ctx.species.id,
                  %{name: "Basa albida", rank: :species, authorship: "(Weld, 1959)"}}
               )

      species = Taxa.get_taxon!(ctx.species.id)
      assert Taxa.accepted_name(species) == "Basa albida"

      assert [%{authorship: "(Weld, 1959)"}] =
               Enum.filter(species.names, &(&1.status == :accepted))

      assert "Basa alba" in Enum.map(Taxa.list_synonyms(species), & &1.name)
      assert Sync.check() |> for_taxa([ctx.species]) == []
    end

    test "adding a synonym or common name confirms it; removing one denies it", ctx do
      basis = {:source, ctx.weld.id}

      {:ok, _} =
        Import.record_taxonomy_change(
          ctx.actor,
          basis,
          {:add_synonym, ctx.species.id, "Basa nigra"}
        )

      [synonym] = Taxa.list_synonyms(ctx.species)
      assert synonym.name == "Basa nigra"

      {:ok, _} =
        Import.record_taxonomy_change(
          ctx.actor,
          basis,
          {:add_common_name, ctx.species.id, "white basa"}
        )

      [common] = Taxa.list_common_names(ctx.species)
      assert common.name == "white basa"
      assert Sync.check() |> for_taxa([ctx.species]) == []

      {:ok, _} = Import.record_taxonomy_change(ctx.actor, basis, {:remove_synonym, synonym.id})
      {:ok, _} = Import.record_taxonomy_change(ctx.actor, basis, {:remove_common_name, common.id})

      assert Taxa.list_synonyms(ctx.species) == []
      assert Taxa.list_common_names(ctx.species) == []
      assert Sync.check() |> for_taxa([ctx.species]) == []

      stances =
        for e <- Import.list_replay_entries(),
            e.kind == :taxonomic_statement,
            do: {e.key["kind"], e.payload["stance"]}

      assert stances == [
               {"synonymy", "confirm"},
               {"common_name", "confirm"},
               {"synonymy", "deny"},
               {"common_name", "deny"}
             ]
    end

    test "creating a taxon records its placement and name as the Source's statements", ctx do
      attrs = %{name: "Basa nova", rank: :species, parent_id: ctx.genus.id, kingdom: "Animalia"}

      assert {:ok, %Taxa.Taxon{} = nova} =
               Import.record_taxonomy_change(
                 ctx.actor,
                 {:source, ctx.weld.id},
                 {:create_taxon, attrs, []}
               )

      assert Taxa.accepted_name(nova) == "Basa nova"
      assert nova.parent_id == ctx.genus.id
      assert %{accepted_at: %DateTime{}} = placement_attribution(nova, ctx.genus, ctx.weld)
      assert Sync.check() |> for_taxa([nova]) == []

      assert kinds() == [
               :taxonomy_edit,
               :taxonomic_statement,
               :taxonomic_decision,
               :taxonomic_statement,
               :taxonomic_decision
             ]
    end

    test "an intermediate rank created over existing taxa moves them by the Source's word",
         ctx do
      attrs = %{name: "Basini", rank: :tribe, parent_id: ctx.family.id, kingdom: "Animalia"}

      {:ok, tribe} =
        Import.record_taxonomy_change(
          ctx.actor,
          {:source, ctx.weld.id},
          {:create_taxon, attrs, [ctx.genus.id]}
        )

      assert parent_id(ctx.genus) == tribe.id
      assert Sync.check() |> for_taxa([tribe, ctx.genus]) == []
    end

    test "several taxa moved at once are each the Source's placement statement", ctx do
      sister = taxon_fixture(rank: :genus, name: "Basella", parent: ctx.family)
      legacy!(sister, Sources.get_legacy_data_source())

      assert {:ok, 2} =
               Import.record_taxonomy_change(
                 ctx.actor,
                 {:source, ctx.weld.id},
                 {:move_all, [ctx.genus.id, sister.id], ctx.other.id}
               )

      assert parent_id(ctx.genus) == ctx.other.id
      assert parent_id(sister) == ctx.other.id
      assert %{accepted_at: %DateTime{}} = placement_attribution(sister, ctx.other, ctx.weld)
    end
  end

  describe "an edit the tree won't follow" do
    test "an accepted newer paper's placement outranks it: nothing changes, and it says why",
         ctx do
      newer = source_fixture("Revision", "2019")

      {:ok, %{attribution: accepted}} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: ctx.genus.id, parent_id: ctx.other.id},
          confirm(newer)
        )

      {:ok, _} = Facts.accept(test_actor(), accepted.id)
      assert parent_id(ctx.genus) == ctx.other.id

      older = source_fixture("Older", "2008")

      assert {:error, {:outranked, message}} =
               Import.record_taxonomy_change(
                 ctx.actor,
                 {:source, older.id},
                 {:place, ctx.genus.id, ctx.family.id}
               )

      assert message =~ "2019"
      assert message =~ "2008"
      assert message =~ "Otherbasisidae"
      assert message =~ "won't change the tree"

      assert parent_id(ctx.genus) == ctx.other.id
      assert placement_attribution(ctx.genus, ctx.family, older) == nil
      assert Import.list_replay_entries() == []
    end

    test "a newer paper denying a synonym outranks an older one adding it", ctx do
      newer = source_fixture("Revision", "2019")

      {:ok, %{attribution: denial}} =
        Taxa.assert_synonymy(
          test_actor(),
          %{name: "Basa nigra", accepted_taxon_id: ctx.species.id},
          %{source_id: newer.id, stance: :deny}
        )

      {:ok, _} = Facts.accept(test_actor(), denial.id)

      assert {:error, {:outranked, message}} =
               Import.record_taxonomy_change(
                 ctx.actor,
                 {:source, ctx.weld.id},
                 {:add_synonym, ctx.species.id, "Basa nigra"}
               )

      assert message =~ "2019"
      assert Taxa.list_synonyms(ctx.species) == []
    end

    test "a Source with no date, a retracted one or Gallformers' own can't be the basis", ctx do
      {:ok, undated} =
        Sources.create_source(%{
          title: "Undated #{System.unique_integer([:positive])}",
          author: "Anon",
          pubyear: "1900",
          citation: "Anon.",
          license: "All Rights Reserved"
        })

      move = {:place, ctx.genus.id, ctx.other.id}

      assert {:error, :undated_source} =
               Import.record_taxonomy_change(ctx.actor, {:source, undated.id}, move)

      notice = source_fixture("Notice", "2001")
      {:ok, _} = Sources.retract_source(test_actor(), ctx.weld, notice, ~D[2001-01-01])

      assert {:error, :retracted_source} =
               Import.record_taxonomy_change(ctx.actor, {:source, ctx.weld.id}, move)

      legacy = Sources.get_legacy_data_source()

      assert {:error, :own_source} =
               Import.record_taxonomy_change(ctx.actor, {:source, legacy.id}, move)

      assert parent_id(ctx.genus) == ctx.family.id
    end
  end

  describe "a new citation" do
    test "is created as a Source, logged, and the change is credited to it", ctx do
      title = "A revision of Basa #{System.unique_integer([:positive])}"

      citation = %{
        title: title,
        authors: ["Smith, J.", "Jones, K."],
        authored: "2008-05",
        doi: "10.1234/basa"
      }

      assert {:ok, _} =
               Import.record_taxonomy_change(
                 ctx.actor,
                 {:citation, citation},
                 {:place, ctx.genus.id, ctx.other.id}
               )

      source = Sources.get_source_by_title(title)

      assert %Source{
               kind: :publication,
               authors: ["Smith, J.", "Jones, K."],
               author: "Smith, J.; Jones, K.",
               pubyear: "2008",
               authored_date: ~D[2008-05-01],
               authored_precision: :month,
               doi: "10.1234/basa"
             } = source

      assert source.citation =~ title
      assert parent_id(ctx.genus) == ctx.other.id
      assert %{stated_on: ~D[2008-05-01]} = placement_attribution(ctx.genus, ctx.other, source)

      assert [%{kind: :source_edit, key: %{"op" => "create"}, payload: %{"attrs" => attrs}} | _] =
               Import.list_replay_entries()

      assert attrs == %{
               "title" => title,
               "authors" => ["Smith, J.", "Jones, K."],
               "authored" => "2008-05",
               "doi" => "10.1234/basa"
             }
    end

    test "needs a title, authors and a date; a bad one writes nothing", ctx do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Import.record_taxonomy_change(
                 ctx.actor,
                 {:citation, %{title: "", authors: [], authored: "05/2008"}},
                 {:place, ctx.genus.id, ctx.other.id}
               )

      assert %{
               title: ["can't be blank"],
               authors: ["can't be blank"],
               authored: ["must be YYYY, YYYY-MM or YYYY-MM-DD"]
             } = errors_on(changeset)

      assert parent_id(ctx.genus) == ctx.family.id
      assert Import.list_replay_entries() == []
    end
  end

  describe "no Source: Gallformers' own position" do
    test "needs a reason", ctx do
      move = {:place, ctx.genus.id, ctx.other.id}

      assert {:error, :reason_required} =
               Import.record_taxonomy_change(ctx.actor, {:gallformers, "  "}, move)

      assert parent_id(ctx.genus) == ctx.family.id
    end

    test "is a Gallformers statement with the reason, dated today, counting at once", ctx do
      reason = "No paper places Basa yet; it is closest to Otherbasisidae."

      assert {:ok, _} =
               Import.record_taxonomy_change(
                 ctx.actor,
                 {:gallformers, reason},
                 {:place, ctx.genus.id, ctx.other.id}
               )

      assert parent_id(ctx.genus) == ctx.other.id

      statement =
        placement_attribution(ctx.genus, ctx.other, Sources.get_gallformers_source())

      assert statement.statement_text == reason
      assert statement.stated_on == Date.utc_today()
      assert statement.accepted_at == nil

      assert [%{kind: :taxonomic_statement, payload: payload}] = Import.list_replay_entries()
      assert payload["statement_text"] == reason
      assert payload["stated"] == Date.to_iso8601(Date.utc_today())
    end
  end

  test "plants keep their direct edits: a credited change to one is refused", ctx do
    plant = plant_fixture(name: "Quercus basa")

    assert {:error, :plant} =
             Import.record_taxonomy_change(
               ctx.actor,
               {:source, ctx.weld.id},
               {:add_synonym, plant.id, "Quercus basoides"}
             )

    assert Taxa.list_synonyms(plant) == []
  end

  describe "replay" do
    test "replays the citation, the statement and its acceptance", ctx do
      title = "Replayed revision #{System.unique_integer([:positive])}"
      citation = %{title: title, authors: ["Smith, J."], authored: "2008"}

      {:ok, _} =
        Import.record_taxonomy_change(
          ctx.actor,
          {:citation, citation},
          {:place, ctx.genus.id, ctx.other.id}
        )

      entries = Import.list_replay_entries()

      assert Enum.map(entries, & &1.kind) == [
               :source_edit,
               :taxonomic_statement,
               :taxonomic_decision
             ]

      # As after the cutover: the citation and its statement not yet made.
      source = Sources.get_source_by_title(title)

      {:ok, _} =
        Facts.remove_attribution(
          test_actor(),
          placement_attribution(ctx.genus, ctx.other, source).fact_id,
          source.id
        )

      Repo.delete!(source)
      assert parent_id(ctx.genus) == ctx.family.id

      assert {:ok, 3} = Replay.run(entries, actor: ctx.actor)
      assert_replays_again(entries, ctx.actor)

      source = Sources.get_source_by_title(title)
      assert %{accepted_at: %DateTime{}} = placement_attribution(ctx.genus, ctx.other, source)
      assert parent_id(ctx.genus) == ctx.other.id
    end

    test "replaying a statement already made changes nothing", ctx do
      {:ok, _} =
        Import.record_taxonomy_change(
          ctx.actor,
          {:gallformers, "No paper places it."},
          {:place, ctx.genus.id, ctx.other.id}
        )

      [entry] = Import.list_replay_entries()
      assert {:ok, 1} = Replay.run([entry], actor: ctx.actor)
      assert_replays_again([entry], ctx.actor)
      assert parent_id(ctx.genus) == ctx.other.id
    end
  end

  describe "a later import of the same Source" do
    setup ctx do
      # The paper's own Source, made by importing it once.
      first =
        taxonomy_batch()
        |> unique_batch_id()
        |> Map.put("taxa", [
          %{"ref" => "t1", "name_as_written" => "Basa alba", "rank" => "species"}
        ])
        |> Map.put("acts", [act("a1", "name", %{"taxon" => "t1"})])

      package = package(gall: nil, taxonomy: first) |> with_review() |> deliver!()
      {:ok, package} = Import.approve_package(test_actor(), package)
      assert package.status == :approved

      Map.put(ctx, :paper, Sources.get_source!(package.source_id))
    end

    defp act(id, kind, fields) do
      Map.merge(
        %{
          "id" => id,
          "stance" => "confirm",
          "kind" => kind,
          "evidence" => [%{"item" => "#/texts/1", "quote" => "Andricus quercuscalifornicus"}]
        },
        fields
      )
    end

    defp placement_batch(acts) do
      taxonomy_batch()
      |> unique_batch_id()
      |> Map.put("taxa", [
        %{"ref" => "t1", "name_as_written" => "Basa", "rank" => "genus"},
        %{"ref" => "t2", "name_as_written" => "Otherbasisidae", "rank" => "family"}
      ])
      |> Map.put("acts", acts)
    end

    test "restating the act raises no question and keeps the curator's acceptance", ctx do
      {:ok, _} =
        Import.record_taxonomy_change(
          ctx.actor,
          {:source, ctx.paper.id},
          {:place, ctx.genus.id, ctx.other.id}
        )

      statement = placement_attribution(ctx.genus, ctx.other, ctx.paper)

      again = placement_batch([act("a1", "placement", %{"taxon" => "t1", "parent" => "t2"})])
      package = package(gall: nil, taxonomy: again) |> with_review() |> deliver!()
      assert package.source_id in [nil, ctx.paper.id]
      {:ok, package} = Import.approve_package(test_actor(), package)
      assert package.source_id == ctx.paper.id

      assert Import.list_queue_items(package) == []
      restated = placement_attribution(ctx.genus, ctx.other, ctx.paper)
      assert restated.id == statement.id
      assert restated.accepted_at == statement.accepted_at
      assert parent_id(ctx.genus) == ctx.other.id
    end

    test "a re-import that doesn't restate it keeps the curator's statement", ctx do
      {:ok, _} =
        Import.record_taxonomy_change(
          ctx.actor,
          {:source, ctx.paper.id},
          {:place, ctx.genus.id, ctx.other.id}
        )

      silent = placement_batch([act("a1", "name", %{"taxon" => "t1"})])
      package = package(gall: nil, taxonomy: silent) |> with_review() |> deliver!()
      {:ok, package} = Import.approve_package(test_actor(), package)
      assert package.status == :approved

      assert %{accepted_at: %DateTime{}} = placement_attribution(ctx.genus, ctx.other, ctx.paper)
      assert parent_id(ctx.genus) == ctx.other.id
    end
  end
end
