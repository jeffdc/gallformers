defmodule GallformersWeb.SpeciesLiveTest do
  @moduledoc """
  The species page (`/species/:id`, matter `803b`, "The species page"): an
  organism's taxon at species rank or below, not a plant. Its header (name
  with authorship and rank, lineage, common names), its Galls (every
  generation), its taxonomy (where it stands and on whose word, synonyms,
  splits and lumps), its Galls' ranges on one map, the Sources citing it or
  its Galls, and Edit mode (names and placement through "Based on which
  Source?").

  The converted seeds (`priv/repo/test_seeds.sql`): Andricus seedii (genus
  Andricus, tribe Cynipini, family Cynipidae; synonym Callirhytis seedii)
  induces Galls 300 (agamic) and 301 (sexgen), both on plant 10, which has
  a native (US-CA) and introduced (RO-B) range; Gall 300 cites Source 59.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  # Reading the seeds, converted, is most of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures, only: [source_fixture: 2, confirm: 1, plant_fixture: 1]
  import Gallformers.DataCase, only: [test_actor: 0]
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Facts
  alias Gallformers.Sources
  alias Gallformers.Taxa

  defp seedii do
    {:ok, taxon} = Taxa.resolve_name("Andricus seedii", rank: :species)
    taxon
  end

  describe "the page" do
    setup %{conn: conn} do
      taxon = seedii()
      {:ok, view, html} = live(conn, ~p"/species/#{taxon.id}")
      %{taxon: taxon, view: view, html: html}
    end

    test "is titled with the accepted name and its rank", %{view: view} do
      assert has_element?(view, "h1", "Andricus seedii")
      assert has_element?(view, "header", "Species")
      assert has_element?(view, "header", "Gallformer")
      assert page_title(view) =~ "Andricus seedii"
    end

    test "its lineage links to the rank pages", %{view: view} do
      assert has_element?(view, "header a[href='/family/Cynipidae']")
      assert has_element?(view, "header a[href='/tribe/Cynipini']")
      assert has_element?(view, "header a[href='/genus/Andricus']")
    end

    test "lists every Gall it induces, both generations, as photo cards", %{view: view} do
      assert has_element?(view, "#species-galls-section .gf-photo-grid")
      assert has_element?(view, "#species-galls-section a[href='/gall/300']")
      assert has_element?(view, "#species-galls-section a[href='/gall/301']")
    end

    test "shows where it stands and its synonyms", %{view: view} do
      assert has_element?(view, "#species-position [data-part=placement]", "Andricus")
      assert has_element?(view, "#species-synonyms", "Callirhytis seedii")
    end

    test "maps its Galls' ranges together", %{view: view, html: html} do
      assert has_element?(view, "#species-range-map")
      assert html =~ "Introduced range"
    end

    test "lists the Sources citing its Galls, with the Galls each covers", %{view: view} do
      assert has_element?(view, "#species-sources a[href='/source/59']")
    end

    test "has See also and no Edit for a reader", %{view: view} do
      assert has_element?(view, "a", "iNaturalist")
      refute has_element?(view, "a[aria-pressed]", "Edit")
    end

    test "a reader asking for ?edit gets the public page", %{conn: conn, taxon: taxon} do
      {:ok, view, _html} = live(conn, ~p"/species/#{taxon.id}?edit")
      refute has_element?(view, "#editing")
    end
  end

  describe "what isn't a species page" do
    test "a plant goes to its Host page", %{conn: conn} do
      plant = plant_fixture(%{})
      assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/species/#{plant.id}")
      assert to == "/host/#{plant.id}"
    end

    test "a genus goes to its genus page", %{conn: conn} do
      genus = seedii().parent_id

      assert {:error, {:live_redirect, %{to: "/genus/Andricus"}}} =
               live(conn, ~p"/species/#{genus}")
    end

    test "an unknown or malformed ID is a 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, "/species/999999999") end
      assert_error_sent 404, fn -> get(build_conn(), "/species/nope") end
    end

    test "a taxon merged into another redirects (301) to it", %{conn: conn} do
      n = System.unique_integer([:positive])
      survivor = taxon_fixture(name: "Mergea#{n} alba", kingdom: "Animalia")
      absorbed = taxon_fixture(name: "Mergea#{n} nigra", kingdom: "Animalia")
      {:ok, _} = Taxa.merge(test_actor(), absorbed, survivor)

      assert redirected_to(get(conn, "/species/#{absorbed.id}"), 301) == "/species/#{survivor.id}"
    end
  end

  describe "split and lump history" do
    setup do
      n = System.unique_integer([:positive])
      genus = taxon_fixture(rank: :genus, name: "Historia#{n}", kingdom: "Animalia")
      species = taxon_fixture(name: "Historia#{n} alba", parent: genus, kingdom: "Animalia")
      %{n: n, genus: genus, species: species}
    end

    test "names the taxa merged into it", %{conn: conn} = ctx do
      absorbed = taxon_fixture(name: "Historia#{ctx.n} nigra", parent: ctx.genus)
      {:ok, _} = Taxa.merge(test_actor(), absorbed, ctx.species)

      {:ok, view, _html} = live(conn, ~p"/species/#{ctx.species.id}")
      assert has_element?(view, "#species-history [data-part=merged]", "Historia#{ctx.n} nigra")
    end

    test "shows a split it came from, with its Source", %{conn: conn} = ctx do
      other = taxon_fixture(name: "Historia#{ctx.n} beta", parent: ctx.genus)
      parent = taxon_fixture(name: "Historia#{ctx.n} lata", parent: ctx.genus)
      paper = source_fixture("Revision", "1990")
      key = %{taxon_id: parent.id, into_taxon_ids: [ctx.species.id, other.id]}
      {:ok, %{attribution: a}} = Taxa.assert_split(test_actor(), key, confirm(paper))
      {:ok, _} = Facts.accept(test_actor(), a.id)

      {:ok, view, _html} = live(conn, ~p"/species/#{ctx.species.id}")
      assert has_element?(view, "#species-history [data-part=split]", "Historia#{ctx.n} lata")
      assert has_element?(view, "#species-history a[href='/source/#{paper.id}']")
    end

    test "a species with no history says nothing of it", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/species/#{ctx.species.id}")
      refute has_element?(view, "#species-history")
    end
  end

  describe "Edit mode" do
    setup %{conn: conn} do
      {conn, user} = log_in_admin(conn, "Sol Source")
      n = System.unique_integer([:positive])
      family = taxon_fixture(rank: :family, name: "Editidae#{n}", kingdom: "Animalia")
      other = taxon_fixture(rank: :genus, name: "Otheredita#{n}", parent: family)
      genus = taxon_fixture(rank: :genus, name: "Edita#{n}", parent: family)
      species = taxon_fixture(name: "Edita#{n} alba", parent: genus)

      legacy = Sources.get_legacy_data_source()
      attribution = %{source_id: legacy.id, stance: :confirm, stated: nil}

      for taxon <- [family, other, genus, species] do
        taxon = Taxa.get_taxon!(taxon.id)
        key = %{taxon_id: taxon.id, parent_id: taxon.parent_id}
        {:ok, _} = Taxa.assert_placement(test_actor(), key, attribution)
        name = %{taxon_id: taxon.id, name: Taxa.accepted_name(taxon), rank: taxon.rank}
        {:ok, _} = Taxa.assert_name(test_actor(), name, attribution)
      end

      {:ok, view, _html} = live(conn, ~p"/species/#{species.id}?edit")

      %{
        conn: conn,
        user: user,
        n: n,
        view: view,
        other: other,
        species: species,
        weld: source_fixture("Weld", "1959")
      }
    end

    defp pick_source(view, source) do
      view |> with_target("#basis-picker") |> render_hook("search_source", %{"value" => "Weld"})
      view |> element("#basis-picker-source [phx-value-id='#{source.id}']") |> render_click()
    end

    defp submit_basis(view) do
      view |> form("#basis-picker-form") |> render_submit()
      render(view)
    end

    test "says what is edited elsewhere: the Galls, on their own pages", %{view: view} do
      assert has_element?(view, "#editing", "Editing")
      assert has_element?(view, "#editing [data-scope=follows]", "Gall")
      assert has_element?(view, "#species-editor")
    end

    test "a new synonym asks which Source it follows, and is made as its statement", ctx do
      view = ctx.view

      view |> element("#species-editor-synonyms button", "Add a synonym") |> render_click()
      view |> form("#species-synonym-form", synonym: %{name: "Cynips edita"}) |> render_submit()
      assert has_element?(view, "#basis-picker", "Based on which Source?")
      assert has_element?(view, "#basis-picker-change", "Cynips edita")

      pick_source(view, ctx.weld)
      html = submit_basis(view)

      assert html =~ "Synonym Cynips edita added"
      assert ["Cynips edita"] = Enum.map(Taxa.list_synonyms(ctx.species), & &1.name)
      assert has_element?(view, "#species-editor-synonyms", "Cynips edita")
    end

    test "a rename gives the name, rank and authorship", ctx do
      view = ctx.view
      new_name = "Edita#{ctx.n} albida"

      view |> element("#species-editor-name button", "Rename") |> render_click()

      view
      |> form("#species-name-form", rename: %{name: new_name, authorship: "(Weld, 1959)"})
      |> render_submit()

      pick_source(view, ctx.weld)
      html = submit_basis(view)

      assert html =~ "Renamed to #{new_name}"
      assert Taxa.accepted_name(ctx.species.id) == new_name
      assert has_element?(view, "h1", new_name)
    end

    test "a move picks the new genus and follows a Source", ctx do
      view = ctx.view
      other_name = Taxa.accepted_name(ctx.other)

      view |> element("#species-editor-placement button", "Move") |> render_click()
      render_keyup(view, "search_parent", %{"value" => other_name})
      render_click(view, "select_parent", %{"id" => "#{ctx.other.id}"})
      view |> element("#species-move-button") |> render_click()
      assert has_element?(view, "#basis-picker-change", other_name)

      pick_source(view, ctx.weld)
      html = submit_basis(view)

      assert html =~ "Moved under #{other_name}"
      assert Taxa.get_taxon!(ctx.species.id).parent_id == ctx.other.id
      assert has_element?(view, "header a[href='/genus/#{other_name}']")
    end

    test "a common name is added and taken out through a Source", ctx do
      view = ctx.view

      view
      |> element("#species-editor-common-names button", "Add a common name")
      |> render_click()

      view
      |> form("#species-common-name-form", common_name: %{name: "white edita"})
      |> render_submit()

      pick_source(view, ctx.weld)
      submit_basis(view)
      assert [common] = Taxa.list_common_names(ctx.species)
      assert has_element?(view, "header", "white edita")

      view
      |> element("#species-editor-common-names button[phx-value-id='#{common.id}']")
      |> render_click()

      assert has_element?(view, "#basis-picker-change", "white edita")
      submit_basis(view)
      assert Taxa.list_common_names(ctx.species) == []
    end

    test "cancelling changes nothing", ctx do
      view = ctx.view
      view |> element("#species-editor-synonyms button", "Add a synonym") |> render_click()
      view |> form("#species-synonym-form", synonym: %{name: "Cynips edita"}) |> render_submit()

      render_click(view, "cancel_basis", %{})

      refute has_element?(view, "#basis-picker")
      assert Taxa.list_synonyms(ctx.species) == []
    end
  end
end
