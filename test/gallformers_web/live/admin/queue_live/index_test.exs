defmodule GallformersWeb.Admin.QueueLive.IndexTest do
  @moduledoc """
  The review queue (`/admin/queue`, matter a856 Task 3): the open queue
  items of every package and the rename proposals, by kind with counts;
  packages by status; and the decisions on rename proposals, which belong
  to no package.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1, test_actor: 0]
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Repo
  alias Gallformers.Taxa

  # Signing in makes the admin the test's actor, so it comes first.
  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Quinn Queue")
    %{conn: conn}
  end

  setup :audit_test_metadata

  # A delivered package awaiting review: "Q. lobata" names no plant here, so
  # it has an open :unresolved_host item.
  defp awaiting! do
    package(gall: unique_batch_id(batch())) |> with_review() |> deliver!()
  end

  defp rename_item!(gall, from, to, collision \\ false) do
    %QueueItem{}
    |> QueueItem.create_changeset(%{
      kind: :gall_rename,
      subject: %{"gall_id" => gall.id},
      proposal: %{"gall_id" => gall.id, "from" => from, "to" => to, "collision" => collision},
      reason: "#{from} was renamed."
    })
    |> Repo.insert!()
  end

  describe "open items" do
    test "lists the open items of every package with counts by kind", %{conn: conn} do
      package = awaiting!()
      rename = rename_item!(gall_fixture(), "Alpha gall", "Beta gall")
      [host | _] = Import.list_queue_items(package, kind: :unresolved_host)

      {:ok, view, html} = live(conn, ~p"/admin/queue")

      assert html =~ "Review queue"
      assert has_element?(view, "#queue-item-#{host.id}")
      assert has_element?(view, "#queue-item-#{rename.id}")

      assert has_element?(view, "#kind-filter-unresolved_host", "Unresolved Host")
      assert has_element?(view, "#kind-filter-gall_rename", "(1)")

      # An item of a package links to the package's page.
      assert has_element?(
               view,
               "#queue-item-#{host.id} a[href='/admin/queue/packages/#{package.id}']"
             )
    end

    test "filters by kind", %{conn: conn} do
      package = awaiting!()
      rename = rename_item!(gall_fixture(), "Alpha gall", "Beta gall")
      [host | _] = Import.list_queue_items(package, kind: :unresolved_host)

      {:ok, view, _html} = live(conn, ~p"/admin/queue")

      view |> element("#kind-filter-gall_rename") |> render_click()
      assert_patch(view, ~p"/admin/queue?kind=gall_rename")

      assert has_element?(view, "#queue-item-#{rename.id}")
      refute has_element?(view, "#queue-item-#{host.id}")

      {:ok, view, _html} = live(conn, ~p"/admin/queue?kind=unresolved_host")
      assert has_element?(view, "#queue-item-#{host.id}")
      refute has_element?(view, "#queue-item-#{rename.id}")
    end

    test "an unknown kind shows every open item", %{conn: conn} do
      rename = rename_item!(gall_fixture(), "Alpha gall", "Beta gall")

      {:ok, view, _html} = live(conn, ~p"/admin/queue?kind=nonsense")
      assert has_element?(view, "#queue-item-#{rename.id}")
    end

    test "says so when nothing is open", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/queue")
      assert has_element?(view, "#open-items", "Nothing is waiting")
    end
  end

  describe "rename proposals" do
    setup do
      load_vocab!()
      source = source_fixture("Queuewell", "1961")
      genus = taxon_fixture(rank: :genus, name: "Queueta", kingdom: "Animalia")
      species = taxon_fixture(name: "Queueta alba", parent: genus, kingdom: "Animalia")
      gall = gall_fixture(name: "Queueta alba (agamic)", generation: "agamic")

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: species.id, object_gall_id: gall.id},
          confirm(source)
        )

      {:ok, _} = Taxa.rename(test_actor(), species, "Queueta nigra")
      [item] = Enum.filter(Import.list_gall_renames(), &(&1.subject["gall_id"] == gall.id))
      %{gall: gall, item: item}
    end

    test "show the Gall's name from and to", %{conn: conn, item: item} do
      {:ok, view, _html} = live(conn, ~p"/admin/queue?kind=gall_rename")

      assert has_element?(view, "#queue-item-#{item.id}", "Queueta alba (agamic)")
      assert has_element?(view, "#queue-item-#{item.id}", "Queueta nigra (agamic)")
      refute has_element?(view, "#queue-item-#{item.id} #collision-#{item.id}")
    end

    test "accepting renames the Gall", %{conn: conn, item: item, gall: gall} do
      {:ok, view, _html} = live(conn, ~p"/admin/queue?kind=gall_rename")

      view |> form("#decide-#{item.id}") |> render_submit(%{"choice" => "accept"})

      assert %QueueItem{status: :decided, decision: %{"accept" => true}} =
               decided = Import.get_queue_item!(item.id)

      assert decided.decided_by_name == "Quinn Queue"
      assert Catalog.get_gall!(gall.id).name == "Queueta nigra (agamic)"
      refute has_element?(view, "#decide-#{item.id}")
      assert render(view) =~ "Decided"
    end

    test "rejecting keeps the Gall's name", %{conn: conn, item: item, gall: gall} do
      {:ok, view, _html} = live(conn, ~p"/admin/queue?kind=gall_rename")

      view
      |> form("#decide-#{item.id}", decision: %{note: "The old name is the one in use."})
      |> render_submit(%{"choice" => "reject"})

      assert %QueueItem{decision: decision} = Import.get_queue_item!(item.id)
      assert decision == %{"reject" => true, "note" => "The old name is the one in use."}
      assert Gall.display_name(Catalog.get_gall!(gall.id)) == "Queueta alba (agamic)"
      assert render(view) =~ "rename rejected"
    end

    test "a colliding name is flagged, and accepting it is refused with the reason",
         %{conn: conn, item: item, gall: gall} do
      other = gall_fixture(name: "Queueta other")

      {:ok, _} =
        Catalog.update_name_parts(test_actor(), other, %{name_override: "Queueta nigra (agamic)"})

      flagged = rename_item!(gall_fixture(), "Some gall", "Queueta nigra (agamic)", true)

      {:ok, view, _html} = live(conn, ~p"/admin/queue?kind=gall_rename")

      assert has_element?(view, "#collision-#{flagged.id}")

      html = view |> form("#decide-#{item.id}") |> render_submit(%{"choice" => "accept"})

      assert html =~ "another Gall"
      assert Import.get_queue_item!(item.id).status == :open
      assert Catalog.get_gall!(gall.id).name == "Queueta alba (agamic)"
    end
  end

  describe "packages" do
    test "lists packages newest first and filters by status", %{conn: conn} do
      {:ok, received} =
        Import.register_package(
          test_actor(),
          "pkg-received-#{System.unique_integer([:positive])}"
        )

      {:ok, other} =
        Import.register_package(test_actor(), "pkg-denied-#{System.unique_integer([:positive])}")

      {:ok, denied} = Import.deny_package(test_actor(), other, "Not a gall paper.")

      {:ok, view, _html} = live(conn, ~p"/admin/queue")

      assert has_element?(view, "#packages #package-#{received.id}", received.key)
      assert has_element?(view, "#packages #package-#{denied.id}", "Denied")

      assert has_element?(
               view,
               "#package-#{received.id} a[href='/admin/queue/packages/#{received.id}']"
             )

      view |> form("#package-status-form", %{status: "denied"}) |> render_change()
      assert_patch(view, ~p"/admin/queue?status=denied")

      assert has_element?(view, "#packages #package-#{denied.id}")
      refute has_element?(view, "#packages #package-#{received.id}")
    end

    test "pages the packages", %{conn: conn} do
      packages =
        for n <- 1..21 do
          {:ok, p} =
            Import.register_package(
              test_actor(),
              "pkg-page-#{n}-#{System.unique_integer([:positive])}"
            )

          p
        end

      oldest = hd(packages)
      newest = List.last(packages)

      {:ok, view, _html} = live(conn, ~p"/admin/queue")
      assert has_element?(view, "#package-#{newest.id}")
      refute has_element?(view, "#package-#{oldest.id}")

      {:ok, view, _html} = live(conn, ~p"/admin/queue?packages_page=2")
      assert has_element?(view, "#package-#{oldest.id}")
      refute has_element?(view, "#package-#{newest.id}")
    end
  end
end
