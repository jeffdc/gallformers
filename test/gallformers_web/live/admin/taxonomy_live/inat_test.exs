defmodule GallformersWeb.Admin.TaxonomyLive.InatTest do
  @moduledoc """
  iNaturalist in the taxonomy admin (matter `cb28` Task 7): "From
  iNaturalist" on the New Taxon page, beside "From POWO-WCVP", opens the
  import panel's search, and the taxon brought in opens on its own page; a
  taxon's page links it to its iNaturalist taxon, beside its WCVP link (the
  ID only). iNaturalist's responses are recorded ones.

  Not async: the day's iNaturalist Source has a unique title.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.INaturalistFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Import
  alias Gallformers.Taxa

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Nel New")
    stub_inat_taxa()
    %{conn: conn}
  end

  describe "the New Taxon page" do
    test "From iNaturalist opens the search; the taxon brought in opens on its page",
         %{conn: conn} do
      rosaceae = plant_fixture(rank: :family, name: "Rosaceae")
      rubus = plant_fixture(rank: :genus, name: "Rubus", parent: rosaceae)

      {:ok, view, html} = live(conn, ~p"/admin/taxonomy/new")
      assert html =~ "Add a taxon from iNaturalist"
      refute html =~ "Search iNaturalist by name"

      view |> element("button", "From iNaturalist…") |> render_click()
      assert has_element?(view, "aside[aria-label='From iNaturalist']")
      assert render(view) =~ "A name, or an iNaturalist link or number."

      view
      |> element("aside[aria-label='From iNaturalist'] form")
      |> render_change(%{"q" => "Rubus frondosus"})

      render_async(view)
      view |> element("li[data-inat='168056'] button", "Look at it") |> render_click()
      html = render_async(view)
      assert html =~ "Where it goes"
      refute html =~ "Then the question is answered with"

      view |> element("[data-role=inat-add]") |> render_click()

      {:ok, frondosus} = Taxa.resolve_name("Rubus frondosus", rank: :species, kingdom: "Plantae")
      assert_redirect(view, "/admin/taxonomy/#{frondosus.id}")
      assert Taxa.inat_id(frondosus) == 168_056
      arguti = Taxa.get_taxon!(Taxa.get_taxon!(frondosus.id).parent_id)
      assert Taxa.accepted_name(arguti) == "Arguti"
      assert Taxa.get_taxon!(arguti.parent_id).parent_id == rubus.id
    end

    test "Close brings the page back as it was", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")
      view |> element("button", "From iNaturalist…") |> render_click()

      view
      |> element("aside[aria-label='From iNaturalist'] button[aria-label=Close]")
      |> render_click()

      refute has_element?(view, "aside[aria-label='From iNaturalist']")
    end
  end

  describe "a taxon's page" do
    test "links it to its iNaturalist taxon by a link or number, logged for replay",
         %{conn: conn} do
      family = plant_fixture(rank: :family, name: "Rosaceae")
      rubus = plant_fixture(rank: :genus, name: "Rubus", parent: family)

      {:ok, view, html} = live(conn, ~p"/admin/taxonomy/#{rubus.id}")
      assert html =~ "iNaturalist link"
      assert has_element?(view, "#inat-link", "Not linked")

      view
      |> element("#inat-link-form")
      |> render_submit(%{"inat" => %{"taxon" => "https://www.inaturalist.org/taxa/47544-Rubus"}})

      assert Taxa.inat_id(rubus) == 47_544
      assert has_element?(view, "#inat-link a[href='https://www.inaturalist.org/taxa/47544']")

      assert [%{key: %{"op" => "set_inat"}}] =
               for(e <- Import.list_replay_entries(), e.key["op"] == "set_inat", do: e)
    end

    test "an animal too; a taxon iNaturalist links to another of ours is refused",
         %{conn: conn} do
      one =
        Gallformers.TaxaFixtures.taxon_fixture(
          rank: :family,
          name: "Syrphidae",
          kingdom: "Animalia"
        )

      other =
        Gallformers.TaxaFixtures.taxon_fixture(
          rank: :family,
          name: "Otheridae",
          kingdom: "Animalia"
        )

      {:ok, _} =
        Import.record_taxonomy_edit(Gallformers.DataCase.test_actor(), {:set_inat, one, 49_995})

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{other.id}")

      html =
        view
        |> element("#inat-link-form")
        |> render_submit(%{"inat" => %{"taxon" => "49995"}})

      assert html =~ "iNaturalist&#39;s taxon 49995 is linked to Syrphidae already."
      assert Taxa.inat_id(other) == nil

      html =
        view
        |> element("#inat-link-form")
        |> render_submit(%{"inat" => %{"taxon" => "Syrphidae"}})

      assert html =~ "Paste an iNaturalist link to the taxon, or its number."
    end
  end
end
