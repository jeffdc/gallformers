defmodule GallformersWeb.Admin.ReviewLive.InatTest do
  @moduledoc """
  A review question answered with a taxon from iNaturalist (matter `cb28`
  Task 6): the question's own search ("Another plant…", "Another taxon…")
  lists iNaturalist's taxa beside ours (and, for a Host, WCVP's), a Host's
  Gallformers group lists genera and sections too; "Look at it" opens the
  import panel in the rail's place; bringing the taxon in answers the
  question with it, and the review moves on. iNaturalist's responses are
  recorded ones (`Gallformers.INaturalistFixtures`).

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1]
  import Gallformers.ImportFixtures
  import Gallformers.INaturalistFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Import
  alias Gallformers.Taxa

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    stub_inat_taxa()
    %{conn: conn}
  end

  setup :audit_test_metadata

  # A package whose Host is "Rubus villosus var. frondosus" (InfluentialPoints'
  # Host of package 119) and whose names include "Torymus", which we don't hold.
  defp delivered! do
    load_vocab!()

    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "Curled-leaf pseudogalls")
      |> put_in(["source", "authors"], ["InfluentialPoints"])
      |> put_in(["source", "authored"], %{"date" => "2026", "as_written" => "2026"})
      |> put_in(["taxa", Access.at(1)], %{
        "ref" => "t2",
        "name_as_written" => "Rubus villosus var. frondosus",
        "rank" => "variety"
      })

    package(gall: gall) |> with_review() |> deliver!()
  end

  defp rubus_tree do
    rosaceae = plant_fixture(rank: :family, name: "Rosaceae")
    rubus = plant_fixture(rank: :genus, name: "Rubus", parent: rosaceae)
    %{rosaceae: rosaceae, rubus: rubus}
  end

  defp item(package, kind, written) do
    package
    |> Import.list_queue_items(kind: kind)
    |> Enum.find(&(&1.subject["name_as_written"] == written))
  end

  # Opens the question's card in the Everything list.
  defp open(conn, package, item) do
    {:ok, view, _html} = live(conn, "/admin/review/packages/#{package.id}?view=all")
    render_hook(view, "open_row", %{"id" => item.id})
    view
  end

  # Opens the card's answer labelled `label` ("Another plant…").
  defp choose(view, item, label) do
    value =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#q-#{item.id} [id^='q-#{item.id}-c']")
      |> Enum.find(&(LazyHTML.text(LazyHTML.query(&1, "[data-role=label]")) =~ label))
      |> LazyHTML.query("button")
      |> LazyHTML.attribute("phx-value-choice")
      |> hd()

    view |> element("#q-#{item.id} button[phx-value-choice='#{value}']") |> render_click()
  end

  defp search(view, item, what, query) do
    view |> with_target("#q-#{item.id}") |> render_hook("search_#{what}", %{"value" => query})
    render_async(view)
  end

  defp result_texts(view, item) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#q-#{item.id} [data-typeahead-results]")
    |> LazyHTML.text()
    |> String.split()
    |> Enum.join(" ")
  end

  describe "a Host question" do
    test "“Another plant…” searches Gallformers, WCVP and iNaturalist; sections and genera are ours too",
         %{conn: conn} do
      %{rubus: rubus} = rubus_tree()
      section = plant_fixture(rank: :section, name: "Rubus", parent: rubus)
      package = delivered!()
      host = item(package, :unresolved_host, "Rubus villosus var. frondosus")
      view = open(conn, package, host)

      assert render(view) =~ "Search Gallformers, WCVP and iNaturalist by name."
      choose(view, host, "Another plant…")
      assert has_element?(view, "#q-#{host.id} label", "Find a plant by name")

      search(view, host, "plant", "Rubus pensilvanicus")
      texts = result_texts(view, host)
      assert texts =~ "On iNaturalist"

      # Its name, what it is and "Look at it", each its own span.
      assert texts =~
               "Argutisection · Field Highbush Blackberries · matched “Rubus pensilvanicus”Look at it"

      search(view, host, "plant", "Rubus")
      texts = result_texts(view, host)
      assert texts =~ "In Gallformers"

      assert has_element?(
               view,
               "#q-#{host.id} [data-typeahead-results] button[phx-value-id='taxon:#{rubus.id}']"
             )

      assert has_element?(
               view,
               "#q-#{host.id} [data-typeahead-results] button[phx-value-id='taxon:#{section.id}']"
             )
    end

    test "Look at it opens the panel in the rail's place; Add answers the question with it",
         %{conn: conn} do
      %{rubus: rubus} = rubus_tree()
      package = delivered!()
      host = item(package, :unresolved_host, "Rubus villosus var. frondosus")
      view = open(conn, package, host)

      assert has_element?(view, "[data-role=answered]")
      choose(view, host, "Another plant…")
      search(view, host, "plant", "Rubus pensilvanicus")

      view
      |> element("#q-#{host.id} [data-typeahead-results] button[phx-value-id='inat:1449402']")
      |> render_click()

      html = render_async(view)
      assert html =~ "From iNaturalist"
      assert html =~ "Then the question is answered with"
      # In the rail's place.
      refute has_element?(view, "[data-role=answered]")

      view |> element("[data-role=inat-add]") |> render_click()

      {:ok, arguti} = Taxa.resolve_name("Arguti", rank: :section, kingdom: "Plantae")
      assert Taxa.inat_id(arguti) == 1_449_402
      assert Taxa.get_taxon!(Taxa.get_taxon!(arguti.id).parent_id).parent_id == rubus.id

      decided = Import.get_queue_item!(host.id)
      assert decided.status == :decided
      assert decided.decision["taxon_id"] == arguti.id
      assert decided.decision["add_synonym"] == true

      # The Source's spelling, and the synonym that matched on iNaturalist.
      synonyms = arguti.id |> Taxa.list_synonyms() |> Enum.map(& &1.name) |> Enum.sort()
      assert synonyms == ["Rubus pensilvanicus", "Rubus villosus var. frondosus"]

      refute render(view) =~ "From iNaturalist"
      assert has_element?(view, "[data-role=answered]")
    end

    test "Close and Cancel bring the rail back, nothing added", %{conn: conn} do
      rubus_tree()
      package = delivered!()
      host = item(package, :unresolved_host, "Rubus villosus var. frondosus")
      view = open(conn, package, host)

      choose(view, host, "Another plant…")
      search(view, host, "plant", "Rubus pensilvanicus")

      view
      |> element("#q-#{host.id} [data-typeahead-results] button[phx-value-id='inat:1449402']")
      |> render_click()

      render_async(view)

      view
      |> element("aside[aria-label='From iNaturalist'] button", "← Other results")
      |> render_click()

      refute render(view) =~ "From iNaturalist"
      assert has_element?(view, "[data-role=answered]")
      assert Import.get_queue_item!(host.id).status == :open
      assert Taxa.resolve_name("Arguti") == :none
    end
  end

  describe "a name we don't have" do
    test "“Another taxon…” searches Gallformers and iNaturalist; Add answers it with the taxon",
         %{conn: conn} do
      package = delivered!()
      torymus = item(package, :unresolved_name, "Torymus")
      view = open(conn, package, torymus)

      assert render(view) =~ "Search Gallformers and iNaturalist by name."
      choose(view, torymus, "Another taxon…")
      search(view, torymus, "taxon", "Syrphidae")

      assert result_texts(view, torymus) =~
               "On iNaturalist Syrphidaefamily · Hover FliesLook at it"

      view
      |> element("#q-#{torymus.id} [data-typeahead-results] button[phx-value-id='inat:49995']")
      |> render_click()

      html = render_async(view)
      assert html =~ "accepted by you."

      view |> element("[data-role=inat-add]") |> render_click()

      {:ok, syrphidae} = Taxa.resolve_name("Syrphidae", rank: :family)
      assert Taxa.inat_id(syrphidae) == 49_995
      assert Import.get_queue_item!(torymus.id).decision == %{"taxon_id" => syrphidae.id}
    end
  end
end
