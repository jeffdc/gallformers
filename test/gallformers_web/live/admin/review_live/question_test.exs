defmodule GallformersWeb.Admin.ReviewLive.QuestionTest do
  @moduledoc """
  One question on a step page (matter `d213`, Task 16): a row that opens
  and closes on a click (a button, so Enter and Space work too), no row
  open to start with; open, the question and its scope, the quotes, the
  options as radio cards (the recommended one tagged, a follow-up input
  only under the chosen one), a Decide bar saying what the chosen option
  does or what is missing, Decide closing the row, and the notes apart.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1, test_actor: 0]
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Repo

  # A batch-local ref (t24, g1, f5, a2) as a word.
  @ref ~r/\b[tgfa]\d+\b/

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    %{conn: conn}
  end

  setup :audit_test_metadata

  @unmapped %{
    "term" => "lignified",
    "slot" => "other",
    "gall" => "g1",
    "evidence" => [%{"item" => "#/texts/3", "quote" => "an external parasitoid"}],
    "note" => "for one Host only"
  }

  # A package awaiting review, by Ashmead, with a statement set aside.
  # "Q. lobata" names no plant here, so its gall batch waits on a Host name.
  defp awaiting!(unmapped \\ [@unmapped]) do
    load_vocab!()

    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "Galls of the oaks")
      |> put_in(["source", "citation"], "Ashmead, W. H. 1897. Galls of the oaks.")
      |> put_in(["source", "authors"], ["Ashmead, W. H."])
      |> put_in(["source", "authored"], %{"date" => "1897", "as_written" => "1897"})
      |> Map.put("unmapped", unmapped)

    package = package(gall: gall) |> with_review() |> deliver!()
    [batch] = Import.list_batches(package)
    %{package: package, batch: batch}
  end

  defp open_item(package, kind),
    do: Enum.find(Import.list_queue_items(package), &(&1.kind == kind))

  defp step(conn, package, step),
    do: live(conn, ~p"/admin/review/packages/#{package.id}/#{step}")

  defp visible_text(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.text()

  defp open_row(view, item), do: view |> element("#item-#{item.id}-row") |> render_click()

  # Chooses the option labelled `label` in an open item.
  defp choose(view, item, label) do
    id =
      view
      |> element("#item-#{item.id}-choices label", label)
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("input")
      |> LazyHTML.attribute("id")
      |> List.first()

    view |> element("##{id}") |> render_click()
  end

  describe "the row" do
    test "starts closed, and opens and closes on a click, as its chevron shows",
         %{conn: conn} do
      %{package: package} = awaiting!()
      host = open_item(package, :unresolved_host)
      {:ok, view, _html} = step(conn, package, "names")

      # The row is a button, so the keyboard opens it too.
      assert has_element?(view, "button#item-#{host.id}-row[aria-expanded=false]")
      refute has_element?(view, "#item-#{host.id}-detail")

      open_row(view, host)
      assert has_element?(view, "button#item-#{host.id}-row[aria-expanded=true]")
      assert has_element?(view, "#item-#{host.id}-row [data-role=chevron].rotate-90")

      assert has_element?(
               view,
               "#item-#{host.id}-detail [data-role=question]",
               "Which plant does Ashmead 1897 mean by"
             )

      assert has_element?(view, "#item-#{host.id}-detail [data-role=scope]", "If you leave it")

      open_row(view, host)
      refute has_element?(view, "#item-#{host.id}-detail")
    end

    test "shows the Source's words and the recommended answer, with no refs", %{conn: conn} do
      %{package: package} = awaiting!()
      hedge = open_item(package, :set_aside_statement)
      {:ok, view, _html} = step(conn, package, "hedges")

      assert has_element?(view, "#item-#{hedge.id}-row", "lignified")
      assert has_element?(view, "#item-#{hedge.id}-row [data-role=answer]", "Leave it out")
      assert has_element?(view, "#item-#{hedge.id}-row [data-role=answer]", "Recommended")

      text = view |> element("#step-sections") |> render() |> visible_text()
      refute text =~ @ref
      refute text =~ package.key
    end

    test "the technical details hold the ref, behind a disclosure", %{conn: conn} do
      %{package: package} = awaiting!()
      host = open_item(package, :unresolved_host)
      {:ok, view, _html} = step(conn, package, "names")

      open_row(view, host)
      assert has_element?(view, "#item-#{host.id}-detail details", "t2")

      detail =
        view
        |> element("#item-#{host.id}-detail [data-role=question]")
        |> render()
        |> visible_text()

      refute detail =~ @ref
    end
  end

  describe "the options" do
    test "radio cards, the recommended one tagged, none chosen to start", %{conn: conn} do
      %{package: package} = awaiting!()
      hedge = open_item(package, :set_aside_statement)
      {:ok, view, _html} = step(conn, package, "hedges")
      open_row(view, hedge)

      assert has_element?(view, "#item-#{hedge.id}-choices [data-role=recommended]")

      assert has_element?(
               view,
               "#item-#{hedge.id}-choices [data-recommended] [data-role=recommended]",
               "Recommended"
             )

      refute has_element?(view, "#item-#{hedge.id}-choices input[checked]")
      assert has_element?(view, "#item-#{hedge.id}-quotes", "an external parasitoid")
    end

    test "a follow-up input shows only under the chosen option", %{conn: conn} do
      %{package: package} = awaiting!()

      item =
        package
        |> Import.list_queue_items(kind: :unresolved_name)
        |> Enum.find(&(&1.subject["name_as_written"] == "Torymus"))

      {:ok, view, _html} = step(conn, package, "names")
      open_row(view, item)
      refute has_element?(view, "#item-#{item.id}-picker")

      choose(view, item, "Another taxon…")

      assert has_element?(
               view,
               "#item-#{item.id}-choices [data-chosen] #item-#{item.id}-picker[phx-hook=Typeahead]"
             )
    end
  end

  describe "deciding" do
    test "Decide is disabled until an answer is chosen, then says what it does and closes the row",
         %{conn: conn} do
      %{package: package} = awaiting!()
      hedge = open_item(package, :set_aside_statement)
      {:ok, view, _html} = step(conn, package, "hedges")
      open_row(view, hedge)

      assert has_element?(view, "#item-#{hedge.id}-decide[disabled]")
      assert has_element?(view, "#item-#{hedge.id}-effect", "Choose an answer above.")

      choose(view, hedge, "Leave it out")
      refute has_element?(view, "#item-#{hedge.id}-decide[disabled]")
      refute has_element?(view, "#item-#{hedge.id}-effect", "Choose an answer above.")

      view |> element("#item-#{hedge.id}-decide") |> render_click()
      assert render(view) =~ "Decision recorded."

      assert %QueueItem{status: :decided, decision: %{"keep" => true}} =
               Import.get_queue_item!(hedge.id)

      # The row stays, closed, with its answer.
      refute has_element?(view, "#item-#{hedge.id}-detail")
      assert has_element?(view, "#item-#{hedge.id}-row[aria-expanded=false]")
      assert has_element?(view, "#item-#{hedge.id}-row [data-role=answer]", "Leave it out")
      assert has_element?(view, "#step-done", "Hedges is settled")

      # Open, a decided row says what was decided.
      open_row(view, hedge)
      assert has_element?(view, "#item-#{hedge.id}-decided", "Leave it out")
      refute has_element?(view, "#item-#{hedge.id}-decide")
    end

    test "a choice with a picker waits for the pick, then decides through it", %{conn: conn} do
      %{package: package} = awaiting!()
      alpha = taxon_fixture(name: "Decidus alpha", kingdom: "Animalia")

      # A name Gallformers doesn't hold, with no candidate.
      item =
        package
        |> Import.list_queue_items(kind: :unresolved_name)
        |> Enum.find(&(&1.subject["name_as_written"] == "Torymus"))

      {:ok, view, _html} = step(conn, package, "names")
      assert has_element?(view, "#section-which_taxon #item-#{item.id}", "Torymus")

      open_row(view, item)
      choose(view, item, "Another taxon…")

      assert has_element?(view, "#item-#{item.id}-decide[disabled]")
      assert has_element?(view, "#item-#{item.id}-effect", "Pick a taxon from the search.")

      view
      |> with_target("#item-row-#{item.id}")
      |> render_hook("search_taxon", %{"value" => "Decidus"})

      view
      |> element("#item-#{item.id}-picker-results button", "Decidus alpha")
      |> render_click()

      refute has_element?(view, "#item-#{item.id}-decide[disabled]")

      view |> element("#item-#{item.id}-decide") |> render_click()
      assert render(view) =~ "Decision recorded."
      assert Import.get_queue_item!(item.id).decision == %{"taxon_id" => alpha.id}
    end

    test "a Host name: another plant, found by name, takes the Source's spelling", %{conn: conn} do
      %{package: package, batch: batch} = awaiting!()
      plant = plant_fixture(name: "Quercus douglasii")
      host = open_item(package, :unresolved_host)
      {:ok, view, _html} = step(conn, package, "names")

      open_row(view, host)
      choose(view, host, "Another plant…")

      view
      |> with_target("#item-row-#{host.id}")
      |> render_hook("search_plant", %{"value" => "Quercus doug"})

      view
      |> element("#item-#{host.id}-picker-results button", "Quercus douglasii")
      |> render_click()

      view |> element("#item-#{host.id}-decide") |> render_click()
      assert render(view) =~ "Decision recorded."

      assert Import.get_queue_item!(host.id).decision["taxon_id"] == plant.id
      assert Import.get_batch!(batch.id).status == :ready
    end

    test "an item settled elsewhere says so", %{conn: conn} do
      %{package: package} = awaiting!()
      hedge = open_item(package, :set_aside_statement)
      {:ok, view, _html} = step(conn, package, "hedges")

      open_row(view, hedge)
      choose(view, hedge, "Leave it out")
      Repo.delete!(hedge)
      html = view |> element("#item-#{hedge.id}-decide") |> render_click()

      assert html =~ "Another decision settled this item"
    end
  end

  describe "notes" do
    test "a note saves on its own, without deciding", %{conn: conn} do
      %{package: package} = awaiting!()
      hedge = open_item(package, :set_aside_statement)
      {:ok, view, _html} = step(conn, package, "hedges")

      open_row(view, hedge)
      # The note is always there, apart from the decision.
      assert has_element?(view, "#item-#{hedge.id}-note-form textarea[placeholder]")

      view
      |> form("#item-#{hedge.id}-note-form", %{"note" => "   "})
      |> render_submit()

      assert has_element?(view, "#item-#{hedge.id}-error", "Write the note first.")
      assert Import.list_notes(hedge) == []

      view
      |> form("#item-#{hedge.id}-note-form", %{"note" => "Woody, but no value fits."})
      |> render_submit()

      assert has_element?(view, "#item-#{hedge.id}-notes", "Woody, but no value fits.")
      assert has_element?(view, "#item-#{hedge.id}-notes", "Rita Reviewer")
      assert [%{text: "Woody, but no value fits."}] = Import.list_notes(hedge)
      assert %QueueItem{status: :open, decision: nil} = Import.get_queue_item!(hedge.id)

      # Deciding leaves the note out of the decision, and the note stays.
      choose(view, hedge, "Leave it out")
      view |> element("#item-#{hedge.id}-decide") |> render_click()
      assert render(view) =~ "Decision recorded."
      assert Import.get_queue_item!(hedge.id).decision == %{"keep" => true}
      assert has_element?(view, "#item-#{hedge.id}-notes", "Woody, but no value fits.")
    end

    test "an old decision's note shows once, as a note", %{conn: conn} do
      %{package: package} = awaiting!()
      hedge = open_item(package, :set_aside_statement)

      {:ok, _} =
        Import.decide_queue_item(test_actor(), hedge, %{"keep" => true, "note" => "Old note."})

      {:ok, view, _html} = step(conn, package, "hedges")

      assert has_element?(view, "#item-#{hedge.id}-notes", "Old note.")
      assert length(String.split(render(view), "Old note.")) == 2
    end
  end

  describe "proposals" do
    test "Reject drops the recommendation and keeps the item open; Undo restores it",
         %{conn: conn} do
      %{package: package} = awaiting!()
      hedge = open_item(package, :set_aside_statement)
      {:ok, view, _html} = step(conn, package, "hedges")
      open_row(view, hedge)

      view |> element("#item-#{hedge.id}-reject") |> render_click()

      item = Import.get_queue_item!(hedge.id)
      assert item.status == :open
      assert %DateTime{} = item.proposal_rejected_at
      assert has_element?(view, "#item-#{hedge.id}-row", "Recommendation rejected")
      refute has_element?(view, "#item-#{hedge.id}-choices [data-role=recommended]")
      assert has_element?(view, "#item-#{hedge.id}-detail")

      view |> element("#item-#{hedge.id}-restore") |> render_click()

      assert Import.get_queue_item!(hedge.id).proposal_rejected_at == nil
      assert has_element?(view, "#item-#{hedge.id}-choices [data-role=recommended]")
    end

    test "Leave the rest out leaves a rejected recommendation open", %{conn: conn} do
      second = %{
        @unmapped
        | "term" => "larval",
          "evidence" => [%{"item" => "#/texts/3", "quote" => "gall wasp larva"}]
      }

      %{package: package} = awaiting!([@unmapped, second])
      [first, other] = Import.list_queue_items(package, kind: :set_aside_statement)
      {:ok, _} = Import.reject_proposal(test_actor(), other)

      {:ok, view, _html} = step(conn, package, "hedges")
      section = "#section-hedge_other"
      refute has_element?(view, "#{section} [id^=bulk-]")

      html =
        view
        |> element("#{section} #leave-rest-hedge_other", "Leave the rest out (1)")
        |> render_click()

      assert html =~ "Left 1 hedge out."
      assert Import.get_queue_item!(first.id).decision == %{"keep" => true}
      assert Import.get_queue_item!(other.id).status == :open
    end
  end

  describe "names held by several species" do
    test "compare the candidates with what the Source says", %{conn: conn} do
      %{package: package, batch: batch} = awaiting!()
      alpha = taxon_fixture(name: "Candidus alpha", kingdom: "Animalia")
      beta = taxon_fixture(name: "Candidus beta", kingdom: "Animalia")

      item =
        %QueueItem{}
        |> QueueItem.create_changeset(%{
          package_id: package.id,
          batch_id: batch.id,
          kind: :ambiguous_match,
          statement_ref: "t3",
          subject: %{"name_as_written" => "Torymus", "rank" => "genus"},
          proposal: %{"candidate_ids" => [alpha.id, beta.id]}
        })
        |> Repo.insert!()

      {:ok, view, _html} = step(conn, package, "names")
      assert has_element?(view, "#section-which_taxon #item-#{item.id}")

      open_row(view, item)
      comparison = "#item-#{item.id}-detail [data-role=comparison]"
      assert has_element?(view, comparison, "Candidus alpha")
      assert has_element?(view, comparison, "Candidus beta")
      assert has_element?(view, comparison, "Ashmead 1897")
    end
  end
end
