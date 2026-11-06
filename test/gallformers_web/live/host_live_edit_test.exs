defmodule GallformersWeb.HostLiveEditTest do
  @moduledoc """
  Edit mode on a plant's page (matter `ec2c`, "Change-set interface": plant
  pages are editorial): a curator turns on Edit (`?edit`); the plant's
  name, its synonyms and its range are edited into the tray
  (`Gallformers.Curation`), each with what it is "based on" when it
  departs from WCVP; delete and merge sit in the rail. Visitors see the
  public page.

  Not async: the tray's Gallformers Source is one per database.
  """
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import GallformersWeb.AdminLiveHelpers
  import Gallformers.CatalogFixtures

  alias Gallformers.Audit.Actor
  alias Gallformers.Curation
  alias Gallformers.Taxa

  setup %{conn: conn} do
    {conn, user} = log_in_admin(conn, "Ada Curator")
    actor = Actor.user(user.id, "Ada Curator")
    plant = plant_fixture(name: "Quercus editplanta#{System.unique_integer([:positive])}")
    {:ok, _} = Taxa.add_synonym(actor, plant, "Quercus oldplanta")
    %{conn: conn, actor: actor, plant: plant, name: Taxa.accepted_name(plant)}
  end

  defp edit(ctx), do: live(ctx.conn, ~p"/host/#{ctx.plant.id}?edit")

  defp items(actor) do
    case Curation.open_set(actor) do
      nil -> []
      set -> Enum.map(set.items, & &1.spec)
    end
  end

  describe "the switch" do
    test "a visitor: no Edit, and ?edit shows the public page", ctx do
      {:ok, view, _html} = live(build_conn(), ~p"/host/#{ctx.plant.id}?edit")

      refute has_element?(view, "a[aria-pressed]", "Edit")
      refute has_element?(view, "#host-editor")
    end

    test "a curator: Edit turns Edit mode on, Done off", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/host/#{ctx.plant.id}")

      assert has_element?(
               view,
               "a[href='/host/#{ctx.plant.id}?edit'][aria-pressed=false]",
               "Edit"
             )

      refute has_element?(view, "#host-editor")

      {:ok, view, _html} = edit(ctx)
      assert has_element?(view, "a[href='/host/#{ctx.plant.id}'][aria-pressed=true]", "Done")
      assert has_element?(view, "#host-editor")

      assert has_element?(
               view,
               "[data-scope=elsewhere] a[href='/admin/taxonomy/#{ctx.plant.id}']"
             )

      assert has_element?(view, "#record-removal")
    end
  end

  describe "the name" do
    test "Rename… puts the new name in the tray, with what it is based on", ctx do
      {:ok, view, _html} = edit(ctx)

      view |> element("#host-editor button", "Rename…") |> render_click()

      view
      |> form("#host-name-dialog form", %{
        "name" => "Quercus renamedplanta",
        "based_on" => "per Flora of North America"
      })
      |> render_submit()

      assert [
               %{
                 kind: :editorial,
                 field: :name,
                 value: "Quercus renamedplanta",
                 based_on: "per Flora of North America"
               }
             ] = items(ctx.actor)

      assert has_element?(view, "#host-editor-name [data-part=pending]")
    end
  end

  describe "the synonyms" do
    test "each synonym can be taken out, and one added; the tray holds the list", ctx do
      {:ok, view, _html} = edit(ctx)

      assert has_element?(view, "#host-editor-synonyms", "Quercus oldplanta")

      view
      |> form("#host-editor-synonyms form", %{"name" => "Quercus newplanta", "sensu" => ""})
      |> render_submit()

      assert [%{field: :synonyms, value: value}] = items(ctx.actor)

      assert Enum.map(value, & &1.name) |> Enum.sort() == [
               "Quercus newplanta",
               "Quercus oldplanta"
             ]

      # The next edit starts from the list in the tray.
      view
      |> element("#host-editor-synonyms [data-synonym='Quercus oldplanta'] button")
      |> render_click()

      assert [%{field: :synonyms, value: [%{name: "Quercus newplanta"}]}] = items(ctx.actor)
      assert has_element?(view, "#host-editor-synonyms [data-part=pending]")
    end
  end

  describe "the range" do
    test "Range… edits it on the map; Put in tray holds the whole range", ctx do
      {:ok, view, _html} = edit(ctx)

      view |> element("#host-editor button", "Range…") |> render_click()
      assert has_element?(view, "#host-range-dialog #host-range-editor")

      render_hook(view, "toggle_region", %{"code" => "US-CA"})

      view
      |> form("#host-range-tray", %{"based_on" => "seen in California"})
      |> render_submit()

      assert [
               %{
                 field: :range,
                 value: [{place_id, "exact", "native"}],
                 based_on: "seen in California"
               }
             ] =
               items(ctx.actor)

      assert place_id == place_id("US-CA")
      refute has_element?(view, "#host-range-dialog")
    end
  end
end
