defmodule GallformersWeb.Admin.QueueLive.PackageTest do
  @moduledoc """
  A package's review page (`/admin/queue/packages/:id`, matter a856 Task 3):
  its batches with their statements and unmapped entries, its queue items
  with each kind's decision, approval (and what holds it), denial of the
  package or of one batch, and resolving it again.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1]
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Import
  alias Gallformers.Import.Batch
  alias Gallformers.Import.Package
  alias Gallformers.Import.QueueItem
  alias Gallformers.Repo

  # Signing in makes the admin the test's actor, so it comes first.
  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    %{conn: conn}
  end

  setup :audit_test_metadata

  @unmapped %{
    "term" => "lignified",
    "slot" => "texture",
    "gall" => "g1",
    "evidence" => [%{"item" => "#/texts/3", "whole_item" => true}],
    "note" => "No texture value for woody galls."
  }

  # A delivered package awaiting review, with an unmapped term. "Q. lobata"
  # names no plant here, so its gall batch waits on an :unresolved_host item.
  defp awaiting! do
    gall = batch() |> unique_batch_id() |> Map.put("unmapped", [@unmapped])
    package = package(gall: gall) |> with_review() |> deliver!()
    [batch] = Import.list_batches(package)
    %{package: package, batch: batch}
  end

  defp item!(package, batch, attrs) do
    %QueueItem{}
    |> QueueItem.create_changeset(
      Map.merge(%{package_id: package.id, batch_id: batch && batch.id, proposal: %{}}, attrs)
    )
    |> Repo.insert!()
  end

  # Submits a decision, then renders once more so the page has handled the
  # component's message (and reloaded) before the test goes on or ends.
  defp decide(view, item, choice, extra \\ %{}) do
    view
    |> form("#decide-#{item.id}", decision: Map.get(extra, :decision, %{}))
    |> render_submit(Map.merge(%{"choice" => choice}, Map.delete(extra, :decision)))

    render(view)
  end

  defp decision(item), do: Import.get_queue_item!(item.id)

  describe "the package" do
    test "shows its batches, statements, unmapped entries and items", %{conn: conn} do
      %{package: package, batch: batch} = awaiting!()
      [host] = Import.list_queue_items(package, kind: :unresolved_host)
      lobata = Enum.find(Import.list_statements(batch), &(&1.ref == "t2"))

      {:ok, view, html} = live(conn, ~p"/admin/queue/packages/#{package.id}")

      assert html =~ package.key
      assert has_element?(view, "#package-status", "Awaiting review")

      assert has_element?(view, "#batch-#{batch.id}", "gall.json")
      assert has_element?(view, "#batch-#{batch.id}", "replace")
      assert has_element?(view, "#batch-#{batch.id}", batch.producer_batch_id)

      assert has_element?(view, "#statement-#{lobata.id}", "Q. lobata")
      assert has_element?(view, "#statement-#{lobata.id}", "unresolved")

      assert has_element?(view, "#unmapped-#{batch.id}", "lignified")
      assert has_element?(view, "#unmapped-#{batch.id}", "texture")

      assert has_element?(view, "#batch-items-#{batch.id} #queue-item-#{host.id}")
    end

    test "a statement shows what it resolved to and its candidates", %{conn: conn} do
      %{package: package, batch: batch} = awaiting!()
      alpha = taxon_fixture(name: "Candidatus alpha")
      beta = taxon_fixture(name: "Candidatus beta")
      statement = Enum.find(Import.list_statements(batch), &(&1.ref == "t2"))

      statement
      |> Ecto.Changeset.change(resolution: :ambiguous, candidate_ids: [alpha.id, beta.id])
      |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/admin/queue/packages/#{package.id}")

      assert has_element?(view, "#statement-#{statement.id}", "Candidatus alpha")
      assert has_element?(view, "#statement-#{statement.id}", "Candidatus beta")
    end
  end

  describe "decisions" do
    setup do
      Map.merge(awaiting!(), %{
        alpha: taxon_fixture(name: "Decidus alpha"),
        beta: taxon_fixture(name: "Decidus beta"),
        first_gall: gall_fixture(name: "Decidus first gall"),
        second_gall: gall_fixture(name: "Decidus second gall")
      })
    end

    test "an ambiguous name: pick a candidate", ctx do
      item =
        item!(ctx.package, ctx.batch, %{
          kind: :ambiguous_match,
          statement_ref: "t7",
          subject: %{"name_as_written" => "D. alpha"},
          proposal: %{"candidate_ids" => [ctx.alpha.id, ctx.beta.id]},
          reason: "two taxa may be this one"
        })

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/queue/packages/#{ctx.package.id}")
      assert has_element?(view, "#decide-#{item.id}", "Decidus alpha")
      assert has_element?(view, "#queue-item-#{item.id}", "D. alpha")

      decide(view, item, "taxon_id:#{ctx.beta.id}")

      assert %QueueItem{status: :decided, decision: decision, decided_by_name: "Rita Reviewer"} =
               decision(item)

      assert decision == %{"taxon_id" => ctx.beta.id}
      refute has_element?(view, "#decide-#{item.id}")
      assert has_element?(view, "#queue-item-#{item.id}", "Decidus beta")
    end

    test "an unresolved Host: another taxon by ID frees the batch", ctx do
      plant = plant_fixture(name: "Quercus decidua")
      [host] = Import.list_queue_items(ctx.package, kind: :unresolved_host)
      assert ctx.batch.status == :blocked

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/queue/packages/#{ctx.package.id}")
      decide(view, host, "taxon_id:other", %{decision: %{other_id: "#{plant.id}"}})

      assert decision(host).decision == %{"taxon_id" => plant.id}
      assert Import.get_batch!(ctx.batch.id).status == :ready
    end

    test "a missing or unknown ID is refused with the reason", ctx do
      [host] = Import.list_queue_items(ctx.package, kind: :unresolved_host)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/queue/packages/#{ctx.package.id}")

      html = decide(view, host, "taxon_id:other", %{decision: %{other_id: ""}})
      assert html =~ "Enter an ID"
      assert decision(host).status == :open

      html = decide(view, host, "taxon_id:other", %{decision: %{other_id: "-5"}})
      assert html =~ "not valid here"
      assert decision(host).status == :open
    end

    test "an unresolved Host: skip, with a note", ctx do
      [host] = Import.list_queue_items(ctx.package, kind: :unresolved_host)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/queue/packages/#{ctx.package.id}")

      decide(view, host, "skip", %{decision: %{note: "Not a Host."}})

      assert decision(host).decision == %{"skip" => true, "note" => "Not a Host."}
    end

    test "an ambiguous Gall: a new Gall", ctx do
      item =
        item!(ctx.package, ctx.batch, %{
          kind: :ambiguous_match,
          statement_ref: "g7",
          subject: %{"name_as_written" => "the round galls"},
          proposal: %{"candidate_ids" => [ctx.first_gall.id, ctx.second_gall.id]}
        })

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/queue/packages/#{ctx.package.id}")
      assert has_element?(view, "#decide-#{item.id}", "Decidus second gall")

      decide(view, item, "new")
      assert decision(item).decision == %{"new" => true}
    end

    test "an undescribed-Gall candidate: the proposed one is marked and can be picked", ctx do
      item =
        item!(ctx.package, ctx.batch, %{
          kind: :undescribed_gall,
          statement_ref: "g8",
          subject: %{"name_as_written" => "an undescribed gall"},
          proposal: %{
            "candidate_ids" => [ctx.first_gall.id, ctx.second_gall.id],
            "proposed" => ctx.second_gall.id
          }
        })

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/queue/packages/#{ctx.package.id}")
      assert has_element?(view, "#decide-#{item.id}", "proposed")

      decide(view, item, "gall_id:#{ctx.second_gall.id}")
      assert decision(item).decision == %{"gall_id" => ctx.second_gall.id}
    end

    test "the package's Source: pick a candidate or a new Source", ctx do
      source = source_fixture("Decision Source", "1970")

      pick =
        item!(ctx.package, nil, %{
          kind: :ambiguous_match,
          statement_ref: "source",
          subject: %{"title" => "Decision Source?"},
          proposal: %{"candidate_ids" => [source.id]}
        })

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/queue/packages/#{ctx.package.id}")
      assert has_element?(view, "#package-items #queue-item-#{pick.id}", "Decision Source?")

      decide(view, pick, "source_id:#{source.id}")
      assert decision(pick).decision == %{"source_id" => source.id}
    end

    test "the Source a notice retracts: skip", ctx do
      item =
        item!(ctx.package, nil, %{
          kind: :unresolved_name,
          statement_ref: "retracts",
          subject: %{"title" => "A retracted paper"}
        })

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/queue/packages/#{ctx.package.id}")
      decide(view, item, "skip")
      assert decision(item).decision == %{"skip" => true}
    end

    test "a dispute shows the findings; keep or drop the statement", ctx do
      findings = [
        %{
          "problem" => "unsupported",
          "reason" => "the quote does not name the Host",
          "reviewer" => "checker",
          "response" => %{"decision" => "disagree", "reason" => "it does"}
        }
      ]

      keep =
        item!(ctx.package, ctx.batch, %{
          kind: :dispute,
          statement_ref: "f2",
          subject: %{"findings" => findings}
        })

      drop =
        item!(ctx.package, ctx.batch, %{
          kind: :dispute,
          statement_ref: "f3",
          subject: %{"findings" => findings}
        })

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/queue/packages/#{ctx.package.id}")
      assert has_element?(view, "#queue-item-#{keep.id}", "the quote does not name the Host")
      assert has_element?(view, "#queue-item-#{keep.id}", "it does")

      decide(view, keep, "keep", %{decision: %{note: "The quote names it."}})
      decide(view, drop, "skip")

      assert decision(keep).decision == %{"keep" => true, "note" => "The quote names it."}
      assert decision(drop).decision == %{"skip" => true}
    end

    test "items for a curator after the fact are acknowledged, with a note or none", ctx do
      conflict =
        item!(ctx.package, ctx.batch, %{
          kind: :same_date_conflict,
          statement_ref: "f9",
          subject: %{"type" => "host_of", "fact_id" => 1, "fact_ids" => [1, 2]}
        })

      generation =
        item!(ctx.package, ctx.batch, %{
          kind: :generation_outside_group,
          statement_ref: "g1",
          subject: %{
            "gall_id" => ctx.first_gall.id,
            "inducer_id" => ctx.alpha.id,
            "generation" => "agamic"
          }
        })

      act =
        item!(ctx.package, ctx.batch, %{
          kind: :taxonomy_disagreement,
          statement_ref: "a1",
          subject: %{"kind" => "placement", "stance" => "confirm", "taxon" => "t1"}
        })

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/queue/packages/#{ctx.package.id}")
      assert has_element?(view, "#queue-item-#{generation.id}", "Decidus first gall")
      assert has_element?(view, "#queue-item-#{generation.id}", "Decidus alpha")
      refute has_element?(view, "#decide-#{conflict.id} button[value=skip]")

      decide(view, conflict, "ack", %{decision: %{note: "Settled by a later paper."}})
      decide(view, generation, "ack")
      decide(view, act, "ack")

      assert decision(conflict).decision == %{"note" => "Settled by a later paper."}
      assert decision(generation).decision == %{}
      assert decision(act).decision == %{}
    end

    test "a name held valid against the tree: acknowledge, pick a taxon or skip", ctx do
      held =
        item!(ctx.package, ctx.batch, %{
          kind: :taxonomy_disagreement,
          statement_ref: "t8",
          subject: %{"name_as_written" => "Decidus gamma"},
          proposal: %{"candidate_ids" => [ctx.alpha.id]}
        })

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/queue/packages/#{ctx.package.id}")
      assert has_element?(view, "#decide-#{held.id} button[value=ack]")

      decide(view, held, "taxon_id:#{ctx.alpha.id}")
      assert decision(held).decision == %{"taxon_id" => ctx.alpha.id}
    end
  end

  describe "approval" do
    test "is held by an open item, and says which", %{conn: conn} do
      %{package: package} = awaiting!()

      {:ok, view, _html} = live(conn, ~p"/admin/queue/packages/#{package.id}")
      view |> element("#approve-package") |> render_click()

      assert has_element?(view, "#approval-held", "Unresolved Host")
      assert has_element?(view, "#approval-held", "t2")
      assert Import.get_package!(package.id).status == :awaiting_review
    end

    test "with nothing open applies the package", %{conn: conn} do
      load_vocab!()
      plant_fixture(name: "Quercus lobata")
      taxon_fixture(name: "Andricus quercuscalifornicus", kingdom: "Animalia")
      taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")

      gall =
        batch()
        |> unique_batch_id()
        |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
        |> put_in(["galls", Access.at(0), "new"], true)

      package = package(gall: gall) |> with_review() |> deliver!()
      assert Import.list_queue_items(package) == []

      {:ok, view, _html} = live(conn, ~p"/admin/queue/packages/#{package.id}")
      html = view |> element("#approve-package") |> render_click()

      assert html =~ "approved"
      assert %Package{status: :approved} = Import.get_package!(package.id)
      assert [%Batch{status: :applied}] = Import.list_batches(package)
      assert has_element?(view, "#package-status", "Approved")
      refute has_element?(view, "#approve-package")
    end
  end

  describe "denial" do
    test "denies the package with a reason", %{conn: conn} do
      %{package: package} = awaiting!()

      {:ok, view, _html} = live(conn, ~p"/admin/queue/packages/#{package.id}")
      view |> element("#deny-package") |> render_click()

      html = view |> form("#deny-form", deny: %{reason: "  "}) |> render_submit()
      assert html =~ "can&#39;t be blank"
      assert Import.get_package!(package.id).status == :awaiting_review

      view |> form("#deny-form", deny: %{reason: "Duplicate delivery."}) |> render_submit()

      assert %Package{status: :denied, denied_reason: "Duplicate delivery."} =
               Import.get_package!(package.id)

      assert has_element?(view, "#package-status", "Denied")
      assert has_element?(view, "#package-header", "Duplicate delivery.")
      refute has_element?(view, "#deny-package")
    end

    test "denies one batch", %{conn: conn} do
      taxonomy = taxonomy_batch() |> unique_batch_id()

      package =
        package(gall: unique_batch_id(batch()), taxonomy: taxonomy) |> with_review() |> deliver!()

      gall = Enum.find(Import.list_batches(package), &(&1.batch_type == :gall))

      {:ok, view, _html} = live(conn, ~p"/admin/queue/packages/#{package.id}")
      view |> element("#deny-batch-#{gall.id}") |> render_click()
      view |> form("#deny-form", deny: %{reason: "Wrong Source."}) |> render_submit()

      assert %Batch{status: :denied, denied_reason: "Wrong Source."} = Import.get_batch!(gall.id)
      assert Import.get_package!(package.id).status == :awaiting_review
      assert has_element?(view, "#batch-#{gall.id}", "Wrong Source.")
      refute has_element?(view, "#deny-batch-#{gall.id}")
    end
  end

  test "resolves the package again", %{conn: conn} do
    %{package: package, batch: batch} = awaiting!()
    # Resolving replaces a batch's open items with the ones it calls for now.
    stale = item!(package, batch, %{kind: :unresolved_name, statement_ref: "t7"})

    {:ok, view, _html} = live(conn, ~p"/admin/queue/packages/#{package.id}")
    assert has_element?(view, "#queue-item-#{stale.id}")

    html = view |> element("#resolve-package") |> render_click()

    assert html =~ "resolved again"
    refute has_element?(view, "#queue-item-#{stale.id}")
    assert [_host] = Import.list_queue_items(package, kind: :unresolved_host)
    assert Import.get_package!(package.id).status == :awaiting_review
  end
end
