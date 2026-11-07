defmodule GallformersWeb.Admin.SourceFactsTest do
  @moduledoc """
  The admin Source page's Facts (matter `f14c`, "The Source's Facts after
  approval"): the Source's applied Facts in the same Facts view as the
  review's Facts page and the public Source page, in a corrections mode.
  Each correctable Fact has a small menu: withdraw the Source's statement
  (it didn't say it), or move it to what it did say (another Host, Trait
  value, parent or accepted taxon), each with a required note
  (`Gallformers.Import.correct_source_fact/6`). A taxonomic statement
  stated anew can be accepted in the same step. The corrections are
  listed, and move the Source's Updated date. A Source stating Facts about
  very many Galls (the legacy data) shows one Gall at a time, found by
  search.

  Not async: the Catalog vocabularies are loaded, and one test lowers how
  many Facts the page shows at once (application env).
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1, test_actor: 0]
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Catalog
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Import
  alias Gallformers.Sources
  alias Gallformers.Taxa

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Cora Corrector")
    %{conn: conn}
  end

  setup :audit_test_metadata

  setup do
    load_vocab!()
    rubus = taxon_fixture(rank: :genus, name: "Rubus", kingdom: "Plantae")

    %{
      legacy: Sources.get_legacy_data_source(),
      paper: source_fixture("InfluentialPoints", "2026"),
      gall: gall_fixture(),
      rubus: rubus,
      frondosus: plant_fixture(name: "Rubus frondosus", parent: rubus)
    }
  end

  defp host!(gall, plant, attribution) do
    {:ok, %{fact: fact}} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: plant.id, object_gall_id: gall.id},
        attribution
      )

    fact
  end

  defp page(conn, source) do
    {:ok, view, _html} = live(conn, ~p"/admin/sources/#{source.id}")
    render_async(view)
    view
  end

  defp row(fact), do: "#fact-f#{fact.id}"

  defp open_editor(view, row, kind) do
    view |> element("#{row}-edit-#{kind}") |> render_click()
    assert has_element?(view, "#correction-editor")
  end

  describe "the Source's Facts" do
    test "show in the Facts view, each correctable Fact with its corrections", ctx do
      fact = host!(ctx.gall, ctx.rubus, confirm(ctx.paper))
      view = page(ctx.conn, ctx.paper)

      assert has_element?(view, "#source-facts")
      assert has_element?(view, row(fact), "Rubus")
      assert has_element?(view, "#{row(fact)}-edit-withdraw")
      assert has_element?(view, "#{row(fact)}-edit-host")
      refute has_element?(view, "#{row(fact)}-edit-values")
    end

    test "a Source with none says so", ctx do
      view = page(ctx.conn, ctx.paper)
      assert has_element?(view, "#source-facts", "states no Facts")
    end
  end

  describe "withdrawing" do
    test "the legacy data's genus Host, with a note: gone from the Source, listed", ctx do
      fact = host!(ctx.gall, ctx.rubus, confirm(ctx.legacy, %{stated: nil}))
      _ = host!(ctx.gall, ctx.rubus, confirm(ctx.paper))
      view = ctx.conn |> page(ctx.legacy) |> find_gall(ctx.gall)
      open_editor(view, row(fact), "withdraw")

      view |> form("#correction-editor", %{"note" => ""}) |> render_submit()
      assert has_element?(view, "#correction-editor-error", "note")
      assert %Attribution{} = Facts.get_attribution(fact.id, ctx.legacy.id)

      view
      |> form("#correction-editor", %{"note" => "InfluentialPoints names species only."})
      |> render_submit()

      render_async(view)

      assert Facts.get_attribution(fact.id, ctx.legacy.id) == nil
      assert %Attribution{} = Facts.get_attribution(fact.id, ctx.paper.id)
      refute has_element?(view, row(fact))
      refute has_element?(view, "#correction-editor")
      assert has_element?(view, "#source-corrections", "Withdrew")
      assert has_element?(view, "#source-corrections", "InfluentialPoints names species only.")
      assert has_element?(view, "#source-corrections", "Cora Corrector")
      assert has_element?(view, "#source-dates", "updated")
    end

    test "cancel closes the editor and changes nothing", ctx do
      fact = host!(ctx.gall, ctx.rubus, confirm(ctx.paper))
      view = page(ctx.conn, ctx.paper)

      open_editor(view, row(fact), "withdraw")
      view |> element("#correction-editor-cancel") |> render_click()

      refute has_element?(view, "#correction-editor")
      assert %Attribution{} = Facts.get_attribution(fact.id, ctx.paper.id)
    end
  end

  describe "stating what the Source said" do
    test "another Host, picked by search", ctx do
      fact = host!(ctx.gall, ctx.rubus, confirm(ctx.paper, %{value_as_written: "Rubus"}))
      view = page(ctx.conn, ctx.paper)

      open_editor(view, row(fact), "host")

      view
      |> with_target("#source-facts-corrections")
      |> render_hook("search_taxon", %{"value" => "Rubus frond"})

      view
      |> element("#correction-editor-taxon-results button", "Rubus frondosus")
      |> render_click()

      view
      |> form("#correction-editor", %{"note" => "It is var. frondosus."})
      |> render_submit()

      render_async(view)

      {:ok, moved} = Catalog.find_gall_fact(ctx.gall.id, {:host, ctx.frondosus.id})
      assert Facts.get_attribution(moved, ctx.paper.id).value_as_written == "Rubus"
      assert Facts.get_attribution(fact.id, ctx.paper.id) == nil
      assert has_element?(view, "#fact-f#{moved}", "Rubus frondosus")
      assert has_element?(view, "#source-corrections", "Rubus frondosus")
    end

    test "another Trait value", ctx do
      {:ok, %{fact: red}} =
        Catalog.assert_trait(
          test_actor(),
          %{gall_id: ctx.gall.id, trait: "color", value: "red"},
          confirm(ctx.paper)
        )

      view = page(ctx.conn, ctx.paper)
      open_editor(view, row(red), "values")
      assert has_element?(view, "#correction-editor-values-red[checked]")

      view |> element("#correction-editor-values-red") |> render_click()
      view |> element("#correction-editor-values-brown") |> render_click()
      view |> form("#correction-editor", %{"note" => "Brown on the plate."}) |> render_submit()
      render_async(view)

      {:ok, brown} = Catalog.find_gall_fact(ctx.gall.id, {:trait, "color", "brown"})
      assert %Attribution{} = Facts.get_attribution(brown, ctx.paper.id)
      assert Facts.get_attribution(red.id, ctx.paper.id) == nil
    end

    test "another parent for a placement, accepted in the same step", ctx do
      family = taxon_fixture(rank: :family, name: "Aphididae", kingdom: "Animalia")
      aphis = taxon_fixture(rank: :genus, name: "Aphis", kingdom: "Animalia", parent: family)

      other =
        taxon_fixture(rank: :genus, name: "Amphorophora", kingdom: "Animalia", parent: family)

      species = taxon_fixture(name: "Aphis rubifolii", kingdom: "Animalia", parent: aphis)

      {:ok, %{fact: placement, attribution: attribution}} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: species.id, parent_id: aphis.id},
          confirm(ctx.paper)
        )

      {:ok, _} = Import.TaxonomicDecisions.decide(test_actor(), :accept, attribution.id)

      view = page(ctx.conn, ctx.paper)
      open_editor(view, row(placement), "parent")
      assert has_element?(view, "#correction-editor-accept")

      view
      |> with_target("#source-facts-corrections")
      |> render_hook("search_taxon", %{"value" => "Amphoro"})

      view
      |> element("#correction-editor-taxon-results button", "Amphorophora")
      |> render_click()

      view
      |> form("#correction-editor", %{"note" => "Moved in the paper.", "accept" => "true"})
      |> render_submit()

      render_async(view)

      assert Taxa.get_taxon!(species.id).parent_id == other.id
      assert has_element?(view, "#facts-taxonomy", "accepted")
    end
  end

  describe "a Source stating Facts about very many Galls" do
    setup do
      previous = Application.get_env(:gallformers, GallformersWeb.Admin.SourceLive.Facts)
      Application.put_env(:gallformers, GallformersWeb.Admin.SourceLive.Facts, all_limit: 1)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:gallformers, GallformersWeb.Admin.SourceLive.Facts, previous),
          else: Application.delete_env(:gallformers, GallformersWeb.Admin.SourceLive.Facts)
      end)
    end

    test "shows one Gall at a time, found by search", ctx do
      fact = host!(ctx.gall, ctx.rubus, confirm(ctx.paper))
      other = host!(gall_fixture(), ctx.frondosus, confirm(ctx.paper))
      view = page(ctx.conn, ctx.paper)

      assert has_element?(view, "#source-facts", "Find a Gall")
      refute has_element?(view, row(fact))

      view = find_gall(view, ctx.gall)

      assert has_element?(view, row(fact))
      refute has_element?(view, row(other))
    end
  end

  # Finds `gall` with the Facts' Gall search and picks it.
  defp find_gall(view, gall) do
    name = gall.id |> Catalog.get_gall!() |> Catalog.Gall.display_name()

    view
    |> with_target("#source-facts-corrections")
    |> render_hook("search_gall", %{"value" => name})

    view |> element("#source-facts-gall-results button", name) |> render_click()
    render_async(view)
    view
  end
end
