defmodule GallformersWeb.GallLiveEditTest do
  @moduledoc """
  Edit mode on the Gall page (matter ec2c): a curator turns on Edit
  (`?edit`); each Host and the Inducer become rows with their Sources and
  actions, each Trait value a chip that can be withdrawn, each Trait an
  Add; every edit goes into the curator's tray (`Gallformers.Curation`),
  and the page marks what is in it. Visitors never see any of it.

  Not async: the fixtures make the Gallformers Source (one per database).
  """
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import GallformersWeb.AdminLiveHelpers
  import GallformersWeb.CurationWebFixtures
  import Gallformers.CatalogFixtures, only: [plant_fixture: 1]

  alias Gallformers.Accounts
  alias Gallformers.Audit.Actor
  alias Gallformers.Curation

  setup %{conn: conn} do
    {conn, user} = log_in_admin(conn, "Ada Curator")
    actor = Actor.user(user.id, "Ada Curator")
    ctx = curated_gall!(actor)
    Map.merge(ctx, %{conn: conn, actor: actor})
  end

  defp edit(ctx), do: live(ctx.conn, ~p"/gall/#{ctx.gall.id}?edit")

  defp items(actor) do
    case Curation.open_set(actor) do
      nil -> []
      set -> Enum.map(set.items, &{&1.kind, &1.spec})
    end
  end

  describe "the switch" do
    test "a visitor: no Edit, and ?edit shows the public page", ctx do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, view, _html} = live(conn, ~p"/gall/#{ctx.gall.id}?edit")

      refute has_element?(view, "a[aria-pressed]", "Edit")
      refute has_element?(view, "#gall-editor")
    end

    test "a curator: Edit turns Edit mode on, Done off", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{ctx.gall.id}")

      assert has_element?(view, "a[href='/gall/#{ctx.gall.id}?edit'][aria-pressed=false]", "Edit")
      refute has_element?(view, "#gall-editor")

      {:ok, view, _html} = edit(ctx)

      assert has_element?(view, "a[href='/gall/#{ctx.gall.id}'][aria-pressed=true]", "Done")
      assert has_element?(view, "#gall-editor")
      assert has_element?(view, "[data-scope=elsewhere]")
    end

    test "the Inducer's lineage and synonyms are edited on its species page", ctx do
      {:ok, view, _html} = edit(ctx)

      assert has_element?(view, "#editing a[href='/species/#{ctx.wasp.id}?edit']")
      assert has_element?(view, "#gall-editor a[href='/species/#{ctx.wasp.id}?edit']")
      refute has_element?(view, "a[href='/admin/taxonomy/#{ctx.wasp.id}']")
    end
  end

  describe "Hosts" do
    test "each Host with its Sources and actions", ctx do
      {:ok, view, _html} = edit(ctx)
      row = "#fact-host-#{ctx.oak.id}"

      assert has_element?(view, "#{row} [data-part=fact]", "Quercus webcurata")
      assert has_element?(view, "#{row} [data-part=sources]", "Weld")

      assert has_element?(view, "#{row} button[phx-value-action=withdraw]")
      assert has_element?(view, "#{row} button[phx-value-action=correct]")
      assert has_element?(view, "#{row} button[phx-value-action=note]")
    end

    test "Withdraw puts it in the tray, and the row says so", ctx do
      {:ok, view, _html} = edit(ctx)

      view
      |> element("#fact-host-#{ctx.oak.id} button[phx-value-action=withdraw]")
      |> render_click()

      assert [{:fact, %{action: :withdraw, key: {:host, oak_id}}}] = items(ctx.actor)
      assert oak_id == ctx.oak.id
      assert has_element?(view, "#fact-host-#{ctx.oak.id} [data-part=pending]", "in your tray")
    end

    test "Correct… replaces it with another plant", ctx do
      rubra = plant_fixture(name: "Quercus rubrawebcurata")
      {:ok, view, _html} = edit(ctx)

      view
      |> element("#fact-host-#{ctx.oak.id} button[phx-value-action=correct]")
      |> render_click()

      assert has_element?(view, "#fact-dialog", "Quercus webcurata")

      view
      |> with_target("#gall-editor")
      |> render_hook("search_dialog_plant", %{"value" => "rubraweb"})

      view |> element("#fact-dialog-plant [phx-value-id='#{rubra.id}']") |> render_click()

      assert [{:fact, %{action: :correct, key: {:host, _}, to: {:host, to}}}] = items(ctx.actor)
      assert to == rubra.id
      refute has_element?(view, "#fact-dialog")
    end

    test "Note… records a note on the Host's Fact", ctx do
      {:ok, view, _html} = edit(ctx)

      view
      |> element("#fact-host-#{ctx.oak.id} button[phx-value-action=note]")
      |> render_click()

      view |> form("#fact-dialog form", %{"text" => "Only on young leaves."}) |> render_submit()

      assert [{:note, %{key: {:host, _}, text: "Only on young leaves."}}] = items(ctx.actor)
    end

    test "Add a host: found by name, shown as added", ctx do
      rubra = plant_fixture(name: "Quercus rubrawebcurata")
      {:ok, view, _html} = edit(ctx)

      view
      |> with_target("#gall-editor")
      |> render_hook("search_add_host", %{"value" => "rubraweb"})

      view |> element("#add-host [phx-value-id='#{rubra.id}']") |> render_click()

      assert [{:fact, %{action: :add, key: {:host, id}}}] = items(ctx.actor)
      assert id == rubra.id
      assert has_element?(view, "#fact-host-#{rubra.id} [data-part=pending]", "in your tray")
    end
  end

  describe "Traits" do
    test "a value's ✕ withdraws it; Add adds one", ctx do
      {:ok, view, _html} = edit(ctx)

      view |> element("#fact-trait-season-Spring button[phx-click=fact_action]") |> render_click()

      view
      |> form("#add-trait-season", %{"trait" => "season", "value" => "Summer"})
      |> render_change()

      assert [
               {:fact, %{action: :withdraw, key: {:trait, "season", "Spring"}}},
               {:fact, %{action: :add, key: {:trait, "season", "Summer"}}}
             ] = items(ctx.actor)

      assert has_element?(view, "#fact-trait-season-Spring.line-through")
      assert has_element?(view, "#fact-trait-season-Summer[data-pending]")
    end
  end

  describe "Common names" do
    test "each with its actions; Add a common name", ctx do
      {:ok, _} =
        Gallformers.Catalog.assert_alias(
          ctx.actor,
          %{gall_id: ctx.gall.id, name: "Webby knot"},
          Gallformers.CatalogFixtures.confirm(ctx.weld)
        )

      {:ok, view, _html} = edit(ctx)

      assert has_element?(view, "#fact-alias-Webby-knot [data-part=fact]", "Webby knot")

      view
      |> element("#fact-alias-Webby-knot button[phx-value-action=withdraw]")
      |> render_click()

      view |> form("#add-common-name", %{"name" => " Horned webgall "}) |> render_submit()

      assert [
               {:fact, %{action: :withdraw, key: {:alias, "Webby knot"}}},
               {:fact, %{action: :add, key: {:alias, "Horned webgall"}}}
             ] = items(ctx.actor)

      assert has_element?(view, "#fact-alias-Horned-webgall [data-part=pending]", "in your tray")
    end
  end

  describe "Editorial" do
    test "Completeness: mark it complete", ctx do
      {:ok, view, _html} = edit(ctx)

      view |> element("#editorial button[phx-click=completeness]") |> render_click()

      assert [{:editorial, %{field: :completeness, value: true}}] = items(ctx.actor)
      assert has_element?(view, "#editorial-completeness [data-part=pending]", "in your tray")
    end

    test "Completeness: a locked Gall can't be marked complete, and says why", ctx do
      bare = Gallformers.CatalogFixtures.gall_fixture()
      {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{bare.id}?edit")

      assert has_element?(view, "#editorial button[phx-click=completeness][disabled]")
      assert has_element?(view, "#editorial-completeness", "no Sources")
    end

    test "Abundance: chosen from the list", ctx do
      [first | _] = Gallformers.Catalog.list_abundances()
      {:ok, view, _html} = edit(ctx)

      view
      |> form("#editorial-abundance", %{"abundance" => to_string(first.id)})
      |> render_change()

      assert [{:editorial, %{field: :abundance, value: id}}] = items(ctx.actor)
      assert id == first.id
    end

    test "the code: another Gall's is refused as you type; a free one goes in the tray", ctx do
      Gallformers.CatalogFixtures.gall_fixture(gallformers_code: "WEBTAKEN")
      {:ok, view, _html} = edit(ctx)

      view |> element("#editorial button[phx-click=edit_code]") |> render_click()
      assert has_element?(view, "#code-dialog", "iNaturalist")

      html = view |> form("#code-form", %{"code" => "WEBTAKEN"}) |> render_change()
      assert html =~ "already used by another Gall"
      assert has_element?(view, "#code-form button[type=submit][disabled]")

      view |> form("#code-form", %{"code" => "WEBFREE"}) |> render_submit()

      assert [{:editorial, %{field: :code, value: "WEBFREE"}}] = items(ctx.actor)
      refute has_element?(view, "#code-dialog")
    end

    test "the name parts: the name they derive shown as you type, then in the tray", ctx do
      {:ok, view, _html} = edit(ctx)

      view |> element("#editorial button[phx-click=edit_name]") |> render_click()
      assert has_element?(view, "#name-dialog #name-shown")

      view
      |> form("#name-dialog-form", %{"name" => %{"name_override" => "Webcurata bud gall"}})
      |> render_change()

      assert has_element?(view, "#name-shown", "Webcurata bud gall")

      view
      |> form("#name-dialog-form", %{"name" => %{"name_override" => "Webcurata bud gall"}})
      |> render_submit()

      assert [{:editorial, %{field: :name_parts, value: parts}}] = items(ctx.actor)
      assert parts[:name_override] == "Webcurata bud gall"
      refute has_element?(view, "#name-dialog")
    end
  end

  test "once applied, the page shows the change", ctx do
    [first | _] = Gallformers.Catalog.list_abundances()
    {:ok, view, _html} = edit(ctx)

    view |> form("#editorial-abundance", %{"abundance" => to_string(first.id)}) |> render_change()
    {:ok, _} = Curation.apply(ctx.actor)

    assert has_element?(view, "#editorial-abundance-select option[selected][value='#{first.id}']")
    refute has_element?(view, "#editorial-abundance [data-part=pending]")
  end

  test "the marks follow the tray: a change taken out elsewhere is unmarked", ctx do
    {:ok, view, _html} = edit(ctx)

    view
    |> element("#fact-host-#{ctx.oak.id} button[phx-value-action=withdraw]")
    |> render_click()

    [item] = Curation.open_set(ctx.actor).items
    :ok = Curation.remove_item(ctx.actor, item.id)

    refute has_element?(view, "#fact-host-#{ctx.oak.id} [data-part=pending]")
    assert has_element?(view, "#fact-host-#{ctx.oak.id} button[phx-value-action=withdraw]")
  end

  test "another curator's unapplied changes here are named", ctx do
    {:ok, other} = Accounts.create_user(%{auth0_id: "auth0|other-curator", display_name: "Adam"})
    adam = Actor.user(other.id, "Adam")

    {:ok, _} =
      Curation.add_item(adam, %{
        kind: :fact,
        gall_id: ctx.gall.id,
        action: :withdraw,
        key: {:host, ctx.oak.id}
      })

    {:ok, view, _html} = edit(ctx)

    assert has_element?(view, "#others-pending", "Adam")
  end
end
