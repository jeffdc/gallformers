defmodule GallformersWeb.Admin.HostRangeLiveTest do
  @moduledoc """
  The Host range review (matter a856, decision 4), carried over from the
  old Host admin onto plant taxa: filters, bulk confirm, WCVP match / sync /
  ignore, each the signed-in admin's through
  `Gallformers.Import.record_wcvp_edit/2`; matching all filtered plants is
  superadmin-only. Each test searches its own plants by a unique tag.
  """
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Audit.Actor
  alias Gallformers.Import
  alias Gallformers.Ranges.Wcvp

  # A test tagged `roles: ["superadmin"]` signs in as a superadmin.
  setup %{conn: conn} = ctx do
    {conn, user} = log_in_admin(conn, "Hal Ranges", Map.get(ctx, :roles, ["admin"]))
    tag = "Hrv#{System.unique_integer([:positive])}"
    alba = plant_fixture(name: "#{tag} alba")
    rubra = plant_fixture(name: "#{tag} rubra")

    %{
      conn: conn,
      user: user,
      actor: Actor.user(user.id, "Hal Ranges"),
      tag: tag,
      alba: alba,
      rubra: rubra
    }
  end

  defp review(tag, params \\ %{}), do: ~p"/admin/host-range?#{Map.put(params, :search, tag)}"

  defp select(view, plant),
    do:
      view
      |> element("input[phx-click=toggle_select][phx-value-id='#{plant.id}']")
      |> render_click()

  describe "the review list" do
    test "lists unconfirmed plants, each linking to its taxonomy page", %{conn: conn} = ctx do
      {:ok, view, html} = live(conn, review(ctx.tag))

      assert html =~ "Host Range Review"
      assert html =~ "Needs Review"
      assert html =~ "WCVP data:"
      assert html =~ "#{ctx.tag} alba"
      assert has_element?(view, "a[href='/admin/taxonomy/#{ctx.alba.id}']")
      assert has_element?(view, "a[href='/admin']")
    end

    test "the search narrows the list", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, review(ctx.tag))

      view |> element("input[phx-keyup=search]") |> render_keyup(%{value: "#{ctx.tag} alba"})

      html = render(view)
      assert html =~ "#{ctx.tag} alba"
      refute html =~ "#{ctx.tag} rubra"
    end

    test "confirmed plants show under the confirmed filter", %{conn: conn, actor: actor} = ctx do
      {:ok, 1} = Wcvp.bulk_confirm_ranges(actor, [ctx.alba.id])

      {:ok, view, html} = live(conn, review(ctx.tag))
      refute html =~ "#{ctx.tag} alba"

      view |> element("form#filter") |> render_change(%{value: "confirmed"})

      assert render(view) =~ "#{ctx.tag} alba"
    end

    test "says so when every range is confirmed", %{conn: conn, actor: actor} do
      ids = for p <- Wcvp.list_refs_for_range_review(filter: :all, wcvp_match: :all), do: p.id
      {:ok, _} = Wcvp.bulk_confirm_ranges(actor, ids)

      {:ok, _view, html} = live(conn, ~p"/admin/host-range")

      assert html =~ "All host ranges confirmed!"
    end

    test "reads the filters from the URL", %{conn: conn} = ctx do
      {:ok, view, html} =
        live(conn, review(ctx.tag, %{filter: "confirmed", sync_status: "never"}))

      assert html =~ "No hosts match your search"
      assert has_element?(view, "form#sync_status_filter option[value=never][selected]")
    end

    test "select all and clear selection", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, review(ctx.tag))

      view |> element("th input[type=checkbox]") |> render_click()
      assert render(view) =~ "Confirm Selected (2)"

      view |> element("button", "Clear selection") |> render_click()
      refute render(view) =~ "Confirm Selected"
    end

    test "requires an admin" do
      conn = get(build_conn(), ~p"/admin/host-range")
      assert redirected_to(conn) =~ "/"
    end
  end

  describe "bulk actions" do
    test "confirms the selected plants' ranges, logged for replay", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, review(ctx.tag))

      select(view, ctx.alba)
      view |> element("button[phx-click=confirm_selected]") |> render_click()
      assert render(view) =~ "Confirm Host Ranges"

      view |> element("#confirm-modal button[phx-click=do_confirm_selected]") |> render_click()

      assert render(view) =~ "Confirmed range for 1 host(s)"
      assert Wcvp.get_link(ctx.alba.id).range_confirmed == true
      refute Wcvp.get_link(ctx.rubra.id)
      assert "set_wcvp" in Enum.map(Import.list_replay_entries(), & &1.key["op"])
    end

    test "cancelling a confirmation keeps the selection", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, review(ctx.tag))

      select(view, ctx.alba)
      view |> element("button[phx-click=confirm_selected]") |> render_click()
      view |> element("#confirm-modal button[phx-click=cancel_confirm]") |> render_click()

      assert has_element?(view, "button[phx-click=confirm_selected]")
    end

    test "syncs the selected plants from WCVP and reports the results", %{conn: conn} do
      plant = plant_fixture(name: "Wcvpseedus rangeus")
      {:ok, view, _html} = live(conn, review("Wcvpseedus"))

      select(view, plant)
      view |> element("button", "Sync Selected from WCVP") |> render_click()
      view |> element("#sync-confirm-modal button[phx-click=do_sync_selected]") |> render_click()
      render(view)
      html = render(view)

      assert html =~ "WCVP Sync Complete"
      assert html =~ "<strong>1</strong> host(s) synced"
      assert %DateTime{} = Wcvp.get_link(plant.id).wcvp_synced_at
      assert "set_host_range" in Enum.map(Import.list_replay_entries(), & &1.key["op"])
    end

    test "a plant WCVP doesn't know is reported as not matched", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, review(ctx.tag))

      select(view, ctx.alba)
      view |> element("button", "Sync Selected from WCVP") |> render_click()
      view |> element("#sync-confirm-modal button[phx-click=do_sync_selected]") |> render_click()
      render(view)
      html = render(view)

      assert html =~ "not matched"
      assert Wcvp.get_link(ctx.alba.id).wcvp_match_status == "no_match"
    end

    test "matches the selected plants without syncing their ranges", %{conn: conn} do
      plant = plant_fixture(name: "Wcvptestus alpinus")
      {:ok, view, _html} = live(conn, review("Wcvptestus"))

      select(view, plant)
      view |> element("button", "Match Selected to WCVP") |> render_click()

      view
      |> element("#match-confirm-modal button[phx-click=do_match_selected]")
      |> render_click()

      render(view)
      html = render(view)

      assert html =~ "WCVP Match Complete"
      link = Wcvp.get_link(plant.id)
      assert link.wcvp_id == "700"
      assert link.powo_id == "urn:lsid:ipni.org:names:test700"
      assert link.wcvp_synced_at == nil
    end

    test "ignored plants are left out by default, can be shown, and cleared again",
         %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, review(ctx.tag))

      select(view, ctx.alba)
      view |> element("button", "Ignore Selected") |> render_click()

      assert Wcvp.get_link(ctx.alba.id).wcvp_match_status == "ignored"
      refute render(view) =~ "#{ctx.tag} alba"

      {:ok, view, html} = live(conn, review(ctx.tag, %{wcvp: "ignored"}))
      assert html =~ "#{ctx.tag} alba"
      assert html =~ "ignored"

      select(view, ctx.alba)
      view |> element("button", "Clear Match Status") |> render_click()

      assert is_nil(Wcvp.get_link(ctx.alba.id).wcvp_match_status)
      refute render(view) =~ "#{ctx.tag} alba"
    end
  end

  describe "matching all filtered plants" do
    test "is not offered to an admin", %{conn: conn} = ctx do
      {:ok, _view, html} = live(conn, review(ctx.tag))
      refute html =~ "Match All Filtered to WCVP"
    end

    @tag roles: ["superadmin"]
    test "is offered to a superadmin", %{conn: conn} = ctx do
      {:ok, _view, html} = live(conn, review(ctx.tag))
      assert html =~ "Match All Filtered to WCVP"
      assert html =~ "Super Admin only"
    end

    @tag roles: ["superadmin"]
    test "a superadmin matches every plant the filters select", %{conn: conn} do
      plant = plant_fixture(name: "Wcvptestus alpinus")

      {:ok, view, _html} = live(conn, review("Wcvptestus"))

      view |> element("button", "Match All Filtered to WCVP") |> render_click()
      assert render(view) =~ "all currently filtered"

      view
      |> element("#match-confirm-modal button[phx-click=do_match_all_filtered]")
      |> render_click()

      render(view)
      html = render(view)

      assert html =~ "linked"
      assert Wcvp.get_link(plant.id).wcvp_id == "700"
    end

    test "an admin's request is refused", %{conn: conn} do
      plant = plant_fixture(name: "Wcvptestus alpinus")
      {:ok, view, _html} = live(conn, review("Wcvptestus"))

      render_hook(view, "match_all_filtered", %{})
      assert render(view) =~ "Only superadmins can match all filtered hosts"

      render_hook(view, "do_match_all_filtered", %{})
      assert is_nil(Wcvp.get_link(plant.id))
    end
  end
end
