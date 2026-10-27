defmodule GallformersWeb.Admin.DashboardLiveTest do
  @moduledoc """
  LiveView tests for the admin dashboard.
  """
  # async: false because admin access is gated by SiteSettings.read_only?/0,
  # which reads from persistent_term-backed global state.
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Gallformers.DataCase, only: [audit_test_metadata: 1]

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Repo

  describe "Admin dashboard" do
    setup %{conn: conn} do
      # Create a mock user session for admin access (must be a User struct)
      user = %Auth0User{
        id: "test-user-id",
        email: "admin@test.com",
        name: "Test Admin",
        nickname: nil,
        picture: nil,
        roles: ["admin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user)
        |> put_session(:db_display_name, "Test User")

      {:ok, conn: conn, user: user}
    end

    test "renders dashboard when authenticated", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Dashboard" or html =~ "Admin"
    end

    test "displays stats cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      # Should show stat cards
      assert html =~ "Galls" or html =~ "Hosts" or html =~ "Sources" or html =~ "Images"
    end

    test "stats show formatted numbers", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      # Stats should be displayed (numbers)
      assert Regex.match?(~r/\d+/, html) == true
    end

    test "displays quick actions section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      # Dashboard shows "Create a New" action cards
      assert html =~ "Create a New"
    end

    test "quick action links are present", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      # Should have action links
      assert has_element?(view, "a[href*='/admin/']")
    end

    test "welcome section is displayed", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Need help?" or html =~ "Discord"
    end
  end

  describe "Admin dashboard stats" do
    setup %{conn: conn} do
      user = %Auth0User{
        id: "test-user-id",
        email: "admin@test.com",
        name: "Test Admin",
        nickname: nil,
        picture: nil,
        roles: ["admin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user)
        |> put_session(:db_display_name, "Test User")

      {:ok, conn: conn}
    end

    test "gall count is displayed", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Galls"
    end

    test "host count is displayed", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Host"
    end

    test "source count is displayed", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Source"
    end

    test "image count is displayed", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Image"
    end
  end

  describe "Admin dashboard quick actions" do
    setup %{conn: conn} do
      user = %Auth0User{
        id: "test-user-id",
        email: "admin@test.com",
        name: "Test Admin",
        nickname: nil,
        picture: nil,
        roles: ["admin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user)
        |> put_session(:db_display_name, "Test User")

      {:ok, conn: conn}
    end

    test "the Galls count links to the Gall search; there is no new-Gall action",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#admin-stats a[href='/admin/galls']", "Galls")
      assert has_element?(view, "#admin-quick-actions a[href='/admin/galls']", "Find a Gall")
      refute has_element?(view, "a[href^='/admin/galls/']")
    end

    test "the new-Host action, the Host range review and the Hosts count go to the taxonomy admin",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "a[href='/admin/taxonomy/new']", "Create a New Host")
      assert has_element?(view, "a[href='/admin/host-range']", "Review Host Ranges")
      assert has_element?(view, "#admin-stats a[href='/admin/taxonomy']", "Hosts")
      refute has_element?(view, "a[href^='/admin/hosts']")
      refute has_element?(view, "a[href^='/admin/section']")
    end

    test "the Sources action and count go to the Source editor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#admin-quick-actions a[href='/admin/sources']", "Find a Source")
      assert has_element?(view, "#admin-stats a[href='/admin/sources']", "Sources")
    end

    test "the review queue action leads the quick actions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(
               view,
               "#admin-quick-actions a[href='/admin/queue']",
               "Review the Queue"
             )
    end

    test "links to no deleted old screen", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      for prefix <- ~w(/admin/gallhost /admin/gall-range /admin/images /admin/image-audit
                       /admin/filter-terms /admin/species-sources) do
        refute has_element?(view, "a[href^='#{prefix}']"), "link to #{prefix}"
      end

      refute render(view) =~ "Being rebuilt"
    end

    test "the Images count is shown, unlinked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#admin-stats div", "Images")
      refute has_element?(view, "#admin-stats a", "Images")
    end

    test "add article link exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "a[href='/admin/articles/new']") or
               render(view) =~ "Create a New Article"
    end

    test "taxonomy link exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "a[href='/admin/taxonomy']") or
               render(view) =~ "Taxonomy"
    end

    test "glossary link exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "a[href='/admin/glossary']") or
               render(view) =~ "Glossary"
    end

    test "superadmin links are hidden from regular admins", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      refute has_element?(view, "a[href='/admin/jobs']")
      refute render(view) =~ "Super Admin"
    end
  end

  describe "Admin dashboard review queue" do
    setup %{conn: conn} do
      user = %Auth0User{
        id: "test-user-id",
        email: "admin@test.com",
        name: "Test Admin",
        nickname: nil,
        picture: nil,
        roles: ["admin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user)
        |> put_session(:db_display_name, "Test User")

      {:ok, conn: conn}
    end

    setup :audit_test_metadata

    defp rename_item!(n) do
      %QueueItem{}
      |> QueueItem.create_changeset(%{
        kind: :gall_rename,
        subject: %{"gall_id" => n},
        proposal: %{"gall_id" => n, "from" => "A #{n}", "to" => "B #{n}", "collision" => false},
        reason: "renamed"
      })
      |> Repo.insert!()
    end

    test "counts the open items, linking to the queue and to each kind", %{conn: conn} do
      before = Import.count_open_queue_items()
      rename_item!(1)
      rename_item!(2)
      renames = Map.get(before, :gall_rename, 0) + 2
      total = before |> Map.values() |> Enum.sum() |> Kernel.+(2)

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#admin-queue a[href='/admin/queue']", "Open items")
      assert has_element?(view, "#admin-queue a[href='/admin/queue']", to_string(total))

      assert has_element?(
               view,
               "#admin-queue a[href='/admin/queue?kind=gall_rename']",
               "Gall rename proposal"
             )

      assert has_element?(
               view,
               "#admin-queue a[href='/admin/queue?kind=gall_rename']",
               to_string(renames)
             )
    end

    test "lists only the kinds with open items", %{conn: conn} do
      rename_item!(3)
      counts = Import.count_open_queue_items()

      {:ok, view, _html} = live(conn, ~p"/admin")

      for kind <- QueueItem.kinds() do
        assert has_element?(view, "#admin-queue a[href='/admin/queue?kind=#{kind}']") ==
                 Map.has_key?(counts, kind),
               "kind #{kind}"
      end
    end
  end

  describe "Admin navigation" do
    setup %{conn: conn} do
      user = %Auth0User{
        id: "test-user-id",
        email: "admin@test.com",
        name: "Test Admin",
        nickname: nil,
        picture: nil,
        roles: ["admin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user)
        |> put_session(:db_display_name, "Test User")

      {:ok, conn: conn}
    end

    test "leads with the domain screens, then the content ones", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      hrefs =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("#admin-nav a[data-nav-href]")
        |> LazyHTML.attribute("href")

      assert hrefs == ~w(/admin /admin/queue /admin/galls /admin/taxonomy /admin/sources
                         /admin/glossary /admin/articles /admin/keys)
    end

    test "has the profile link and no link to a deleted screen", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#admin-nav a[href='/admin/profile']")
      refute has_element?(view, "#admin-nav a[href='/admin/images']")
    end
  end

  describe "Superadmin dashboard" do
    setup %{conn: conn} do
      user = %Auth0User{
        id: "test-superadmin-id",
        email: "superadmin@test.com",
        name: "Super Admin",
        nickname: nil,
        picture: nil,
        roles: ["superadmin"]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user)
        |> put_session(:db_display_name, "Super Admin")

      {:ok, conn: conn}
    end

    test "shows jobs dashboard in the super admin section", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin")

      assert html =~ "Super Admin"
      assert html =~ "Jobs Dashboard"
      assert has_element?(view, "a[href='/admin/jobs']")
    end
  end

  describe "Admin authentication requirement" do
    test "redirects unauthenticated users", %{conn: conn} do
      # Without session setup, should redirect
      conn = get(conn, ~p"/admin")

      # Should redirect to login or home
      assert redirected_to(conn) =~ "/" or redirected_to(conn) =~ "/auth"
    end
  end
end
