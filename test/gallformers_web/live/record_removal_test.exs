defmodule GallformersWeb.RecordRemovalTest do
  @moduledoc """
  Deleting and merging Galls and plants from the pages (matter `ec2c`,
  "Deletes"): the Gall page in Edit mode and the taxonomy admin's page of a
  taxon (`GallformersWeb.RecordRemoval`, on `Gallformers.Import`'s
  `deletion_impact/1`, `record_deletion/2`, `merge_preview/2` and
  `record_merge/2`). A delete shows its impact, or why it is blocked and
  what to do instead, and asks for the name typed; a merge picks the
  record to keep, previews the merge and asks for the name typed.

  Not async: the fixtures make the Gallformers Source (one per database).
  """
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import GallformersWeb.AdminLiveHelpers
  import GallformersWeb.CurationWebFixtures
  import Gallformers.CatalogFixtures

  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Import
  alias Gallformers.Taxa

  setup %{conn: conn} do
    {conn, user} = log_in_admin(conn, "Ada Curator")
    %{conn: conn, actor: Actor.user(user.id, "Ada Curator")}
  end

  defp uniq, do: System.unique_integer([:positive])

  defp deletions, do: for(e <- Import.list_replay_entries(), e.kind == :deletion, do: e)

  describe "on the Gall page" do
    test "Edit mode has Delete and Merge; the public page has neither", ctx do
      gall = gall_fixture()

      {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{gall.id}")
      refute has_element?(view, "#record-removal")

      {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{gall.id}?edit")
      assert has_element?(view, "#record-removal button", "Delete…")
      assert has_element?(view, "#record-removal button", "Merge into another Gall…")
    end

    test "a Gall a real Source's Facts rest on can't be deleted: why, and what to do", ctx do
      %{gall: gall} = curated_gall!(ctx.actor)
      {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{gall.id}?edit")

      view |> element("#record-removal button", "Delete…") |> render_click()

      assert has_element?(view, "#record-removal-blocked", "Weld")
      assert has_element?(view, "#record-removal-blocked", "merge it")
      refute has_element?(view, "#dangerous-delete-modal")
    end

    test "a Gall nothing from a real Source rests on is deleted once its name is typed", ctx do
      name = "Andricus deletablis #{uniq()}"
      gall = gall_fixture(name: name)
      {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{gall.id}?edit")

      view |> element("#record-removal button", "Delete…") |> render_click()
      assert has_element?(view, "#dangerous-delete-modal", name)

      view
      |> form("#dangerous-delete-modal-form", %{"confirmation" => "wrong"})
      |> render_submit()

      assert %Gall{} = Catalog.get_gall(gall.id)

      view |> form("#dangerous-delete-modal-form", %{"confirmation" => name}) |> render_submit()

      assert_redirect(view, "/galls")
      assert Catalog.get_gall(gall.id) == nil
      assert [_] = deletions()
    end

    test "merging: pick the Gall to keep, see what moves, type the name", ctx do
      %{gall: absorbed} = curated_gall!(ctx.actor)
      survivor = gall_fixture(name: "Andricus keptus #{uniq()} gall")
      {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{absorbed.id}?edit")

      view |> element("#record-removal button", "Merge into another Gall…") |> render_click()

      view
      |> with_target("#record-removal")
      |> render_hook("search_survivor", %{"value" => "keptus"})

      view |> element("#merge-survivor [phx-value-id='#{survivor.id}']") |> render_click()

      assert has_element?(view, "#merge-preview", "host: Quercus webcurata")
      assert has_element?(view, "#merge-preview", survivor.name)

      absorbed_name = Gall.display_name(absorbed)

      view
      |> form("#merge-confirm", %{"confirmation" => absorbed_name})
      |> render_submit()

      assert_redirect(view, "/gall/#{survivor.id}?edit")
      assert Catalog.get_gall(absorbed.id) == nil
      assert Catalog.gall_redirect(absorbed.id) == survivor.id
    end
  end

  describe "on the taxonomy page" do
    test "a plant nothing refers to is deleted once its name is typed", ctx do
      name = "Lonely#{uniq()} alba"
      plant = plant_fixture(name: name)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy/#{plant.id}")

      view |> element("#record-removal button", "Delete…") |> render_click()
      assert has_element?(view, "#dangerous-delete-modal", name)

      view |> form("#dangerous-delete-modal-form", %{"confirmation" => name}) |> render_submit()

      assert_redirect(view, "/admin/taxonomy")
      assert Taxa.get_taxon(plant.id) == nil
      assert [_] = deletions()
    end

    test "deleting a genus deletes what is under it, and says so first", ctx do
      family = plant_fixture(rank: :family, name: "Removaceae#{uniq()}")
      genus = plant_fixture(rank: :genus, name: "Removus#{uniq()}", parent: family)
      kid = plant_fixture(name: "#{Taxa.accepted_name(genus)} kid", parent: genus)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy/#{genus.id}")

      view |> element("#record-removal button", "Delete…") |> render_click()

      assert has_element?(view, "#dangerous-delete-modal", Taxa.accepted_name(kid))
    end

    test "a plant merges into the plant kept", ctx do
      absorbed = plant_fixture(name: "Quercus mergeda#{uniq()}")
      survivor = plant_fixture(name: "Quercus keptia#{uniq()}")
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy/#{absorbed.id}")

      view |> element("#record-removal button", "Merge into another plant…") |> render_click()

      view
      |> with_target("#record-removal")
      |> render_hook("search_survivor", %{"value" => "keptia"})

      view |> element("#merge-survivor [phx-value-id='#{survivor.id}']") |> render_click()
      assert has_element?(view, "#merge-preview", Taxa.accepted_name(survivor))

      view
      |> form("#merge-confirm", %{"confirmation" => Taxa.accepted_name(absorbed)})
      |> render_submit()

      assert_redirect(view, "/admin/taxonomy/#{survivor.id}")
      assert Taxa.get_taxon(absorbed.id) == nil
      assert Taxa.taxon_redirect(absorbed.id) == survivor.id
    end

    test "a plant a real Source names as a Host can't be deleted: why, and what to do", ctx do
      %{oak: oak} = curated_gall!(ctx.actor)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy/#{oak.id}")

      view |> element("#record-removal button", "Delete…") |> render_click()

      assert has_element?(view, "#record-removal-blocked [data-part=blocker]", "Weld")
      refute has_element?(view, "#dangerous-delete-modal")
    end

    test "a taxon that isn't a plant has Delete but no Merge", ctx do
      wasp = Gallformers.TaxaFixtures.taxon_fixture(name: "Andricus nomergus#{uniq()}")
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy/#{wasp.id}")

      assert has_element?(view, "#record-removal button", "Delete…")
      refute has_element?(view, "#record-removal button", "Merge")
    end
  end
end
