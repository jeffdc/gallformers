defmodule GallformersWeb.Admin.ReviewLive.FactsTest do
  @moduledoc """
  A Source's Facts page (matter `f14c`, item 4): what approving writes,
  given the answers so far (`Gallformers.Import.preview_package/2`),
  grouped by Gall and category, each Fact marked new, held, in conflict,
  waiting on a question (a link to it) or dropped; whether the Source is
  ready to approve; edits (drop, change a Host, change a Trait's values, a
  note) and their undo. An approved package shows the Source's applied
  Facts, read-only.

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

  alias Gallformers.Catalog
  alias Gallformers.DoclingFixtures
  alias Gallformers.Import
  alias Gallformers.Taxa

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    %{conn: conn}
  end

  setup :audit_test_metadata

  # -- fixtures ------------------------------------------------------------------

  # The tree the fixture batch resolves against: Quercus with two oaks, the
  # wasp and its Gall (Inducer held from a legacy Source), Torymus.
  defp tree! do
    load_vocab!()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    lobata = plant_fixture(name: "Quercus lobata", parent: quercus)
    douglasii = plant_fixture(name: "Quercus douglasii", parent: quercus)
    andricus = Taxa.get_by_legacy_id(:taxonomy, 33)
    wasp = taxon_fixture(name: "Andricus quercuscalifornicus", parent: andricus)
    taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")
    legacy = source_fixture("Legacy", "1990")
    gall = gall_fixture(name: "Andricus quercuscalifornicus (agamic)", generation: "agamic")

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
        confirm(legacy)
      )

    %{quercus: quercus, lobata: lobata, douglasii: douglasii, wasp: wasp, gall: gall}
  end

  @words "The galls are ovoid, a swelling on the leaf."

  defp doc do
    words = %{
      "self_ref" => "#/texts/5",
      "label" => "text",
      "content_layer" => "body",
      "text" => @words,
      "prov" => [%{"page_no" => 2, "bbox" => %{}, "charspan" => [0, 0]}],
      "children" => []
    }

    DoclingFixtures.document()
    |> Map.update!("texts", &(&1 ++ [words]))
    |> update_in(["body", "children"], &(&1 ++ [%{"$ref" => "#/texts/5"}]))
  end

  # The fixture gall batch (format 4): its Host written in full, an "ovoid"
  # shape the producer places under globular.
  defp gall_batch do
    batch()
    |> unique_batch_id()
    |> Map.put("format_version", 4)
    |> put_in(["source", "title"], "Galls of the oaks")
    |> put_in(["source", "authors"], ["Ashmead, W. H."])
    |> put_in(["source", "authored"], %{"date" => "1897", "as_written" => "1897"})
    |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
    |> Map.update!("facts", fn facts ->
      facts ++
        [
          %{
            "id" => "f6",
            "stance" => "confirm",
            "kind" => "trait",
            "gall" => "g1",
            "trait" => "shape",
            "term" => "ovoid",
            "category" => %{"value" => "globular"},
            "evidence" => [%{"item" => "#/texts/5", "quote" => "ovoid"}]
          }
        ]
    end)
  end

  # A package nothing holds, of a Source Gallformers holds.
  defp ready! do
    tree = tree!()
    source = source_fixture("Ashmead, W. H. 1897. Galls of the oaks", "1897")
    gall = put_in(gall_batch(), ["source", "citation"], source.citation)
    package = package(gall: gall, doc: doc()) |> with_review([], responded: true) |> deliver!()
    Map.put(tree, :package, package)
  end

  # A package whose names wait in Names: nothing in the tree.
  defp waiting! do
    load_vocab!()

    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "Galls of the oaks")
      |> put_in(["source", "authors"], ["Ashmead, W. H."])
      |> put_in(["source", "authored"], %{"date" => "1897", "as_written" => "1897"})

    package(gall: gall) |> with_review() |> deliver!()
  end

  defp facts(conn, package) do
    {:ok, view, _html} = live(conn, ~p"/admin/review/packages/#{package.id}/facts")
    render_async(view)
    view
  end

  defp gall_row(package), do: Enum.find(Import.list_batches(package), &(&1.file == "gall.json"))

  # A Fact's row on the page.
  defp row(package, ref), do: "#fact-b#{gall_row(package).id}-#{ref}"

  defp open_editor(view, row, kind) do
    view |> element("#{row}-edit-#{kind}") |> render_click()
    assert has_element?(view, "#fact-editor")
  end

  # -- the page --------------------------------------------------------------------

  describe "the page" do
    test "is a step of the Source's review, in the bar and on the overview", %{conn: conn} do
      %{package: package} = ready!()
      base = "/admin/review/packages/#{package.id}"

      view = facts(conn, package)
      assert has_element?(view, "h1", "Facts")
      assert has_element?(view, "h1 a[href='/admin/review']", "Sources to review")
      assert has_element?(view, "h1 a[href='#{base}']")
      assert has_element?(view, "#step-bar-facts[aria-current=page]", "Facts")
      assert has_element?(view, "#step-bar-facts", "optional")

      {:ok, step, _html} = live(conn, "#{base}/names")
      assert has_element?(step, "#step-bar-facts[href='#{base}/facts']")

      {:ok, overview, _html} = live(conn, base)

      assert has_element?(
               overview,
               "#overview a[href='#{base}/facts']",
               "See every Fact this Source would add"
             )
    end

    test "a Source's page has its Facts at its own path", %{conn: conn} do
      %{package: package} = ready!()
      {:ok, view, _html} = live(conn, ~p"/admin/review/sources/#{package.source_id}/facts")
      render_async(view)
      assert has_element?(view, "#facts")
      assert has_element?(view, "#step-bar-facts[aria-current=page]")
    end
  end

  describe "the readiness line" do
    test "ready: this is what approving writes", %{conn: conn} do
      %{package: package} = ready!()
      view = facts(conn, package)

      assert has_element?(
               view,
               "#facts-readiness",
               "Ready to approve: this is what approving writes."
             )
    end

    test "not ready: the questions that hold it, by step, each linking to it", %{conn: conn} do
      package = waiting!()
      {:ok, preview} = Import.preview_package(package, test_actor())
      n = preview.blocking.count
      assert n > 0

      view = facts(conn, package)

      assert has_element?(
               view,
               "#facts-readiness",
               "Not ready to approve: #{n} questions still hold it"
             )

      assert has_element?(
               view,
               "#facts-readiness a[href='/admin/review/packages/#{package.id}/names']",
               "Names"
             )
    end
  end

  describe "the Facts" do
    test "grouped by Gall, then by category, each marked", %{conn: conn} = ctx do
      %{package: package, gall: gall} = Map.merge(ctx, ready!())
      view = facts(conn, package)
      group = "#facts-gall-#{gall.id}"

      assert has_element?(view, "#{group} h3", "Andricus quercuscalifornicus (agamic)")
      assert has_element?(view, group, "the large stem galls")
      assert has_element?(view, "#{group} a[href='/gall/#{gall.id}'][target=_blank]", "matches")

      # Inducer held, Host new, the Trait under its Trait, the rest in Other.
      assert has_element?(view, "#{group} [data-category=inducer] #{row(package, "f1")}")
      assert has_element?(view, "#{row(package, "f1")}[data-status=held]")
      assert has_element?(view, "#{group} [data-category=hosts] #{row(package, "f2")}")
      assert has_element?(view, "#{row(package, "f2")}[data-status=new]", "Quercus lobata")
      assert has_element?(view, "#{group} [data-category=traits]", "shape")
      assert has_element?(view, "#{row(package, "f6-globular")}", "globular")
      assert has_element?(view, "#{row(package, "f6-globular")}", "ovoid")
      assert has_element?(view, "#{group} [data-category=other] #{row(package, "f3")}")

      # The Host's quote, and its passage on request.
      assert has_element?(view, row(package, "f2"), "Common on Q. lobata throughout the hills")
      refute has_element?(view, "#{row(package, "f2")} [data-role=passage-text]")
      view |> element("#{row(package, "f2")} [data-role=show-passage]") |> render_click()
      assert has_element?(view, "#{row(package, "f2")} [data-role=passage-text]")

      # Counts, as filter chips.
      assert has_element?(view, "#facts-filter-new", "New")
      view |> element("#facts-filter-new") |> render_click()
      assert has_element?(view, row(package, "f2"))
      refute has_element?(view, row(package, "f1"))
      view |> element("#facts-filter-all") |> render_click()
      assert has_element?(view, row(package, "f1"))
    end

    test "a genus Host shows as one Host Fact on the genus, with its quote", %{conn: conn} do
      tree!()

      gall =
        gall_batch()
        |> Map.update!(
          "taxa",
          &(&1 ++ [%{"ref" => "t4", "name_as_written" => "Quercus", "rank" => "genus"}])
        )
        |> Map.update!("facts", fn facts ->
          facts ++
            [
              %{
                "id" => "f7",
                "stance" => "confirm",
                "kind" => "relationship",
                "type" => "host_of",
                "subject" => "t4",
                "object" => "g1",
                "evidence" => [%{"item" => "#/texts/5", "quote" => "a swelling on the leaf"}]
              }
            ]
        end)

      package = package(gall: gall, doc: doc()) |> with_review([], responded: true) |> deliver!()
      view = facts(conn, package)

      assert has_element?(view, "[data-category=hosts] #{row(package, "f7")}", "Quercus")
      assert has_element?(view, row(package, "f7"), "genus")
      assert has_element?(view, row(package, "f7"), "a swelling on the leaf")
    end

    test "a waiting Fact links to its question on its step page", %{conn: conn} do
      package = waiting!()
      host = Enum.find(Import.list_queue_items(package), &(&1.kind == :unresolved_host))

      view = facts(conn, package)

      assert has_element?(view, "#{row(package, "f2")}[data-status=waiting]")

      assert has_element?(
               view,
               "#{row(package, "f2")} a[href='/admin/review/packages/#{package.id}/names#item-row-#{host.id}']"
             )
    end
  end

  # -- edits -------------------------------------------------------------------------

  describe "edits" do
    test "drop a Fact, with a note, and undo it", %{conn: conn} do
      %{package: package} = ready!()
      view = facts(conn, package)
      f3 = row(package, "f3")

      open_editor(view, f3, "drop")

      view
      |> form("#fact-editor", %{"note" => "Torymus is the gall's inquiline"})
      |> render_submit()

      render_async(view)

      assert [%{kind: :drop, statement_ref: "f3", note: "Torymus is the gall's inquiline"} = edit] =
               Import.list_fact_edits(package)

      assert has_element?(view, "#{f3}[data-status=dropped]")
      assert has_element?(view, f3, "Torymus is the gall's inquiline")
      assert has_element?(view, f3, "Rita Reviewer")

      view |> element("#{f3}-edit-#{edit.id}-undo") |> render_click()
      render_async(view)

      assert Import.list_fact_edits(package) == []
      assert has_element?(view, "#{f3}[data-status=new]")
    end

    test "change a Host to another plant", %{conn: conn} do
      %{package: package, douglasii: douglasii} = ready!()
      view = facts(conn, package)
      f2 = row(package, "f2")

      open_editor(view, f2, "host")

      view
      |> element("#fact-editor-plant")
      |> render_hook("search_plant", %{"value" => "Quercus doug"})

      view
      |> element("#fact-editor-plant-results button", "Quercus douglasii")
      |> render_click()

      view |> form("#fact-editor", %{"note" => ""}) |> render_submit()
      render_async(view)

      assert [%{kind: :host, value: %{"host_taxon_id" => id}}] = Import.list_fact_edits(package)
      assert id == douglasii.id
      assert has_element?(view, f2, "Quercus douglasii")
      assert has_element?(view, f2, "Host changed")
    end

    test "change a Trait's value to several", %{conn: conn} do
      %{package: package} = ready!()
      view = facts(conn, package)

      open_editor(view, row(package, "f6-globular"), "values")
      assert has_element?(view, "#fact-editor-values-globular[checked]")

      view |> element("#fact-editor-values-conical") |> render_click()
      view |> element("#fact-editor-values-globular") |> render_click()
      view |> element("#fact-editor-values-cup") |> render_click()
      view |> form("#fact-editor", %{"note" => ""}) |> render_submit()
      render_async(view)

      assert [%{kind: :trait_value, value: %{"values" => values}}] =
               Import.list_fact_edits(package)

      assert Enum.sort(values) == ["conical", "cup"]
      assert has_element?(view, row(package, "f6-conical"), "conical")
      assert has_element?(view, row(package, "f6-cup"), "cup")
      refute has_element?(view, row(package, "f6-globular"))
    end

    test "a note", %{conn: conn} do
      %{package: package} = ready!()
      view = facts(conn, package)
      f1 = row(package, "f1")

      open_editor(view, f1, "note")
      view |> form("#fact-editor", %{"note" => "Check the generation"}) |> render_submit()
      render_async(view)

      assert [%{kind: :note, note: "Check the generation"}] = Import.list_fact_edits(package)
      assert has_element?(view, f1, "Check the generation")
      refute has_element?(view, "#fact-editor")
    end

    test "cancel closes the editor and changes nothing", %{conn: conn} do
      %{package: package} = ready!()
      view = facts(conn, package)

      open_editor(view, row(package, "f1"), "drop")
      view |> element("#fact-editor-cancel") |> render_click()

      refute has_element?(view, "#fact-editor")
      assert Import.list_fact_edits(package) == []
    end
  end

  describe "an approved package" do
    test "shows the Source's applied Facts, read-only", %{conn: conn} do
      %{package: package} = ready!()
      {:ok, _} = Import.approve_package(test_actor(), package)

      view = facts(conn, package)

      assert has_element?(view, "#facts-applied", "approved")
      assert has_element?(view, "[data-category=hosts]", "Quercus lobata")
      refute has_element?(view, "[data-role=fact-menu]")
      refute has_element?(view, "#facts-readiness")
    end
  end
end
