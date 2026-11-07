defmodule Gallformers.Import.TaxonomicDecisionsTest do
  @moduledoc """
  A curator's acceptance, decline or reopening of a Source's taxonomic
  statement (`f923` Task 1) is audited and logged for replay by stable
  references (the Source's title, the act's taxa by name), and replaying the
  log makes the same decision again.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures, only: [source_fixture: 2, confirm: 1]
  import Gallformers.TaxaFixtures

  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Import
  alias Gallformers.Import.Replay
  alias Gallformers.Import.ReplayEntry
  alias Gallformers.Taxa

  setup do
    family = taxon_fixture(rank: :family, name: "Cynipidae Decisions", kingdom: "Animalia")
    other = taxon_fixture(rank: :family, name: "Figitidae Decisions", kingdom: "Animalia")
    genus = taxon_fixture(rank: :genus, name: "Andricus Decisions", parent: family)
    paper = source_fixture("Revision", "1990")

    {:ok, %{attribution: statement, fact: fact}} =
      Taxa.assert_placement(
        test_actor(),
        %{taxon_id: genus.id, parent_id: other.id},
        confirm(paper)
      )

    %{genus: genus, other: other, paper: paper, statement: statement, fact: fact}
  end

  defp entries,
    do: Repo.all(from e in ReplayEntry, where: e.kind == :taxonomic_decision, order_by: e.id)

  test "accepting is logged by stable references", ctx do
    assert {:ok, %{attribution: %Attribution{accepted_at: %DateTime{}}}} =
             Import.accept_taxonomic_statement(test_actor(), ctx.statement.id)

    assert [%ReplayEntry{key: key, payload: %{}}] = entries()

    assert key == %{
             "op" => "accept",
             "source" => %{"title" => ctx.paper.title},
             "kind" => "placement",
             "fact" => %{
               "taxon" => %{
                 "name" => "Andricus Decisions",
                 "rank" => "genus",
                 "kingdom" => "Animalia"
               },
               "parent" => %{
                 "name" => "Figitidae Decisions",
                 "rank" => "family",
                 "kingdom" => "Animalia"
               }
             }
           }
  end

  test "declining is logged with its reason; a refused decision logs nothing", ctx do
    assert {:error, :reason_required} =
             Import.decline_taxonomic_statement(test_actor(), ctx.statement.id, "")

    assert entries() == []

    {:ok, _} = Import.decline_taxonomic_statement(test_actor(), ctx.statement.id, "Not followed.")

    assert [%ReplayEntry{key: %{"op" => "decline"}, payload: %{"reason" => "Not followed."}}] =
             entries()
  end

  test "replaying makes the same decisions again", ctx do
    {:ok, _} = Import.decline_taxonomic_statement(test_actor(), ctx.statement.id, "Unsure.")
    {:ok, _} = Import.reopen_taxonomic_statement(test_actor(), ctx.statement.id)
    {:ok, _} = Import.accept_taxonomic_statement(test_actor(), ctx.statement.id)
    logged = entries()

    # As after the cutover: the decisions not yet made.
    {:ok, _} = Facts.reopen(test_actor(), ctx.statement.id)
    assert Repo.get!(Attribution, ctx.statement.id).accepted_at == nil

    assert {:ok, 3} = Replay.run(logged, actor: test_actor())
    Gallformers.ImportFixtures.assert_replays_again(logged, test_actor(), relogs: true)
    Gallformers.ImportFixtures.assert_replays_again([List.last(logged)])

    replayed = Repo.get!(Attribution, ctx.statement.id)
    assert %DateTime{} = replayed.accepted_at
    assert replayed.declined_at == nil
  end

  test "replaying a decision already made changes nothing", ctx do
    {:ok, _} = Import.accept_taxonomic_statement(test_actor(), ctx.statement.id)
    [entry] = entries()

    assert {:ok, 1} = Replay.run([entry], actor: test_actor())
    Gallformers.ImportFixtures.assert_replays_again([entry], test_actor())
    assert length(entries()) == 1
  end

  test "a decision whose statement is gone stops the replay", ctx do
    entry = %{
      kind: :taxonomic_decision,
      key: %{
        "op" => "accept",
        "source" => %{"title" => ctx.paper.title},
        "kind" => "placement",
        "fact" => %{
          "taxon" => %{"name" => "Andricus Decisions", "rank" => "genus", "kingdom" => "Animalia"},
          "parent" => nil
        }
      },
      payload: %{}
    }

    assert {:error, %{reason: {:statement_not_found, _}}} =
             Replay.run([entry], actor: test_actor())
  end
end
