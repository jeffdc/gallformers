defmodule GallformersWeb.Admin.ReviewLive.SourceTextTest do
  @moduledoc """
  The Source in context on a step page (matter `d213`, Task 22): every
  quote's "Show the passage", the Source's entry around it with the quoted
  block marked; "Read the Source" on an open question, a panel with the
  whole text, the question's quotes marked and a find box; and neither
  when the package's `document.json` can't be read.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1]
  import Gallformers.ImportFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Import
  alias Gallformers.Storage.Private

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

  # A package awaiting review, with a Host name to resolve ("Q. lobata",
  # quoted from #/texts/2) and a statement set aside (quoted from #/texts/3).
  defp awaiting! do
    load_vocab!()

    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "Galls of the oaks #{System.unique_integer([:positive])}")
      |> Map.put("unmapped", [@unmapped])

    package = package(gall: gall) |> with_review() |> deliver!()
    %{package: package}
  end

  defp open_item(package, kind),
    do: Enum.find(Import.list_queue_items(package), &(&1.kind == kind))

  defp step(conn, package, step),
    do: live(conn, ~p"/admin/review/packages/#{package.id}/#{step}")

  defp open_row(view, item), do: view |> element("#item-#{item.id}-row") |> render_click()

  describe "Show the passage" do
    test "a Host name's quote shows the Source's entry, the quoted block marked", %{conn: conn} do
      %{package: package} = awaiting!()
      host = open_item(package, :unresolved_host)
      {:ok, view, _html} = step(conn, package, "names")
      open_row(view, host)

      passage = "#item-#{host.id}-quotes details[data-role=passage]"
      assert has_element?(view, "#{passage} summary", "Show the passage")

      assert has_element?(
               view,
               "#{passage} [data-cited]",
               "Common on Q. lobata throughout the hills"
             )

      # The rest of the entry is there, not marked; the page is given.
      assert has_element?(view, "#{passage} [data-role=block]", "external parasitoid")
      refute has_element?(view, "#{passage} [data-cited]", "external parasitoid")
      assert has_element?(view, "#{passage} [data-role=page]", "p. 1")
      # The page header is left out.
      refute has_element?(view, passage, "Journal of Examples")
    end

    test "a hedge's quote has its passage too", %{conn: conn} do
      %{package: package} = awaiting!()
      hedge = open_item(package, :set_aside_statement)
      {:ok, view, _html} = step(conn, package, "hedges")
      open_row(view, hedge)

      assert has_element?(
               view,
               "#item-#{hedge.id}-quotes details[data-role=passage] [data-cited]",
               "Torymus developed as an external parasitoid"
             )
    end
  end

  describe "Read the Source" do
    test "opens the whole text, the question's quotes marked; Close shuts it", %{conn: conn} do
      %{package: package} = awaiting!()
      host = open_item(package, :unresolved_host)
      {:ok, view, _html} = step(conn, package, "names")
      refute has_element?(view, "#source-reader")

      open_row(view, host)
      view |> element("#item-#{host.id}-read-source", "Read the Source") |> render_click()

      assert has_element?(view, "aside#source-reader")
      assert has_element?(view, "#source-reader [data-role=question]", "Q. lobata")
      assert has_element?(view, "#source-reader-body [data-cited]", "Common on Q. lobata")
      refute has_element?(view, "#source-reader-body [data-cited]", "external parasitoid")
      assert has_element?(view, "#source-reader-body [data-role=block]", "external parasitoid")
      # The page makes room for it.
      assert has_element?(view, "#step-page[data-reading]")

      view |> element("#source-reader button", "Close") |> render_click()
      refute has_element?(view, "#source-reader")
      refute has_element?(view, "#step-page[data-reading]")
    end

    test "the find box marks what it finds", %{conn: conn} do
      %{package: package} = awaiting!()
      host = open_item(package, :unresolved_host)
      {:ok, view, _html} = step(conn, package, "names")
      open_row(view, host)
      view |> element("#item-#{host.id}-read-source") |> render_click()

      view |> element("#source-reader-find") |> render_change(%{"find" => "douglasii"})

      assert has_element?(view, "#source-reader-body mark", "douglasii")
      assert has_element?(view, "#source-reader-hits", "1 passage")
    end
  end

  describe "without the Source's text" do
    test "no quote has a passage and no question has Read the Source", %{conn: conn} do
      %{package: package} = awaiting!()
      :ok = Private.put(package.s3_prefix <> "document.json", "not json")
      host = open_item(package, :unresolved_host)
      {:ok, view, _html} = step(conn, package, "names")
      open_row(view, host)

      assert has_element?(view, "#item-#{host.id}-quotes", "Common on Q. lobata")
      refute has_element?(view, "#item-#{host.id}-quotes [data-role=passage]")
      refute has_element?(view, "#item-#{host.id}-read-source")
    end
  end
end
