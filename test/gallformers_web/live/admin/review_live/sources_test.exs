defmodule GallformersWeb.Admin.ReviewLive.SourcesTest do
  @moduledoc """
  The Sources to review (`/admin/review`, `6611` Task 6): each Source with
  work waiting, its packages grouped under it, with how much is left to
  decide, how much has a proposed answer, what holds approval and its
  status; filtered and sorted; each opening the Source's page.

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

  import Ecto.Query, only: [from: 2]

  alias Gallformers.Import
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.QueueItem
  alias Gallformers.Repo

  # Signing in makes the admin the test's actor, so it comes first.
  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    %{conn: conn}
  end

  setup :audit_test_metadata

  # A delivered package awaiting review, of a new Source (not matched until
  # it is applied). "Q. lobata" names no plant here, so its gall batch waits
  # on an open Host name.
  defp awaiting!(title \\ "Galls of the oaks", citation \\ nil) do
    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], title)
      |> put_in(["source", "citation"], citation || "Ashmead, W. H. 1897. #{title}.")
      |> put_in(["source", "authors"], ["Ashmead, W. H."])

    package(gall: gall) |> with_review() |> deliver!()
  end

  # The row of a package's Source on the list.
  defp row(%{source_id: nil, id: id}), do: "#package-#{id}"
  defp row(%{source_id: id}), do: "#source-#{id}"

  # A delivered package with nothing to decide.
  defp ready! do
    load_vocab!()
    plant_fixture(name: "Quercus lobata")
    taxon_fixture(name: "Andricus quercuscalifornicus", kingdom: "Animalia")
    taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")

    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "A ready paper")
      |> put_in(["source", "citation"], "Ready, A. 2001. A ready paper.")
      |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
      |> put_in(["galls", Access.at(0), "new"], true)

    package = package(gall: gall) |> with_review() |> deliver!()
    assert Import.list_queue_items(package) == []
    package
  end

  test "lists a delivered package's Source with its counts, and opens its page", %{conn: conn} do
    package = awaiting!()
    assert package.source_id == nil
    open = Import.list_queue_items(package)
    assert open != []

    {:ok, view, html} = live(conn, ~p"/admin/review")
    assert html =~ "Sources to review"

    row = row(package)
    assert has_element?(view, row, "Galls of the oaks")
    assert has_element?(view, row, "Ashmead, W. H. 1897. Galls of the oaks.")
    assert has_element?(view, "#{row} [data-role=to-decide]", "#{length(open)}")
    assert has_element?(view, "#{row} [data-role=holding]", "Host plants")
    assert has_element?(view, row, "Awaiting review")

    # No package keys, file names or refs.
    refute render(element(view, row)) =~ package.key
    refute render(element(view, row)) =~ "gall.json"

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> element("#{row} a", "Galls of the oaks") |> render_click()

    # A Source opens at its first step with work left.
    assert to == ~p"/admin/review/packages/#{package.id}/names"
  end

  test "groups the packages of a Source Gallformers holds under it", %{conn: conn} do
    source = source_fixture("Ashmead, W. H. 1897. Galls of the oaks", "1897")
    first = awaiting!("Galls of the oaks", source.citation)
    second = awaiting!("Galls of the oaks", source.citation)
    assert first.source_id == source.id and second.source_id == source.id

    open = length(Import.list_queue_items(first)) + length(Import.list_queue_items(second))

    {:ok, view, _html} = live(conn, ~p"/admin/review")

    assert has_element?(view, "#source-#{source.id}", source.title)
    assert has_element?(view, "#source-#{source.id} [data-role=to-decide]", "#{open}")
    refute has_element?(view, "#package-#{first.id}")

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> element("#source-#{source.id} a", source.title) |> render_click()

    assert to == ~p"/admin/review/sources/#{source.id}/names"
  end

  test "the Gallformers notes are one Source, listing its notes", %{conn: conn} do
    gallformers = gallformers_source()

    notes =
      for _ <- 1..2 do
        batch()
        |> unique_batch_id()
        |> Map.put("source", %{"gallformers" => true})
        |> then(&batch_files([{"gall.json", &1}]))
        |> deliver!(review: false)
      end

    assert Enum.map(notes, &{&1.source_id, &1.status}) ==
             List.duplicate({gallformers.id, :awaiting_review}, 2)

    {:ok, view, _html} = live(conn, ~p"/admin/review")
    assert has_element?(view, "#source-#{gallformers.id}", "Gallformers ID Notes")
    assert has_element?(view, "#source-#{gallformers.id}", "2 notes")

    # Each waits on a Host name ("Q. lobata"), so it needs the curator.
    {:ok, page, _html} = live(conn, ~p"/admin/review/sources/#{gallformers.id}?tab=needs")

    for note <- notes do
      assert has_element?(page, "#note-#{note.id}", "the large stem galls")

      assert has_element?(
               page,
               "#note-#{note.id} a[href='/admin/review/packages/#{note.id}']",
               "View the note"
             )
    end
  end

  test "filters Sources that need decisions from those ready to approve", %{conn: conn} do
    waiting = awaiting!()
    ready = ready!()

    {:ok, view, _html} = live(conn, ~p"/admin/review")
    assert has_element?(view, row(waiting))
    refute has_element?(view, row(ready))

    view |> element("#filter-ready") |> render_click()
    refute has_element?(view, row(waiting))
    assert has_element?(view, row(ready), "Ready to approve")

    view |> element("#filter-all") |> render_click()
    assert has_element?(view, row(waiting))
    assert has_element?(view, row(ready))
  end

  test "sorts by most to decide", %{conn: conn} do
    _few = awaiting!("Few questions")
    many = awaiting!("Many questions")

    # One more open question for the second Source.
    [batch] = Import.list_batches(Import.get_package!(many.id))

    %QueueItem{}
    |> QueueItem.create_changeset(%{
      package_id: many.id,
      batch_id: batch.id,
      kind: :unresolved_name,
      statement_ref: "t9",
      subject: %{"name_as_written" => "Extra name"},
      proposal: %{}
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/admin/review?filter=all")

    html = view |> form("#review-sort", sort: "most") |> render_change()
    assert index(html, "Many questions") < index(html, "Few questions")

    html = view |> form("#review-sort", sort: "close") |> render_change()
    assert index(html, "Few questions") < index(html, "Many questions")
  end

  test "To decide counts the questions; terms set aside are counted apart", %{conn: conn} do
    unmapped = %{
      "term" => "lignified",
      "slot" => "texture",
      "gall" => "g1",
      "evidence" => [%{"item" => "#/texts/3", "whole_item" => true}],
      "note" => "No texture value for woody galls."
    }

    gall = batch() |> unique_batch_id() |> Map.put("unmapped", [unmapped])
    package = package(gall: gall) |> with_review() |> deliver!()
    open = Import.list_queue_items(package)
    questions = Enum.reject(open, &(&1.kind in [:trait_term, :set_aside_statement]))
    assert length(questions) < length(open)

    {:ok, view, _html} = live(conn, ~p"/admin/review")
    assert has_element?(view, "#{row(package)} [data-role=to-decide]", "#{length(questions)}")
    assert has_element?(view, "#{row(package)} [data-role=set-aside]", "1 set aside")
  end

  test "the list names a section as the Source's page does", %{conn: conn} do
    package = awaiting!()
    [batch] = Import.list_batches(package)
    taxon = taxon_fixture(name: "Andricus quercuscalifornica", kingdom: "Animalia")

    # The resolver proposed a taxon the Source calls new under another spelling.
    Repo.update_all(
      from(s in BatchStatement,
        where: s.batch_id == ^batch.id and s.ref == "t1"
      ),
      set: [
        resolution: :ambiguous,
        method: "spelling_variant",
        detail: %{
          "new_status" => "new species",
          "name_as_written" => "Andricus quercuscalifornicus"
        }
      ]
    )

    %QueueItem{}
    |> QueueItem.create_changeset(%{
      package_id: package.id,
      batch_id: batch.id,
      kind: :ambiguous_match,
      statement_ref: "t1",
      subject: %{"name_as_written" => "Andricus quercuscalifornicus"},
      proposal: %{"candidate_ids" => [taxon.id], "proposed" => taxon.id}
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/admin/review")

    assert has_element?(
             view,
             "#{row(package)} [data-role=holding]",
             "Which taxon is it"
           )
  end

  defp index(html, text) do
    {i, _} = :binary.match(html, text)
    i
  end
end
