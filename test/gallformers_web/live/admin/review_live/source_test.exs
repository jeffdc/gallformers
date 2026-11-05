defmodule GallformersWeb.Admin.ReviewLive.SourceTest do
  @moduledoc """
  One Source's review overview (`/admin/review/sources/:id`, `6611` Task 6;
  matter `d213`, Task 15): its summary, what it states, denial, approval
  from the step bar, and "Which Source this is" as a banner. The steps
  (`StepTest`) and the questions (`QuestionTest`) are tested apart.

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
  alias Gallformers.Import.Package
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

  # A delivered package awaiting review, by Ashmead, with a statement set
  # aside.
  # "Q. lobata" names no plant here, so its gall batch waits on a Host name.
  defp awaiting!(unmapped \\ [@unmapped]) do
    load_vocab!()

    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "Galls of the oaks")
      |> put_in(["source", "citation"], "Ashmead, W. H. 1897. Galls of the oaks.")
      |> put_in(["source", "authors"], ["Ashmead, W. H."])
      |> Map.put("unmapped", unmapped)

    package = package(gall: gall) |> with_review() |> deliver!()
    [batch] = Import.list_batches(package)
    %{package: package, batch: batch}
  end

  # A delivered package of `source`, which Gallformers holds.
  defp matched!(source) do
    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "Galls of the oaks")
      |> put_in(["source", "citation"], source.citation)

    package = package(gall: gall) |> with_review() |> deliver!()
    assert package.source_id == source.id
    package
  end

  defp open_item(package, kind),
    do: Enum.find(Import.list_queue_items(package), &(&1.kind == kind))

  # A new Source's package (matched to its Source only once applied) has a
  # page of its own.
  defp page(conn, package), do: live(conn, ~p"/admin/review/packages/#{package.id}")

  defp visible_text(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.text()

  defp open_row(view, item), do: view |> element("#item-#{item.id}-row") |> render_click()

  # Choose the option labelled `label` in an open item.
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

  describe "the overview" do
    test "shows the Source and what it states, with no refs and no questions", %{conn: conn} do
      %{package: package} = awaiting!()
      host = open_item(package, :unresolved_host)

      {:ok, view, html} = page(conn, package)

      assert has_element?(view, "h1", "Ashmead 2024")
      assert html =~ "Galls of the oaks"
      assert html =~ "Ashmead, W. H. 1897. Galls of the oaks."
      assert has_element?(view, "#source-head", "Awaiting review")
      assert has_element?(view, "#source-stats", "Galls")

      # The questions are on the step pages.
      refute has_element?(view, "#item-#{host.id}")

      text = view |> element("#overview") |> render() |> visible_text()
      refute text =~ @ref
      refute text =~ package.key
    end

    test "a Source Gallformers holds shows its packages together", %{conn: conn} do
      source = source_fixture("Ashmead, W. H. 1897. Galls of the oaks", "1897")
      first = matched!(source)
      second = matched!(source)

      hosts =
        Enum.count(Import.list_queue_items(first) ++ Import.list_queue_items(second), fn i ->
          i.kind in [:unresolved_host, :unresolved_name]
        end)

      {:ok, view, html} = live(conn, ~p"/admin/review/sources/#{source.id}")

      assert html =~ source.title
      assert has_element?(view, "#overview-names", "#{hosts} of #{hosts} left")
      assert has_element?(view, "#approve-wait", "Names")
    end

    test "asks “Which Source this is” in a banner, decided there", %{conn: conn} do
      %{package: package, batch: batch} = awaiting!()
      held = source_fixture("Galls of the oaks, again", "1897")

      item =
        %QueueItem{}
        |> QueueItem.create_changeset(%{
          package_id: package.id,
          batch_id: batch.id,
          kind: :ambiguous_match,
          statement_ref: "source",
          subject: %{"title" => "Galls of the oaks", "citation" => "Ashmead 1897."},
          proposal: %{"candidate_ids" => [held.id]}
        })
        |> Repo.insert!()

      {:ok, view, _html} = page(conn, package)

      assert has_element?(view, "#banner #section-source", "Which Source this is")
      assert has_element?(view, "#banner #item-#{item.id}", "Galls of the oaks")
      assert has_element?(view, "#approve-wait", "Which Source this is")

      open_row(view, item)
      assert has_element?(view, "#item-#{item.id}-detail", "a Source Gallformers already holds")
      refute has_element?(view, "#item-#{item.id}-decide:not([disabled])")
      choose(view, item, held.title)
      refute has_element?(view, "#item-#{item.id}-decide[disabled]")
    end
  end

  describe "the Source in Gallformers" do
    # Open questions that count as left: all but what was set aside.
    defp questions_left(package) do
      Enum.count(
        Import.list_queue_items(package),
        &(&1.status == :open and
            &1.kind not in [:set_aside_term, :set_aside_statement, :trait_term])
      )
    end

    test "the overview links back to the Source", %{conn: conn} do
      source = source_fixture("Ashmead, W. H. 1897. Galls of the oaks", "1897")
      matched!(source)

      {:ok, view, _html} = live(conn, ~p"/admin/review/sources/#{source.id}")

      assert has_element?(view, "#source-head a[href='/admin/sources/#{source.id}']")
    end

    test "the Sources list and the Source's page link to its review, with the questions left",
         %{conn: conn} do
      source = source_fixture("Ashmead, W. H. 1897. Galls of the oaks", "1897")
      package = matched!(source)
      left = questions_left(package)
      assert left > 1

      {:ok, view, _html} = live(conn, ~p"/admin/sources")
      view |> form("#source-search-form", %{query: source.title}) |> render_change()

      assert has_element?(
               view,
               "#source-#{source.id} a[href='/admin/review/sources/#{source.id}']",
               "Being reviewed: #{left} questions left"
             )

      {:ok, view, _html} = live(conn, ~p"/admin/sources/#{source.id}")

      assert has_element?(
               view,
               "#source-review a[href='/admin/review/sources/#{source.id}']",
               "Being reviewed: #{left} questions left"
             )
    end
  end

  describe "approval" do
    test "waits, saying for what, while a question that holds it is open", %{conn: conn} do
      %{package: package} = awaiting!()
      {:ok, view, _html} = page(conn, package)

      refute has_element?(view, "#approve-open")
      assert has_element?(view, "#approve-wait", "Approve appears once Names is settled")
      assert has_element?(view, "#overview", "Approve appears once Names is settled.")
    end

    test "with nothing holding it approves the Source's package", %{conn: conn} do
      plant_fixture(name: "Quercus lobata")
      taxon_fixture(name: "Andricus quercuscalifornicus", kingdom: "Animalia")
      taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")
      load_vocab!()

      gall =
        batch()
        |> unique_batch_id()
        |> put_in(["source", "title"], "A ready paper")
        |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
        |> put_in(["galls", Access.at(0), "new"], true)

      package = package(gall: gall) |> with_review() |> deliver!()

      {:ok, view, _html} = page(conn, package)
      assert has_element?(view, "#source-head", "Ready to approve")
      assert has_element?(view, "#overview", "Nothing holds approval")
      refute has_element?(view, "#continue")

      view |> element("#approve-open") |> render_click()
      html = view |> element("#approve") |> render_click()
      assert html =~ "approved"
      assert %Package{status: :approved} = Import.get_package!(package.id)
      assert has_element?(view, "#source-head", "Approved")
    end

    test "deny asks for a reason and denies the package", %{conn: conn} do
      %{package: package} = awaiting!()
      {:ok, view, _html} = page(conn, package)

      view |> element("#deny") |> render_click()
      html = view |> form("#deny-form", deny: %{reason: "  "}) |> render_submit()
      assert html =~ "can&#39;t be blank"

      view |> form("#deny-form", deny: %{reason: "Duplicate delivery."}) |> render_submit()

      assert %Package{status: :denied, denied_reason: "Duplicate delivery."} =
               Import.get_package!(package.id)
    end
  end
end
