defmodule GallformersWeb.Admin.ReviewLive.StepTest do
  @moduledoc """
  A Source's review in steps (matter `d213`, Task 15): the overview
  (`/admin/review/sources/:id`, `/admin/review/packages/:id`) with each
  step's status, a page per step (`…/names`, `galls`, `disputes`, `traits`,
  `hedges`) with Previous and Next, and the step bar on every page, where
  Approve appears once nothing holds approval and asks to confirm.

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

  # A package awaiting review, by Ashmead: its Host and two names wait in
  # Names (holding approval), a hedged statement in Hedges.
  defp awaiting! do
    load_vocab!()

    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "Galls of the oaks")
      |> put_in(["source", "authored"], %{"date" => "1897", "as_written" => "1897"})
      |> put_in(["source", "authors"], ["Ashmead, W. H."])
      |> Map.put("unmapped", [@unmapped])

    package(gall: gall) |> with_review() |> deliver!()
  end

  # A package whose names all resolve: only its hedged statement is open.
  defp settled! do
    plant_fixture(name: "Quercus lobata")
    taxon_fixture(name: "Andricus quercuscalifornicus", kingdom: "Animalia")
    taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")
    load_vocab!()

    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "A ready paper")
      |> put_in(["source", "authors"], ["Ashmead, W. H."])
      |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
      |> put_in(["galls", Access.at(0), "new"], true)
      |> Map.put("unmapped", [@unmapped])

    package(gall: gall) |> with_review() |> deliver!()
  end

  defp open_items(package), do: Import.list_queue_items(package)

  defp overview(conn, package), do: live(conn, ~p"/admin/review/packages/#{package.id}")

  defp step(conn, package, step),
    do: live(conn, ~p"/admin/review/packages/#{package.id}/#{step}")

  describe "the overview" do
    test "names the Source by its short name, with a row per step", %{conn: conn} do
      package = awaiting!()
      open = open_items(package)
      names = Enum.count(open, &(&1.kind in [:unresolved_host, :unresolved_name]))

      {:ok, view, html} = overview(conn, package)

      assert has_element?(view, "h1", "Ashmead 1897")
      assert html =~ "Galls of the oaks"

      assert has_element?(view, "#overview-names", "Names")
      assert has_element?(view, "#overview-names", "Which organisms does the Source mean?")
      assert has_element?(view, "#overview-names", "#{names} of #{names} left")
      assert has_element?(view, "#overview-names", "with a recommended answer")
      assert has_element?(view, "#overview-names", "Holds approval")

      assert has_element?(view, "#overview-hedges", "1 of 1 left")
      assert has_element?(view, "#overview-hedges", "Doesn't hold approval")
      assert has_element?(view, "#overview-disputes", "All settled")

      # Continue goes to the first step with work left.
      assert has_element?(
               view,
               "#continue[href='/admin/review/packages/#{package.id}/names']",
               "Continue: Names"
             )

      # The questions themselves are on the step pages.
      refute has_element?(view, "#section-hosts")
    end

    test "a Source Gallformers holds has its overview and steps at its own path", %{conn: conn} do
      source = source_fixture("Ashmead, W. H. 1897. Galls of the oaks", "1897")

      gall =
        batch()
        |> unique_batch_id()
        |> put_in(["source", "title"], "Galls of the oaks")
        |> put_in(["source", "citation"], source.citation)

      package = package(gall: gall) |> with_review() |> deliver!()
      assert package.source_id == source.id
      host = Enum.find(open_items(package), &(&1.kind == :unresolved_host))

      {:ok, view, _html} = live(conn, ~p"/admin/review/sources/#{source.id}")
      assert has_element?(view, "h1", "Weld 1897")
      assert has_element?(view, "#continue[href='/admin/review/sources/#{source.id}/names']")

      {:ok, view, _html} = live(conn, ~p"/admin/review/sources/#{source.id}/names")
      assert has_element?(view, "#section-hosts #item-#{host.id}", "Q. lobata")
    end
  end

  describe "a step page" do
    test "shows its sections, with what step it is and whether it holds approval",
         %{conn: conn} do
      package = awaiting!()
      host = Enum.find(open_items(package), &(&1.kind == :unresolved_host))
      hedge = Enum.find(open_items(package), &(&1.kind == :set_aside_statement))

      {:ok, view, _html} = step(conn, package, "names")

      assert has_element?(view, "#step-head", "Step 1 of 5 · holds approval")
      assert has_element?(view, "#step-head h2", "Names")
      assert has_element?(view, "#step-head", "Which organisms does the Source mean?")
      assert has_element?(view, "#section-hosts #item-#{host.id}")
      refute has_element?(view, "#item-#{hedge.id}")
      refute has_element?(view, "#step-done")

      # Previous goes to the overview, Next to Galls.
      assert has_element?(view, "#step-prev[href='/admin/review/packages/#{package.id}']")

      assert has_element?(
               view,
               "#step-next[href='/admin/review/packages/#{package.id}/galls']",
               "Next: Galls"
             )

      {:ok, view, _html} = step(conn, package, "hedges")
      assert has_element?(view, "#step-head", "Step 5 of 5 · doesn't hold approval")
      assert has_element?(view, "#section-hedge_other #item-#{hedge.id}")
      assert has_element?(view, "#step-prev[href='/admin/review/packages/#{package.id}/traits']")
      assert has_element?(view, "#step-next[href='/admin/review/packages/#{package.id}']")
    end

    test "a settled step says so and offers the next one", %{conn: conn} do
      package = awaiting!()
      {:ok, view, _html} = step(conn, package, "disputes")

      assert has_element?(view, "#step-done", "✓ Disputes is settled.")

      assert has_element?(
               view,
               "#step-done a[href='/admin/review/packages/#{package.id}/traits']",
               "Next: Traits"
             )
    end

    test "an unknown step goes to the overview", %{conn: conn} do
      package = awaiting!()
      path = ~p"/admin/review/packages/#{package.id}"

      assert {:error, {:live_redirect, %{to: ^path}}} = step(conn, package, "nonsense")
    end
  end

  describe "the step bar" do
    test "shows each step with what's left or a check, and marks what holds approval",
         %{conn: conn} do
      package = awaiting!()
      open = open_items(package)
      names = Enum.count(open, &(&1.kind in [:unresolved_host, :unresolved_name]))

      {:ok, view, _html} = step(conn, package, "names")

      assert has_element?(view, "#step-bar-overview[href='/admin/review/packages/#{package.id}']")
      assert has_element?(view, "#step-bar-names[aria-current=page]")
      assert has_element?(view, "#step-bar-names [data-role=left]", "#{names}")
      assert has_element?(view, "#step-bar-names [data-role=holds]")
      assert has_element?(view, "#step-bar-disputes [data-role=done]")
      assert has_element?(view, "#step-bar-hedges [data-role=left]", "1")
      refute has_element?(view, "#step-bar-hedges [data-role=holds]")

      assert has_element?(
               view,
               "#approve-wait",
               "Approve appears once Names is settled"
             )

      refute has_element?(view, "#approve-open")
    end

    test "Approve appears once nothing holds approval, and asks before applying",
         %{conn: conn} do
      package = settled!()
      {:ok, view, _html} = overview(conn, package)

      refute has_element?(view, "#approve-wait")
      refute has_element?(view, "#approve-confirm")

      view |> element("#approve-open", "Approve…") |> render_click()

      assert has_element?(view, "#approve-confirm", "Approving applies this Source's Facts")
      assert has_element?(view, "#approve-confirm", "1 hedge is still open")
      assert has_element?(view, "#approve-confirm", "can be settled after")
      assert %Package{status: :awaiting_review} = Import.get_package!(package.id)

      view |> element("#approve-cancel") |> render_click()
      refute has_element?(view, "#approve-confirm")

      view |> element("#approve-open") |> render_click()
      html = view |> element("#approve", "Approve and apply") |> render_click()

      assert html =~ "approved"
      assert %Package{status: :approved} = Import.get_package!(package.id)
      assert has_element?(view, "#step-bar", "Approved")
    end

    test "is on every step page", %{conn: conn} do
      package = settled!()
      {:ok, view, _html} = step(conn, package, "hedges")

      assert has_element?(view, "#step-bar-hedges[aria-current=page]")
      assert has_element?(view, "#approve-open")
    end
  end
end
