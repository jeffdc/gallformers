defmodule GallformersWeb.PaletteLiveTest do
  @moduledoc """
  The command palette (`GallformersWeb.PaletteLive`, a sticky LiveView in
  the root layout): closed until opened (the header's trigger, or `/` or
  `s`, which send it `open`); a search field; the groups of
  `GallformersWeb.Palette`; ↑ ↓ move the selection; Esc or a click outside
  closes it.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import GallformersWeb.AdminLiveHelpers, only: [log_in_admin: 1, log_in_admin: 2]
  import Gallformers.CatalogFixtures, only: [gall_fixture: 1]

  alias Gallformers.Audit.Actor
  alias Gallformers.Curation
  alias GallformersWeb.PaletteLive

  defp palette(conn, user \\ nil) do
    {:ok, view, _html} = live_isolated(conn, PaletteLive, session: %{"current_user" => user})
    view
  end

  test "closed until opened; then the search field and the Go to list" do
    view = palette(build_conn())
    refute has_element?(view, "[role=dialog]")

    render_hook(view, "open", %{})

    assert has_element?(view, "[role=dialog][aria-label='Search Gallformers'] input#palette-q")
    assert has_element?(view, "#palette-results a[href='/id']", "Identify a gall")
    refute has_element?(view, "#palette-results", "Edit this page")
  end

  test "a curator gets their commands", %{conn: conn} do
    curator = %Gallformers.Accounts.Auth0User{
      id: "u1",
      name: "Ada",
      nickname: "ada",
      roles: ["admin"]
    }

    view = palette(conn, curator)
    render_hook(view, "open", %{})

    assert has_element?(view, "#palette-results a[href='/admin/changes']", "Changes")
  end

  test "typing searches; the first row is selected, and the arrows move it", %{conn: conn} do
    view = palette(conn)
    render_hook(view, "open", %{})

    view
    |> form("#palette-form", %{"q" => "glossary-term-that-matches-nothing"})
    |> render_change()

    assert has_element?(view, "#palette-row-0[aria-selected=true]", "See every result")

    render_hook(view, "open", %{})
    view |> form("#palette-form", %{"q" => ""}) |> render_change()
    render_keydown(view, "key", %{"key" => "ArrowDown"})

    assert has_element?(view, "#palette-row-1[aria-selected=true]", "Browse galls")
    assert has_element?(view, "input#palette-q[aria-activedescendant=palette-row-1]")
  end

  test "a curator typing finds their commands", %{conn: conn} do
    {conn, _user} = log_in_admin(conn)
    view = palette(conn, get_session(conn, :current_user))
    render_hook(view, "open", %{})

    view |> form("#palette-form", %{"q" => "observation"}) |> render_change()

    assert has_element?(
             view,
             "#palette-results a[href='/admin/observation']",
             "Add from observation…"
           )
  end

  describe "a curator's changes" do
    setup %{conn: conn} do
      {conn, user} = log_in_admin(conn, "Ada Curator")
      %{conn: conn, actor: Actor.user(user.id, "Ada Curator")}
    end

    defp add_change!(actor) do
      gall = gall_fixture(name: "Andricus palettrayi gall")

      {:ok, _} =
        Curation.add_item(actor, %{
          kind: :editorial,
          subject: {:gall, gall.id},
          field: :completeness,
          value: true
        })
    end

    test "shown when opened: the count, each change, and Review and apply", %{
      conn: conn,
      actor: actor
    } do
      view = palette(conn, get_session(conn, :current_user))
      add_change!(actor)
      render_hook(view, "open", %{})

      assert has_element?(view, "#palette-results", "Your changes")
      assert has_element?(view, "#palette-row-0", "Review and apply")
      assert has_element?(view, "#palette-row-0", "1 change in your tray")
      assert has_element?(view, "#palette-row-1", "Andricus palettrayi gall: Completeness")
    end

    test "Review and apply opens the tray's own: the palette closes, the tray reviews", %{
      conn: conn,
      actor: actor
    } do
      add_change!(actor)
      view = palette(conn, get_session(conn, :current_user))
      render_hook(view, "open", %{})

      for row <- ["#palette-row-0", "#palette-row-1"] do
        assert has_element?(view, "#{row}[phx-click*='\"close\"'][phx-click*='\"tray_review\"']")
        assert has_element?(view, "#{row}[phx-click*='\"target\":\"#tray\"']")
      end
    end

    test "none while the tray is empty", %{conn: conn} do
      view = palette(conn, get_session(conn, :current_user))
      render_hook(view, "open", %{})

      refute has_element?(view, "#palette-results", "Your changes")
      refute has_element?(view, "#palette-results", "Review and apply")
    end
  end

  test "Esc and close shut it", %{conn: conn} do
    view = palette(conn)

    render_hook(view, "open", %{})
    render_keydown(view, "key", %{"key" => "Escape"})
    refute has_element?(view, "[role=dialog]")

    render_hook(view, "open", %{})
    render_hook(view, "close", %{})
    refute has_element?(view, "[role=dialog]")
  end

  test "opening again starts fresh", %{conn: conn} do
    view = palette(conn)
    render_hook(view, "open", %{})
    view |> form("#palette-form", %{"q" => "quercus"}) |> render_change()
    render_hook(view, "close", %{})

    render_hook(view, "open", %{})
    assert has_element?(view, "input#palette-q[value='']")
    assert has_element?(view, "#palette-results a[href='/id']")
  end
end
