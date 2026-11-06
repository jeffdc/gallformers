defmodule GallformersWeb.GallLiveEditDialogsTest do
  @moduledoc """
  Edit mode's dialogs on the Gall page (matter ec2c; moved from the admin
  Gall page, which is gone): the photos (the image manager), the
  Gallformers ID note (each save a new dated version), the lead Source (an
  editorial item in the tray) and range exclusions (marked on the map,
  then put in the tray as Fact items on the Gall's exclusions). The old
  admin URLs send curators here.

  Not async: the Gallformers Source is unique.
  """
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [test_actor: 0]
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Curation
  alias Gallformers.Sources

  setup %{conn: conn} do
    {conn, user} = log_in_admin(conn, "Gail Galls")

    %{
      conn: conn,
      actor: Actor.user(user.id, "Gail Galls"),
      gallformers: gallformers_source(),
      source: source_fixture("Weld", "1959")
    }
  end

  defp relate!(gall, type, taxon, source) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: type, subject_taxon_id: taxon.id, object_gall_id: gall.id},
        confirm(source)
      )

    gall
  end

  # A described Gall on a Host that grows in California and Alberta.
  defp gall_with_range(ctx) do
    name = "Zyzzdialog#{System.unique_integer([:positive])}"
    genus = taxon_fixture(rank: :genus, name: name, kingdom: "Animalia")
    species = taxon_fixture(name: "#{name} lecta", parent: genus, kingdom: "Animalia")
    plant = plant_fixture()
    :ok = host_range_fixture(plant, [{"US-CA", "exact"}, {"CA-AB", "exact"}])

    gall_fixture(name: "#{name} lecta")
    |> relate!("inducer_of", species, ctx.source)
    |> relate!("host_of", plant, ctx.source)
  end

  defp edit(ctx, gall), do: live(ctx.conn, ~p"/gall/#{gall.id}?edit")

  defp items(actor) do
    case Curation.open_set(actor) do
      nil -> []
      set -> Enum.map(set.items, &{&1.kind, &1.spec})
    end
  end

  describe "photos" do
    test "the photo viewer's Edit photos opens Edit mode with the image manager open", ctx do
      gall = gall_with_range(ctx)
      {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{gall.id}")
      refute has_element?(view, "#photos-panel")

      {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{gall.id}?edit&photos")

      assert has_element?(view, "#photos-panel #photos-manager")
      refute has_element?(view, "#photos-panel [role=dialog] #photos-manager")
    end

    test "Photos… opens it, Done closes it, in the URL", ctx do
      gall = gall_with_range(ctx)
      {:ok, view, _html} = edit(ctx, gall)

      view |> element("#editorial button[phx-click=open_photos]") |> render_click()
      assert_patch(view, "/gall/#{gall.id}?edit&photos")
      assert has_element?(view, "#photos-panel #photos-manager")

      view |> element("#photos-panel button[phx-click=close_photos]") |> render_click()
      assert_patch(view, "/gall/#{gall.id}?edit")
      refute has_element?(view, "#photos-panel")
    end

    test "?photos without Edit mode is the public page", ctx do
      gall = gall_with_range(ctx)
      {:ok, view, _html} = live(Phoenix.ConnTest.build_conn(), ~p"/gall/#{gall.id}?edit&photos")

      refute has_element?(view, "#photos-panel")
    end
  end

  describe "the ID note" do
    test "each save is a new dated version; earlier versions are listed", ctx do
      gall = gall_with_range(ctx)
      {:ok, _} = Sources.store_note(test_actor(), ctx.gallformers, gall.id, "Old note.", nil)
      {:ok, view, _html} = edit(ctx, gall)

      view |> element("#editorial button[phx-click=open_note]") |> render_click()
      assert has_element?(view, "#note-form textarea", "Old note.")

      view |> form("#note-form", note: %{text: "New note."}) |> render_submit()

      assert [newest, oldest] = Sources.list_gall_notes(gall.id)
      assert newest.version_date == Date.utc_today()
      assert oldest.version_date == nil
      assert has_element?(view, "#note-version-#{newest.id}", "New note.")
      assert has_element?(view, "#note-version-#{oldest.id}", "Old note.")
    end

    test "an unchanged note stores nothing; a blank one is refused", ctx do
      gall = gall_with_range(ctx)
      {:ok, _} = Sources.store_note(test_actor(), ctx.gallformers, gall.id, "Same.", nil)
      {:ok, view, _html} = edit(ctx, gall)
      view |> element("#editorial button[phx-click=open_note]") |> render_click()

      assert view |> form("#note-form", note: %{text: "Same."}) |> render_submit() =~ "unchanged"
      assert view |> form("#note-form", note: %{text: "  "}) |> render_submit() =~ "needs text"
      assert [_one] = Sources.list_gall_notes(gall.id)
    end

    test "a Gall's first note is the Gallformers Source's", ctx do
      gall = gall_with_range(ctx)
      {:ok, view, _html} = edit(ctx, gall)
      view |> element("#editorial button[phx-click=open_note]") |> render_click()

      view |> form("#note-form", note: %{text: "First."}) |> render_submit()

      assert [%{source_id: source_id}] = Sources.list_gall_notes(gall.id)
      assert source_id == ctx.gallformers.id
    end
  end

  test "the lead Source: one of the Gall's own Sources, into the tray", ctx do
    gall = gall_with_range(ctx)
    unrelated = source_fixture("Unrelated", "1990")
    {:ok, view, _html} = edit(ctx, gall)

    assert has_element?(view, "#editorial-lead-source option[value='#{ctx.source.id}']")
    refute has_element?(view, "#editorial-lead-source option[value='#{unrelated.id}']")

    view
    |> form("#editorial-lead", %{"default_source_id" => to_string(ctx.source.id)})
    |> render_change()

    assert [{:editorial, %{field: :default_source_id, value: id}}] = items(ctx.actor)
    assert id == ctx.source.id
  end

  describe "range exclusions" do
    test "a place marked on the map goes in the tray as an exclusion", ctx do
      gall = gall_with_range(ctx)
      {:ok, view, _html} = edit(ctx, gall)

      view |> element("#editorial button[phx-click=open_range]") |> render_click()
      assert has_element?(view, "#range-dialog #exclusions-range-map")

      render_hook(view, "toggle_region", %{"code" => "US-CA"})
      assert has_element?(view, "#marked-places", "California")

      view |> element("#range-dialog button[phx-click=range_to_tray]") |> render_click()

      ca = place_id("US-CA")
      assert [{:fact, %{action: :add, key: {:range, :exclude, ^ca}}}] = items(ctx.actor)
      refute has_element?(view, "#range-dialog")
    end

    test "restoring an exclusion goes in the tray as its withdrawal", ctx do
      gall = gall_with_range(ctx)
      ca = place_id("CA")

      {:ok, _} =
        Catalog.assert_range(
          test_actor(),
          %{gall_id: gall.id, adjustment: :exclude, place_id: ca},
          confirm(ctx.source)
        )

      {:ok, view, _html} = edit(ctx, gall)
      view |> element("#editorial button[phx-click=open_range]") |> render_click()

      render_hook(view, "toggle_region", %{"code" => "CA-AB"})
      assert has_element?(view, "#marked-places", "Alberta")

      view |> element("#range-dialog button[phx-click=range_to_tray]") |> render_click()

      assert [{:fact, %{action: :withdraw, key: {:range, :exclude, ^ca}}}] = items(ctx.actor)
    end

    test "a place outside the potential range can't be marked; nothing marked, nothing to add",
         ctx do
      gall = gall_with_range(ctx)
      {:ok, view, _html} = edit(ctx, gall)
      view |> element("#editorial button[phx-click=open_range]") |> render_click()

      render_hook(view, "toggle_region", %{"code" => "MX-JAL"})

      refute has_element?(view, "#marked-places")
      assert has_element?(view, "#range-dialog button[phx-click=range_to_tray][disabled]")
    end

    test "a country with subdivisions opens the drill-down", ctx do
      gall = gall_with_range(ctx)
      {:ok, view, _html} = edit(ctx, gall)
      view |> element("#editorial button[phx-click=open_range]") |> render_click()

      render_hook(view, "toggle_country", %{"code" => "US"})

      assert has_element?(view, "input[phx-click='toggle_place'][phx-value-code='US-CA']")
    end
  end

  test "the old admin Gall URLs send curators to the Gall page in Edit mode", ctx do
    gall = gall_with_range(ctx)

    assert redirected_to(get(ctx.conn, "/admin/galls/#{gall.id}"), 301) == "/gall/#{gall.id}?edit"
    assert redirected_to(get(ctx.conn, "/admin/galls"), 301) == "/galls"
  end
end
