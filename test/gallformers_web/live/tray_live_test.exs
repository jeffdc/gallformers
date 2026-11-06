defmodule GallformersWeb.TrayLiveTest do
  @moduledoc """
  The curator's tray (`GallformersWeb.TrayLive`, matter ec2c): one sticky
  LiveView in the root layout, on every page, for curators only. It shows
  the tray bar while the curator's change set holds items, keeps up with
  it (PubSub), and runs Review and apply: each item with the back end's
  flags, taken out singly, confirmed where needed, the evidence asked once,
  applied singly or all together; Discard after a confirmation.

  Not async: the fixtures make the Gallformers Source (one per database).
  """
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import GallformersWeb.AdminLiveHelpers
  import GallformersWeb.CurationWebFixtures
  import Gallformers.CatalogFixtures, only: [plant_fixture: 1]

  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Curation
  alias Gallformers.Facts
  alias GallformersWeb.TrayLive

  setup %{conn: conn} do
    {conn, user} = log_in_admin(conn, "Ada Curator")
    actor = Actor.user(user.id, "Ada Curator")
    ctx = curated_gall!(actor)
    Map.merge(ctx, %{conn: conn, actor: actor})
  end

  defp tray(conn), do: live_isolated(conn, TrayLive, session: get_session(conn))

  defp add!(actor, spec) do
    {:ok, item} = Curation.add_item(actor, spec)
    item
  end

  defp withdraw_host!(ctx),
    do:
      add!(ctx.actor, %{
        kind: :fact,
        gall_id: ctx.gall.id,
        action: :withdraw,
        key: {:host, ctx.oak.id}
      })

  describe "the bar" do
    test "nothing for someone who isn't a curator", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{})
      {:ok, view, _html} = live_isolated(conn, TrayLive, session: %{})

      refute has_element?(view, "#change-tray")
    end

    test "nothing while the tray is empty", %{conn: conn} do
      {:ok, view, _html} = tray(conn)

      refute has_element?(view, "#change-tray")
    end

    test "the count and the changes", ctx do
      withdraw_host!(ctx)
      {:ok, view, _html} = tray(ctx.conn)

      assert has_element?(view, "#change-tray [data-part=count]", "1 change in your tray")
      assert has_element?(view, "#change-tray [data-part=lines]", "Andricus webcuratus gall")
    end

    test "keeps up with edits made on other pages", ctx do
      {:ok, view, _html} = tray(ctx.conn)
      refute has_element?(view, "#change-tray")

      withdraw_host!(ctx)

      assert has_element?(view, "#change-tray [data-part=count]", "1 change")
    end

    test "is on every page for a curator, public and admin", ctx do
      withdraw_host!(ctx)

      for path <- ["/about", "/gall/#{ctx.gall.id}", "/admin"] do
        assert html_response(get(ctx.conn, path), 200) =~ ~s(id="change-tray")
      end
    end
  end

  describe "Review and apply" do
    test "each change with its flags, in the back end's words", ctx do
      item = withdraw_host!(ctx)
      {:ok, view, _html} = tray(ctx.conn)

      view |> element("#change-tray button[phx-click=tray_review]") |> render_click()

      assert has_element?(view, "#review-dialog #review-item-#{item.id}", "Quercus webcurata")
      assert has_element?(view, "#review-item-#{item.id} [data-flag=supersedes]")
      assert has_element?(view, "#review-item-#{item.id} [data-flag=needs_reason]")
    end

    test "a change taken out leaves the tray", ctx do
      item = withdraw_host!(ctx)
      {:ok, view, _html} = tray(ctx.conn)
      view |> element("#change-tray button[phx-click=tray_review]") |> render_click()

      view |> element("#review-item-#{item.id} button[phx-click=remove_item]") |> render_click()

      assert Curation.open_set(ctx.actor) == nil
      refute has_element?(view, "#change-tray")
      refute has_element?(view, "#review-dialog")
    end

    test "the evidence, once for the set, lets a superseding change apply", ctx do
      withdraw_host!(ctx)
      {:ok, view, _html} = tray(ctx.conn)
      view |> element("#change-tray button[phx-click=tray_review]") |> render_click()

      view
      |> form("#review-evidence", %{
        "evidence" => %{
          "text" => "Not a host: misidentified.",
          "observations" => "https://www.inaturalist.org/observations/555"
        }
      })
      |> render_change()

      assert %{
               evidence: %{
                 text: "Not a host: misidentified.",
                 observations: [%{provider: "inaturalist", id: "555"}]
               }
             } = Curation.open_set(ctx.actor)

      refute has_element?(view, "[data-flag=needs_reason]")

      view |> element("#review-dialog button[phx-click=apply_all]") |> render_click()

      assert Facts.get_fact!(ctx.host.id).standing == :withdrawn
      assert Curation.open_set(ctx.actor) == nil
      refute has_element?(view, "#change-tray")
    end

    test "a change needing confirmation applies once confirmed, alone", ctx do
      item =
        add!(ctx.actor, %{
          kind: :editorial,
          subject: {:gall, ctx.gall.id},
          field: :code,
          value: "AWEB"
        })

      other =
        add!(ctx.actor, %{
          kind: :fact,
          gall_id: ctx.gall.id,
          action: :add,
          key: {:host, plant_fixture(name: "Quercus altera").id}
        })

      {:ok, view, _html} = tray(ctx.conn)
      view |> element("#change-tray button[phx-click=tray_review]") |> render_click()

      assert has_element?(view, "#review-item-#{item.id} button[phx-click=apply_item][disabled]")

      view |> element("#review-item-#{item.id} input[phx-click=toggle_confirm]") |> render_click()
      view |> element("#review-item-#{item.id} button[phx-click=apply_item]") |> render_click()

      assert Catalog.get_gall!(ctx.gall.id).gallformers_code == "AWEB"
      assert [%{id: id}] = Curation.open_set(ctx.actor).items
      assert id == other.id
    end

    test "a Source as evidence: found by its title", ctx do
      withdraw_host!(ctx)
      {:ok, view, _html} = tray(ctx.conn)
      view |> element("#change-tray button[phx-click=tray_review]") |> render_click()

      render_hook(view, "search_evidence_source", %{"value" => "Weld"})
      assert has_element?(view, "#review-evidence-source", "Weld")

      render_hook(view, "select_evidence_source", %{"id" => to_string(ctx.weld.id)})

      assert %{evidence: %{source_id: source_id}} = Curation.open_set(ctx.actor)
      assert source_id == ctx.weld.id
    end
  end

  test "Discard empties the tray after a confirmation", ctx do
    withdraw_host!(ctx)
    {:ok, view, _html} = tray(ctx.conn)

    view |> element("#change-tray button[phx-click=tray_discard]") |> render_click()
    assert has_element?(view, "#discard-tray")
    assert Curation.open_set(ctx.actor) != nil

    view |> element("#discard-tray button[phx-click=confirm_discard_tray]") |> render_click()

    assert Curation.open_set(ctx.actor) == nil
    refute has_element?(view, "#change-tray")
  end
end
