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
  alias Gallformers.Curation.Wording

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

  defp tray(actor) do
    case Curation.open_set(actor) do
      nil -> []
      set -> set.items
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
      refute has_element?(view, "a[href='/admin/taxonomy/#{ctx.wasp.id}']")
    end
  end

  # Edit mode acts through the Fact inspector (matter 87a1, task 7): each
  # action in Gallformers' block of the selected Fact, each group's Add.
  defp open_fact(ctx, key), do: live(ctx.conn, ~p"/gall/#{ctx.gall.id}?edit&fact=#{key}")

  defp act(view, action),
    do: view |> element("#fact-inspector button[phx-value-action=#{action}]") |> render_click()

  defp submit_why(view, why),
    do: view |> form("#fact-action-form", %{"why" => why}) |> render_submit()

  describe "Gallformers' actions in the inspector" do
    test "a Fact's Gallformers block has Change…, Deny… and Add a note…; Confirm… when Gallformers hasn't stated it",
         ctx do
      {:ok, view, _html} = open_fact(ctx, "host:#{ctx.oak.id}")
      gallformers = "#fact-inspector [data-source=gallformers]"

      assert has_element?(view, gallformers, "Gallformers hasn't stated this")

      for {action, words} <- [
            confirm: "Confirm…",
            correct: "Change…",
            withdraw: "Deny…",
            note: "Add a note…"
          ] do
        assert has_element?(view, "#{gallformers} button[phx-value-action=#{action}]", words)
      end
    end

    test "Deny… puts Gallformers' denial in the tray with its reason, and the block says so",
         ctx do
      {:ok, view, _html} = open_fact(ctx, "host:#{ctx.oak.id}")

      act(view, "withdraw")
      submit_why(view, "Not on oaks: a misidentified maple.")

      assert [{:fact, %{action: :withdraw, key: {:host, oak_id}}}] = items(ctx.actor)
      assert oak_id == ctx.oak.id
      assert [%{evidence: %{text: "Not on oaks: a misidentified maple."}}] = tray(ctx.actor)

      assert has_element?(
               view,
               "#fact-inspector [data-source=gallformers] [data-part=pending]",
               "In your tray: Deny host: Quercus webcurata"
             )

      refute has_element?(view, "#fact-inspector button[phx-value-action=withdraw]")
    end

    test "Take out takes it out of the tray, and the actions come back", ctx do
      {:ok, view, _html} = open_fact(ctx, "host:#{ctx.oak.id}")
      act(view, "withdraw")
      submit_why(view, "")

      view |> element("#fact-inspector button", "Take out") |> render_click()

      assert items(ctx.actor) == []
      assert has_element?(view, "#fact-inspector button[phx-value-action=withdraw]")
    end

    test "a change taken out elsewhere comes off the inspector too", ctx do
      {:ok, view, _html} = open_fact(ctx, "host:#{ctx.oak.id}")
      act(view, "withdraw")
      submit_why(view, "")

      [item] = Curation.open_set(ctx.actor).items
      :ok = Curation.remove_item(ctx.actor, item.id)

      refute has_element?(view, "#fact-inspector [data-part=pending]")
      assert has_element?(view, "#fact-inspector button[phx-value-action=withdraw]")
    end

    test "Change… a Host to another plant, found by the plant search", ctx do
      rubra = plant_fixture(name: "Quercus rubrawebcurata")
      {:ok, view, _html} = open_fact(ctx, "host:#{ctx.oak.id}")

      act(view, "correct")

      view
      |> with_target("#fact-actions")
      |> render_hook("search_plant", %{"value" => "rubraweb"})

      view |> element("#fact-action-plant [phx-value-id='#{rubra.id}']") |> render_click()
      submit_why(view, "")

      assert [{:fact, %{action: :correct, key: {:host, _}, to: {:host, to}}}] = items(ctx.actor)
      assert to == rubra.id
    end

    test "Change… a Trait value to another of its values", ctx do
      {:ok, view, _html} = open_fact(ctx, "trait:season:Spring")

      act(view, "correct")
      view |> element("#fact-action-values-Summer") |> render_click()
      submit_why(view, "")

      assert [{:fact, %{action: :correct, key: {:trait, "season", "Spring"}, to: to}}] =
               items(ctx.actor)

      assert to == {:trait, "season", "Summer"}
    end

    test "Change… with nothing chosen says what's missing and adds nothing", ctx do
      {:ok, view, _html} = open_fact(ctx, "host:#{ctx.oak.id}")

      act(view, "correct")
      submit_why(view, "")

      assert has_element?(view, "#fact-action-error", "Choose the plant it should be.")
      assert items(ctx.actor) == []
    end

    test "Add a note… is a note on the Fact, not a statement; it needs its words", ctx do
      {:ok, view, _html} = open_fact(ctx, "host:#{ctx.oak.id}")

      act(view, "note")
      submit_why(view, "  ")
      assert has_element?(view, "#fact-action-error", "Write the note.")

      submit_why(view, "Only on young leaves.")
      assert [{:note, %{key: {:host, _}, text: "Only on young leaves."}}] = items(ctx.actor)
    end

    test "an observation's link in Why becomes the statement's Observation", ctx do
      {:ok, view, _html} = open_fact(ctx, "host:#{ctx.oak.id}")

      act(view, "confirm")
      submit_why(view, "Seen here: https://www.inaturalist.org/observations/318135694")

      assert [%{evidence: %{observations: [%{provider: "inaturalist", id: "318135694"}]}}] =
               tray(ctx.actor)
    end

    test "Cancel closes the form", ctx do
      {:ok, view, _html} = open_fact(ctx, "host:#{ctx.oak.id}")

      act(view, "withdraw")
      view |> element("#fact-action-form button", "Cancel") |> render_click()

      refute has_element?(view, "#fact-action-form")
      assert items(ctx.actor) == []
    end

    test "the Inducer: a note only; its taxonomy is edited on its page", ctx do
      {:ok, view, _html} = open_fact(ctx, "inducer:#{ctx.wasp.id}")

      assert has_element?(view, "#fact-inspector button[phx-value-action=note]")
      refute has_element?(view, "#fact-inspector button[phx-value-action=withdraw]")
      assert has_element?(view, "#fact-inspector a[href='/species/#{ctx.wasp.id}?edit']")
    end

    test "readers never see the actions", ctx do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, view, _html} = live(conn, ~p"/gall/#{ctx.gall.id}?edit&fact=host:#{ctx.oak.id}")

      assert has_element?(view, "#fact-inspector")
      refute has_element?(view, "#fact-inspector button[phx-value-action]")
    end
  end

  # Fixing how Gallformers read a Source (matter 87a1, task 9): a level
  # deeper than Gallformers' own changes, under the Source's authority.
  describe "fixing a reading of a Source" do
    setup ctx, do: quote_weld_host!(ctx.actor, ctx)

    defp weld(ctx), do: "#fact-inspector [data-source='#{ctx.weld.id}']"

    defp fix_reading(view, ctx) do
      view |> element("#fact-readings-toggle") |> render_click()
      view |> element("#{weld(ctx)} button", "Fix our reading…") |> render_click()
    end

    test "the toggle shows Fix our reading… on the other Sources only", ctx do
      {:ok, view, _html} = open_fact(ctx, "host:#{ctx.oak.id}")

      refute has_element?(view, "#fact-inspector button", "Fix our reading…")
      assert has_element?(view, "#fact-readings-toggle", "Found an error in a Source reading?")

      view |> element("#fact-readings-toggle") |> render_click()

      assert has_element?(view, "#{weld(ctx)} button", "Fix our reading…")
      refute has_element?(view, "#fact-inspector [data-source=gallformers] [data-part=reading]")
      assert has_element?(view, "#fact-readings-toggle", "Done fixing readings")

      view |> element("#fact-readings-toggle") |> render_click()
      refute has_element?(view, "#fact-inspector button", "Fix our reading…")
    end

    test "the form names the Source and its date", ctx do
      {:ok, view, _html} = open_fact(ctx, "host:#{ctx.oak.id}")
      fix_reading(view, ctx)
      name = Wording.source_name(ctx.weld)

      assert has_element?(view, "#{weld(ctx)} #fact-action-form", "What #{name} actually says")
      assert has_element?(view, "#{weld(ctx)}", "Under #{name}'s authority, at its date (1959)")
    end

    test "what the Source does say goes in the tray as its reading fix, with the Why", ctx do
      bicolor = plant_fixture(name: "Quercus bicolorwebcurata")
      {:ok, view, _html} = open_fact(ctx, "host:#{ctx.oak.id}")
      fix_reading(view, ctx)

      view
      |> with_target("#fact-actions")
      |> render_hook("search_plant", %{"value" => "bicolorweb"})

      view |> element("#fact-action-plant [phx-value-id='#{bicolor.id}']") |> render_click()
      submit_why(view, "Weld names Q. bicolor on p. 41.")

      assert [{:reading, %{source_id: source_id, key: {:host, oak_id}, to: {:host, to}}}] =
               items(ctx.actor)

      assert {source_id, oak_id, to} == {ctx.weld.id, ctx.oak.id, bicolor.id}
      assert [%{evidence: %{text: "Weld names Q. bicolor on p. 41."}}] = tray(ctx.actor)

      assert has_element?(
               view,
               "#{weld(ctx)} [data-part=reading]",
               "In your tray: Fix our reading"
             )

      refute has_element?(view, "#fact-inspector [data-source=gallformers] [data-part=pending]")

      view |> element("#{weld(ctx)} button", "Take out") |> render_click()
      assert items(ctx.actor) == []
    end

    test "It doesn't say this: the Source's statement goes, nothing in its place", ctx do
      {:ok, view, _html} = open_fact(ctx, "host:#{ctx.oak.id}")
      fix_reading(view, ctx)

      view
      |> form("#fact-action-form", %{"why" => "", "unstated" => "true"})
      |> render_submit()

      assert [{:reading, %{source_id: source_id, to: nil}}] = items(ctx.actor)
      assert source_id == ctx.weld.id
    end

    test "readers never see it", ctx do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, view, _html} = live(conn, ~p"/gall/#{ctx.gall.id}?fact=host:#{ctx.oak.id}")

      refute has_element?(view, "#fact-readings-toggle")
    end
  end

  describe "adding" do
    test "each group has its Add; the Traits not recorded are each an add", ctx do
      {:ok, view, _html} = edit(ctx)

      assert has_element?(
               view,
               "#gall-hosts button[phx-click=add_fact][phx-value-group=host]",
               "Add a host"
             )

      assert has_element?(view, "#gall-range button[phx-value-group=range]", "Add a place")

      assert has_element?(
               view,
               "#gall-common-names button[phx-value-group=alias]",
               "Add a common name"
             )

      assert has_element?(view, "#gall-traits button[phx-value-group='trait:season']", "Add")

      assert has_element?(
               view,
               "#gall-traits-section button[phx-value-group='trait:color']",
               "color"
             )
    end

    test "Add a host: a new Fact through the plant search, then shown as proposed", ctx do
      rubra = plant_fixture(name: "Quercus rubrawebcurata")
      {:ok, view, _html} = edit(ctx)

      view |> element("#gall-hosts button[phx-click=add_fact]") |> render_click()
      assert has_element?(view, "#fact-inspector [data-part=kind]", "New Host")

      view
      |> with_target("#fact-actions")
      |> render_hook("search_plant", %{"value" => "rubraweb"})

      view |> element("#fact-action-plant [phx-value-id='#{rubra.id}']") |> render_click()
      submit_why(view, "On red oak at the arboretum.")

      assert [{:fact, %{action: :add, key: {:host, id}}}] = items(ctx.actor)
      assert id == rubra.id
      assert has_element?(view, "#gall-hosts [data-proposed]", "Quercus rubrawebcurata")
    end

    test "+ color: values of a Trait not recorded, one change each", ctx do
      {:ok, view, _html} = edit(ctx)

      view
      |> element("#gall-traits-section button[phx-value-group='trait:color']")
      |> render_click()

      assert has_element?(view, "#fact-inspector [data-part=kind]", "New Color")

      view |> element("#fact-action-values-red") |> render_click()
      view |> element("#fact-action-values-brown") |> render_click()
      submit_why(view, "")

      assert ctx.actor
             |> items()
             |> Enum.map(fn {:fact, %{action: :add, key: key}} -> key end)
             |> Enum.sort() ==
               [{:trait, "color", "brown"}, {:trait, "color", "red"}]
    end

    test "Add a common name: written in", ctx do
      {:ok, view, _html} = edit(ctx)

      view |> element("button[phx-value-group=alias]") |> render_click()

      view
      |> form("#fact-action-form", %{"value" => " Horned webgall ", "why" => ""})
      |> render_submit()

      assert [{:fact, %{action: :add, key: {:alias, "Horned webgall"}}}] = items(ctx.actor)
    end

    test "Add a place: one of the three kinds, the place through the place search", ctx do
      {:ok, view, _html} = edit(ctx)
      alberta = Gallformers.CatalogFixtures.place_id("CA-AB")

      view |> element("button[phx-value-group=range]") |> render_click()

      view
      |> with_target("#fact-actions")
      |> render_hook("search_place", %{"value" => "albert"})

      view |> element("#fact-action-place [phx-value-id='#{alberta}']") |> render_click()

      view
      |> form("#fact-action-form", %{"adjustment" => "occurrence", "why" => ""})
      |> render_submit()

      assert [{:fact, %{action: :add, key: {:occurrence, ^alberta}}}] = items(ctx.actor)
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
