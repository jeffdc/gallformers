defmodule Gallformers.Facts.AcceptanceTest do
  @moduledoc """
  Acceptance and decline of taxonomic statements (`f923` Task 1): a
  Source's statement of a taxonomic Fact counts only once a curator has
  accepted it, unless the Source is Gallformers' own (the Gallformers
  Source or the undated legacy data Source). A declined statement never
  counts until reopened. Gall Facts are unaffected.

  Not async: some tests make the one Gallformers Source.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures, only: [source_fixture: 2, gallformers_source: 0]

  alias Gallformers.Accounts
  alias Gallformers.Audit.Actor
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Sources

  defp fact!(kind, slot) do
    {:ok, fact} = Facts.create_fact(test_actor(), %{kind: kind, slot: slot})
    fact
  end

  defp attribute!(fact, source, attrs \\ %{}) do
    {:ok, %{attribution: attribution}} =
      Facts.attribute(
        test_actor(),
        Map.merge(%{fact_id: fact.id, source_id: source.id, stance: :confirm}, attrs)
      )

    attribution
  end

  defp standing(fact), do: Facts.get_fact!(fact.id).standing

  defp legacy_source, do: Sources.get_legacy_data_source()

  setup ctx do
    user =
      if ctx[:as_user] do
        {:ok, user} =
          Accounts.create_user(%{
            auth0_id: "auth0|acceptance-#{System.unique_integer([:positive])}",
            display_name: "Ada"
          })

        :ok = put_test_actor(Actor.user(user.id, "Ada"))
        user
      end

    slot = "taxon:#{System.unique_integer([:positive])}:placement"
    older = fact!("taxon_placement", slot)
    newer = fact!("taxon_placement", slot)
    legacy = attribute!(older, legacy_source(), %{stated: nil})
    paper = source_fixture("Revision", "1990")
    statement = attribute!(newer, paper)

    %{older: older, newer: newer, legacy: legacy, paper: paper, statement: statement, user: user}
  end

  describe "an unaccepted statement" do
    test "a newer paper's statement leaves the older winner current", ctx do
      assert standing(ctx.older) == :current
      assert standing(ctx.newer) == :unsupported
    end

    test "the legacy and Gallformers Sources count without acceptance", ctx do
      gallformers = gallformers_source()
      other = fact!("taxon_placement", ctx.older.slot)
      attribute!(other, gallformers, %{stated: "2026-01-01", statement_text: "Our position."})

      assert standing(other) == :current
      assert standing(ctx.older) == :superseded
    end

    test "gall kinds count without acceptance", ctx do
      slot = "gall:#{System.unique_integer([:positive])}:detachable"
      old = fact!("trait", slot)
      new = fact!("trait", slot)
      attribute!(old, source_fixture("Kinsey", "1930"))
      attribute!(new, ctx.paper)

      assert standing(new) == :current
      assert standing(old) == :superseded
    end
  end

  describe "accept/3" do
    @tag :as_user
    test "accepting supersedes the older winner, recording who and when", ctx do
      assert {:ok, %{attribution: %Attribution{} = accepted, conflicts: []}} =
               Facts.accept(test_actor(), ctx.statement.id)

      assert accepted.accepted_by_user_id == ctx.user.id
      assert %DateTime{} = accepted.accepted_at
      assert standing(ctx.newer) == :current
      assert standing(ctx.older) == :superseded
    end

    test "is audited", ctx do
      {:ok, _} = Facts.accept(test_actor(), ctx.statement.id)

      assert [_ | _] =
               Repo.all(
                 from c in test_audit_changes(),
                   where: c.table_name == "attributions" and c.op == :update
               )
    end

    test "a Gallformers' own statement needs none", ctx do
      assert {:error, :own_source} = Facts.accept(test_actor(), ctx.legacy.id)
    end

    test "a gall Fact's statement takes none", ctx do
      fact = fact!("trait", nil)
      attribution = attribute!(fact, ctx.paper)
      assert {:error, :not_taxonomic} = Facts.accept(test_actor(), attribution.id)
    end

    test "an unknown attribution", _ctx do
      assert {:error, :not_found} = Facts.accept(test_actor(), -1)
    end

    test "a retracted accepted Source falls back to the older winner", ctx do
      {:ok, _} = Facts.accept(test_actor(), ctx.statement.id)
      notice = source_fixture("Retraction notice", "2000")
      {:ok, _} = Sources.retract_source(test_actor(), ctx.paper, notice, ~D[2000-01-01])
      {:ok, _} = Facts.recompute_for_source(test_actor(), ctx.paper.id)

      assert standing(ctx.older) == :current
      assert standing(ctx.newer) == :retracted
    end

    test "a re-import changing the statement's stance clears its acceptance", ctx do
      {:ok, _} = Facts.accept(test_actor(), ctx.statement.id)
      attribute!(ctx.newer, ctx.paper, %{stance: :deny})

      assert %Attribution{accepted_at: nil} = Repo.get!(Attribution, ctx.statement.id)
      assert standing(ctx.older) == :current
    end

    test "a restatement keeps its acceptance", ctx do
      {:ok, _} = Facts.accept(test_actor(), ctx.statement.id)
      attribute!(ctx.newer, ctx.paper)

      assert %Attribution{accepted_at: %DateTime{}} = Repo.get!(Attribution, ctx.statement.id)
      assert standing(ctx.newer) == :current
    end
  end

  describe "decline/3" do
    test "declining keeps the older winner and records the reason", ctx do
      assert {:ok, %{attribution: declined}} =
               Facts.decline(test_actor(), ctx.statement.id, "Not followed by later work.")

      assert declined.decline_reason == "Not followed by later work."
      assert %DateTime{} = declined.declined_at
      assert declined.accepted_at == nil
      assert standing(ctx.older) == :current
      assert standing(ctx.newer) == :unsupported
    end

    test "a reason is required", ctx do
      assert {:error, :reason_required} = Facts.decline(test_actor(), ctx.statement.id, "  ")
    end

    test "declining an accepted statement undoes its effect", ctx do
      {:ok, _} = Facts.accept(test_actor(), ctx.statement.id)
      {:ok, _} = Facts.decline(test_actor(), ctx.statement.id, "Changed my mind.")

      assert standing(ctx.older) == :current
      assert standing(ctx.newer) == :unsupported
    end
  end

  describe "reopen/2" do
    test "reopen then accept", ctx do
      {:ok, _} = Facts.decline(test_actor(), ctx.statement.id, "Unsure.")
      assert {:ok, %{attribution: reopened}} = Facts.reopen(test_actor(), ctx.statement.id)
      assert reopened.declined_at == nil and reopened.decline_reason == nil
      assert standing(ctx.newer) == :unsupported

      {:ok, _} = Facts.accept(test_actor(), ctx.statement.id)
      assert standing(ctx.newer) == :current
    end
  end

  describe "slot_statements/1" do
    test "every statement in the slot, with whether each counts", ctx do
      statements = Facts.slot_statements(ctx.statement.id)

      assert Enum.sort(Enum.map(statements, & &1.id)) ==
               Enum.sort([ctx.legacy.id, ctx.statement.id])

      by_id = Map.new(statements, &{&1.id, &1})
      assert %{counts: true, retracted: false, fact_id: older_id} = by_id[ctx.legacy.id]
      assert older_id == ctx.older.id

      assert %{counts: false, stated_on: ~D[1990-01-01], stated_precision: :year} =
               by_id[ctx.statement.id]
    end

    test "an unslotted Fact's statements are its own" do
      fact = fact!("taxon_synonymy", nil)
      other = fact!("taxon_synonymy", nil)
      a = attribute!(fact, legacy_source(), %{stated: nil})
      _b = attribute!(other, legacy_source(), %{stated: nil})

      assert [%{id: id}] = Facts.slot_statements(a.id)
      assert id == a.id
    end

    test "none for an unknown statement" do
      assert Facts.slot_statements(-1) == []
    end
  end

  test "the kinds that need acceptance are the taxonomic ones" do
    assert Enum.sort(Facts.acceptance_kinds()) ==
             ~w(taxon_common_name taxon_name taxon_placement taxon_split taxon_synonymy)
  end
end
