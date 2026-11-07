defmodule GallformersWeb.Admin.ReviewLive.TaxonomyTest do
  @moduledoc """
  The taxonomy queue (`/admin/review/taxonomy`, matter `f923` Task 6): the
  Sources' taxonomic statements to accept or decline, across Sources,
  grouped by Source, each decided in place. Accept is recommended; Decline
  asks for its reason only once chosen. "Accept the rest of this paper"
  shows what it does to the tree first. The Sources list and a Source's
  overview lead here.

  Not async: packages create Sources and the vocabularies are loaded.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1]
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Sources
  alias Gallformers.Taxa

  # Signing in makes the admin the test's actor, so it comes first.
  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    %{conn: conn}
  end

  setup :audit_test_metadata

  setup do
    load_vocab!()
    legacy = Sources.get_legacy_data_source()
    n = System.unique_integer([:positive])

    family = taxon_fixture(rank: :family, name: "Pageidae#{n}", kingdom: "Animalia")
    other = taxon_fixture(rank: :family, name: "Otherpageidae#{n}", kingdom: "Animalia")
    genus = taxon_fixture(rank: :genus, name: "Pagea#{n}", parent: family)

    for taxon <- [family, other, genus] do
      taxon = Taxa.get_taxon!(taxon.id)
      attribution = %{source_id: legacy.id, stance: :confirm, stated: nil}

      {:ok, _} =
        Taxa.assert_placement(
          Gallformers.DataCase.test_actor(),
          %{taxon_id: taxon.id, parent_id: taxon.parent_id},
          attribution
        )

      {:ok, _} =
        Taxa.assert_name(
          Gallformers.DataCase.test_actor(),
          %{taxon_id: taxon.id, name: Taxa.accepted_name(taxon), rank: taxon.rank},
          attribution
        )
    end

    %{family: family, other: other, genus: genus}
  end

  defp declared(ref, taxon) do
    taxon = Taxa.get_taxon!(taxon.id)
    %{"ref" => ref, "name_as_written" => Taxa.accepted_name(taxon), "rank" => "#{taxon.rank}"}
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

  # An applied paper of `date` by Weld, placing `taxon` under `parent`.
  defp places!(taxon, parent, date \\ "2001") do
    u = System.unique_integer([:positive])

    batch =
      taxonomy_batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "A revision #{u}")
      |> put_in(["source", "citation"], "Weld, L. H. #{date}. A revision #{u}.")
      |> put_in(["source", "authors"], ["Weld, L. H."])
      |> put_in(["source", "authored"], %{"date" => date, "as_written" => date})
      |> Map.put("taxa", [declared("t1", taxon), declared("t2", parent)])
      |> Map.put("acts", [act("a1", "placement", %{"taxon" => "t1", "parent" => "t2"})])

    package = package(gall: nil, taxonomy: batch) |> with_review() |> deliver!()
    {:ok, _} = Import.approve_package(Gallformers.DataCase.test_actor(), package)
    [item] = Import.list_queue_items(package, kind: :taxonomy_acceptance)
    %{package: Import.get_package!(package.id), item: item, source_id: item.subject["source_id"]}
  end

  defp open_row(view, item), do: view |> element("#item-#{item.id}-row") |> render_click()

  defp pick(view, item, label) do
    view
    |> element("#item-#{item.id}-choice-#{choice_index(view, item, label)}")
    |> render_click()
  end

  defp parent_id(taxon), do: Taxa.get_taxon!(taxon.id).parent_id

  describe "the way in" do
    test "the Sources list has a row for the open questions, leading to the page", ctx do
      places!(ctx.genus, ctx.other)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/review")

      assert has_element?(view, "#taxonomy-questions", "Taxonomy questions")
      assert has_element?(view, "#taxonomy-questions [data-role=to-decide]", "1")

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> element("#taxonomy-questions a", "Taxonomy questions") |> render_click()

      assert to == ~p"/admin/review/taxonomy"
    end

    test "a Source's overview says how many are open and links to them", ctx do
      %{source_id: source_id} = places!(ctx.genus, ctx.other)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/review/sources/#{source_id}")

      assert has_element?(view, "#taxonomy-questions-open", "1 taxonomy question open")

      assert has_element?(
               view,
               "#taxonomy-questions-open a[href='/admin/review/taxonomy?source=#{source_id}']"
             )
    end
  end

  describe "the page" do
    test "groups the questions by Source, Accept recommended", ctx do
      %{item: item, source_id: source_id} = places!(ctx.genus, ctx.other)

      {:ok, view, html} = live(ctx.conn, ~p"/admin/review/taxonomy")

      assert html =~ "Taxonomy questions"
      assert has_element?(view, "#section-source-#{source_id} #item-#{item.id}", "Pagea")
      assert has_element?(view, "#section-source-#{source_id}", "Weld 2001")
      assert has_element?(view, "#item-#{item.id}-row", "Recommended")
    end

    test "accepting moves the tree and the question leaves the list", ctx do
      %{item: item} = places!(ctx.genus, ctx.other)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/review/taxonomy")

      open_row(view, item)
      pick(view, item, "Accept: follow Weld 2001")
      view |> element("#item-#{item.id}-decide") |> render_click()

      assert %QueueItem{status: :decided, decision: %{"accept" => true}} =
               Import.get_queue_item!(item.id)

      assert parent_id(ctx.genus) == ctx.other.id
      assert render(view) =~ "Decision recorded."
      refute has_element?(view, "#item-#{item.id}")
    end

    test "Decline asks for the reason only once chosen, and needs one", ctx do
      %{item: item} = places!(ctx.genus, ctx.other)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/review/taxonomy")

      open_row(view, item)
      refute has_element?(view, "#item-#{item.id}-picker-reason")

      pick(view, item, "Decline")
      assert has_element?(view, "#item-#{item.id}-picker-reason")
      assert has_element?(view, "#item-#{item.id}-decide[disabled]")

      view
      |> form("#item-#{item.id}-picker", %{"value" => "Not followed by later work."})
      |> render_change()

      view |> element("#item-#{item.id}-decide") |> render_click()

      assert %QueueItem{decision: %{"decline" => true, "reason" => "Not followed by later work."}} =
               Import.get_queue_item!(item.id)

      assert parent_id(ctx.genus) == ctx.family.id

      assert Facts.get_attribution(item.subject["attribution_id"]).decline_reason ==
               "Not followed by later work."

      # Decided ones are listed on request, with the reason.
      view |> element("#show-decided") |> render_click()
      assert has_element?(view, "#item-#{item.id}", "Not followed by later work.")
    end

    test "a refusal from the tree shows its reason in the row", ctx do
      # The family under its own genus: a cycle.
      %{item: item} = places!(ctx.family, ctx.genus)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/review/taxonomy")

      open_row(view, item)
      pick(view, item, "Accept: follow Weld 2001")
      view |> element("#item-#{item.id}-decide") |> render_click()

      assert has_element?(view, "#item-#{item.id}-error", "The tree refuses it")
      assert Import.get_queue_item!(item.id).status == :open
    end

    test "a Source's link shows only its questions", ctx do
      %{item: mine, source_id: source_id} = places!(ctx.genus, ctx.other)
      %{item: theirs} = places!(ctx.genus, ctx.other, "2002")

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/review/taxonomy?source=#{source_id}")

      assert has_element?(view, "#item-#{mine.id}")
      refute has_element?(view, "#item-#{theirs.id}")
    end

    test "says so when nothing is open", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/review/taxonomy")
      assert render(view) =~ "No taxonomy question is waiting."
    end
  end

  describe "accepting the rest of a paper" do
    test "shows what it does to the tree, then accepts on confirmation", ctx do
      %{item: item, source_id: source_id} = places!(ctx.genus, ctx.other)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/review/taxonomy")

      view |> element("#accept-rest-#{source_id}") |> render_click()

      assert has_element?(view, "#accept-rest-preview-#{source_id}", "Moves")

      assert has_element?(
               view,
               "#accept-rest-preview-#{source_id}",
               Taxa.accepted_name(ctx.other.id)
             )

      assert parent_id(ctx.genus) == ctx.family.id

      view |> element("#accept-rest-confirm-#{source_id}") |> render_click()

      assert parent_id(ctx.genus) == ctx.other.id
      assert Import.get_queue_item!(item.id).status == :decided
      assert render(view) =~ "Accepted 1 statement"
    end

    test "a refusal is shown in the preview, with nothing to confirm", ctx do
      %{source_id: source_id} = places!(ctx.family, ctx.genus)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/review/taxonomy")

      view |> element("#accept-rest-#{source_id}") |> render_click()

      assert has_element?(view, "#accept-rest-preview-#{source_id}", "The tree refuses it")
      refute has_element?(view, "#accept-rest-confirm-#{source_id}")
    end
  end

  describe "split questions" do
    setup ctx do
      actor = Gallformers.DataCase.test_actor()
      legacy = Sources.get_legacy_data_source()
      weld = source_fixture("Weld", "1959")
      paper = source_fixture("Splitter", "2001")
      split = taxon_fixture(name: "#{Taxa.accepted_name(ctx.genus)} alba", parent: ctx.genus)
      beta = taxon_fixture(name: "#{Taxa.accepted_name(ctx.genus)} beta", parent: ctx.genus)

      for taxon <- [split, beta] do
        attribution = %{source_id: legacy.id, stance: :confirm, stated: nil}

        {:ok, _} =
          Taxa.assert_placement(
            actor,
            %{taxon_id: taxon.id, parent_id: ctx.genus.id},
            attribution
          )

        {:ok, _} =
          Taxa.assert_name(
            actor,
            %{taxon_id: taxon.id, name: Taxa.accepted_name(taxon), rank: :species},
            attribution
          )
      end

      oak = plant_fixture()
      induced = fn gall, taxon, source -> relate!(actor, "inducer_of", taxon, gall, source) end
      hosted = fn gall, source -> relate!(actor, "host_of", oak, gall, source) end

      # The paper's own Gall of the daughter, on the oak.
      own = gall_fixture(name: "#{Taxa.accepted_name(beta)} (sexgen)", generation: "sexual")
      induced.(own, beta, paper)
      hosted.(own, paper)

      gall = gall_fixture(name: "#{Taxa.accepted_name(split)} (agamic)", generation: "agamic")
      induced.(gall, split, weld)
      hosted.(gall, weld)

      {:ok, %{attribution: attribution}} =
        Taxa.assert_split(
          actor,
          %{taxon_id: split.id, into_taxon_ids: [split.id, beta.id]},
          confirm(paper)
        )

      {:ok, _} = Import.TaxonomicDecisions.decide(actor, :accept, attribution.id)
      [item] = Import.list_split_questions()

      %{paper: paper, split: split, beta: beta, gall: gall, item: item}
    end

    defp relate!(actor, type, taxon, gall, source) do
      {:ok, _} =
        Gallformers.Catalog.assert_relationship(
          actor,
          %{type: type, subject_taxon_id: taxon.id, object_gall_id: gall.id},
          confirm(source)
        )
    end

    test "are listed under the splitting Source, each daughter a choice, the suggested one recommended",
         ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/review/taxonomy")

      row = "#section-source-#{ctx.paper.id} #item-#{ctx.item.id}"
      assert has_element?(view, row, ctx.gall.name)
      assert has_element?(view, "#item-#{ctx.item.id}-row", "A suggestion to check")

      open_row(view, ctx.item)
      beta = Taxa.accepted_name(ctx.beta)
      recommended = "#item-#{ctx.item.id}-choices [data-recommended]"
      assert has_element?(view, recommended, beta)
      assert has_element?(view, recommended, "as this one is")
      refute has_element?(view, recommended, "Not known yet")
      assert has_element?(view, "#item-#{ctx.item.id}-choices", "in its narrow sense")
      assert has_element?(view, "#item-#{ctx.item.id}-choices", "Not known yet")
      refute has_element?(view, "#accept-rest-#{ctx.paper.id}")
    end

    test "choosing a daughter re-points the Gall's Inducer", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/review/taxonomy")

      open_row(view, ctx.item)
      pick(view, ctx.item, Taxa.accepted_name(ctx.beta))
      view |> element("#item-#{ctx.item.id}-decide") |> render_click()

      assert %QueueItem{status: :decided, decision: %{"taxon_id" => id}} =
               Import.get_queue_item!(ctx.item.id)

      assert id == ctx.beta.id
      assert render(view) =~ "Decision recorded."

      assert [%{taxon_id: ^id}] =
               Gallformers.Catalog.list_gall_summaries_by_inducer([id])
               |> Enum.filter(&(&1.gall_id == ctx.gall.id))
               |> Enum.flat_map(& &1.inducers)
    end

    test "not known yet keeps it, and the Gall page says so on its Inducer", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/review/taxonomy")

      open_row(view, ctx.item)
      pick(view, ctx.item, "Not known yet")
      view |> element("#item-#{ctx.item.id}-decide") |> render_click()

      assert %QueueItem{decision: %{"not_known" => true}} = Import.get_queue_item!(ctx.item.id)

      {:ok, page, _html} = live(ctx.conn, ~p"/gall/#{ctx.gall.id}")
      assert render(page) =~ "in its old broad sense, before #{Sources.short_name(ctx.paper)}"
    end
  end

  # The index of the choice labelled `label` in an open item's choices.
  defp choice_index(view, item, label) do
    view
    |> element("#item-#{item.id}-choices label", label)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("input")
    |> LazyHTML.attribute("value")
    |> List.first()
  end
end
