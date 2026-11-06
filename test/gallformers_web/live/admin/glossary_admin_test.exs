defmodule GallformersWeb.Admin.GlossaryAdminTest do
  @moduledoc """
  The glossary admin (`/admin/glossary`, design system matter bc0d): the
  list (filter, live updates, New entry) and the form (create, update,
  validation, discard unsaved changes, delete from a danger panel through a
  confirmation dialog), on the admin list and edit page patterns.

  Not async: admin access reads the site settings (persistent_term).
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Glossaries

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn)

    {:ok, entry} =
      Glossaries.create_glossary(%{
        word: "fixturoid",
        definition: "A gall made for a test.",
        urls: "https://example.org/fixturoid"
      })

    %{conn: conn, entry: entry}
  end

  describe "the list" do
    test "every entry, linked to its form, with its public anchor", %{conn: conn, entry: entry} do
      {:ok, view, _html} = live(conn, ~p"/admin/glossary")

      assert has_element?(view, "h1", "Glossary")

      assert has_element?(
               view,
               "#glossary-entries a[href='/admin/glossary/#{entry.id}']",
               "fixturoid"
             )

      assert has_element?(view, "#glossary-entries a[href='/glossary#fixturoid']")
      assert has_element?(view, "a[href='/admin/glossary/new']", "New entry")
    end

    test "the filter narrows the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/glossary")

      view |> form("#glossary-search-form", %{"query" => "zzz-no-such-word"}) |> render_change()

      refute has_element?(view, "#glossary-entries a", "fixturoid")
      assert has_element?(view, "[data-part=empty]")
    end

    test "an entry added elsewhere appears", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/glossary")

      {:ok, _} =
        Glossaries.create_glossary(%{
          word: "secondoid",
          definition: "Another.",
          urls: "https://example.org/s"
        })

      assert render(view) =~ "secondoid"
    end
  end

  describe "the form" do
    test "a new entry: create it, then edit it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/glossary/new")

      assert has_element?(view, "h1", "New glossary entry")

      assert has_element?(
               view,
               "nav[aria-label=Breadcrumb] a[href='/admin/glossary']",
               "Glossary"
             )

      {:error, {:live_redirect, %{to: to}}} =
        view
        |> form("#glossary-form",
          glossary: %{word: "neologoid", definition: "New.", urls: "https://example.org/n"}
        )
        |> render_submit()

      assert to =~ ~r{^/admin/glossary/\d+$}
    end

    test "an entry: its word as the title, View on site, and save", %{conn: conn, entry: entry} do
      {:ok, view, _html} = live(conn, ~p"/admin/glossary/#{entry.id}")

      assert has_element?(view, "h1", "fixturoid")
      assert has_element?(view, "a[href='/glossary#fixturoid']", "View on site")

      view
      |> form("#glossary-form", glossary: %{definition: "A better definition."})
      |> render_submit()

      assert Glossaries.get_glossary!(entry.id).definition == "A better definition."
    end

    test "a blank word is an error", %{conn: conn, entry: entry} do
      {:ok, view, _html} = live(conn, ~p"/admin/glossary/#{entry.id}")

      html = view |> form("#glossary-form", glossary: %{word: ""}) |> render_change()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end

    test "Cancel with unsaved changes asks first", %{conn: conn, entry: entry} do
      {:ok, view, _html} = live(conn, ~p"/admin/glossary/#{entry.id}")

      view |> form("#glossary-form", glossary: %{definition: "Changed."}) |> render_change()
      view |> element("button[phx-click=request_cancel]") |> render_click()

      assert has_element?(view, "button[phx-click=confirm_discard]")

      {:error, {:live_redirect, %{to: "/admin/glossary"}}} =
        view |> element("button[phx-click=confirm_discard]") |> render_click()
    end

    test "delete from the danger panel, through a confirmation", %{conn: conn, entry: entry} do
      {:ok, view, _html} = live(conn, ~p"/admin/glossary/#{entry.id}")

      view |> element("#danger button", "Delete…") |> render_click()
      assert has_element?(view, "#delete-entry", "fixturoid")

      {:error, {:live_redirect, %{to: "/admin/glossary"}}} =
        view |> element("#delete-entry button[phx-click=delete]") |> render_click()

      assert_raise Ecto.NoResultsError, fn -> Glossaries.get_glossary!(entry.id) end
    end
  end
end
