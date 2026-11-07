defmodule Gallformers.Facts.ContestTest do
  @moduledoc """
  A revalidated name outranks an older synonymy of it (`f923`, the last
  "Decided" rule): once a name is a taxon's accepted name by a dated,
  counting statement, a synonymy making that name a synonym of another
  taxon whose newest counting confirmation is older (legacy undated
  included) stops counting: it is `:superseded`. Facts sees this as data:
  a name Fact and a synonymy Fact contest one name (`contest`) for their
  taxa (`contest_holder`). Declining or retracting the name statement lets
  the synonymy count again.

  Not async: some tests make the one Gallformers Source.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures, only: [source_fixture: 2, gallformers_source: 0]

  alias Gallformers.Facts
  alias Gallformers.Sources

  defmodule Recorder do
    @moduledoc false
    @behaviour Gallformers.Facts.Events

    @impl true
    def facts_changed(fact_ids) do
      send(self(), {:facts_changed, fact_ids})
      :ok
    end
  end

  defp fact!(kind, attrs) do
    {:ok, fact} = Facts.create_fact(test_actor(), Map.put(attrs, :kind, kind))
    fact
  end

  defp attribute!(fact, source, attrs) do
    {:ok, %{attribution: attribution}} =
      Facts.attribute(
        test_actor(),
        Map.merge(%{fact_id: fact.id, source_id: source.id, stance: :confirm}, attrs)
      )

    attribution
  end

  defp standing(fact), do: Facts.get_fact!(fact.id).standing

  setup do
    n = System.unique_integer([:positive])
    {revalidated, old} = {"taxon:#{n}1", "taxon:#{n}2"}
    contest = "taxon_name:synca nigra #{n}"
    legacy = Sources.get_legacy_data_source()

    # The tree's synonymy: N is a synonym of the old taxon.
    synonymy = fact!("taxon_synonymy", %{contest: contest, contest_holder: old})
    attribute!(synonymy, legacy, %{stated: nil})

    # A 1959 paper's statement that N is the revalidated taxon's name.
    name =
      fact!("taxon_name", %{
        slot: "#{revalidated}:name",
        contest: contest,
        contest_holder: revalidated
      })

    paper = source_fixture("Revalidation", "1959")
    statement = attribute!(name, paper, %{})

    %{synonymy: synonymy, name: name, paper: paper, statement: statement, contest: contest}
  end

  test "a name Fact's contest is stored", ctx do
    assert %{contest: contest, contest_holder: "taxon:" <> _} = Facts.get_fact!(ctx.name.id)
    assert contest == ctx.contest
  end

  test "awaiting a curator, the name statement leaves the synonymy current", ctx do
    assert standing(ctx.name) == :unsupported
    assert standing(ctx.synonymy) == :current
  end

  test "accepting it supersedes the older synonymy, and says so to the listeners", ctx do
    listeners = Application.get_env(:gallformers, Facts.Events)
    Application.put_env(:gallformers, Facts.Events, listeners: [Recorder])
    on_exit(fn -> Application.put_env(:gallformers, Facts.Events, listeners) end)

    {:ok, _} = Facts.accept(test_actor(), ctx.statement.id)

    assert standing(ctx.name) == :current
    assert standing(ctx.synonymy) == :superseded
    assert_received {:facts_changed, ids}
    assert Enum.sort(ids) == Enum.sort([ctx.name.id, ctx.synonymy.id])
  end

  test "declining it lets the synonymy count again", ctx do
    {:ok, _} = Facts.accept(test_actor(), ctx.statement.id)
    {:ok, _} = Facts.decline(test_actor(), ctx.statement.id, "Not revalidated.")

    assert standing(ctx.name) == :unsupported
    assert standing(ctx.synonymy) == :current
  end

  test "a retraction of the paper lets the synonymy count again", ctx do
    {:ok, _} = Facts.accept(test_actor(), ctx.statement.id)
    notice = source_fixture("Retraction notice", "2000")
    {:ok, _} = Sources.retract_source(test_actor(), ctx.paper, notice, ~D[2000-01-01])
    {:ok, _} = Facts.recompute_for_source(test_actor(), ctx.paper.id)

    assert standing(ctx.name) == :retracted
    assert standing(ctx.synonymy) == :current
  end

  test "a synonymy confirmed after the name statement keeps counting", ctx do
    {:ok, _} = Facts.accept(test_actor(), ctx.statement.id)
    later = source_fixture("Later synonymy", "1990")
    {:ok, _} = Facts.accept(test_actor(), attribute!(ctx.synonymy, later, %{}).id)

    assert standing(ctx.name) == :current
    assert standing(ctx.synonymy) == :current
  end

  test "a Gallformers statement of the name counts without acceptance", ctx do
    gallformers = gallformers_source()

    attribute!(ctx.name, gallformers, %{
      stated: "2026-01-01",
      statement_text: "A species of its own."
    })

    assert standing(ctx.synonymy) == :superseded
  end

  test "deleting the name Fact lets the synonymy count again", ctx do
    {:ok, _} = Facts.accept(test_actor(), ctx.statement.id)
    {:ok, _} = Facts.delete_facts(test_actor(), [ctx.name.id])

    assert standing(ctx.synonymy) == :current
  end
end
