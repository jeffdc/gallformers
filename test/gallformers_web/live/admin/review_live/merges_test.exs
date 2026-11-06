defmodule GallformersWeb.Admin.ReviewLive.MergesTest do
  @moduledoc """
  The questions merges leave (`/admin/review/merges`, matter `ec2c`,
  "Deletes and merges: back end as built"): a merge that brings two
  Sources of the same date into disagreement on one Fact queues a
  `:same_date_conflict` of no package, so of no Source. Like the Gall
  rename proposals, they have a page of their own, which the Sources list
  leads to while any is open; each is acknowledged in place.

  Not async: the Catalog vocabularies are loaded.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1, test_actor: 0]
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Catalog
  alias Gallformers.Import

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    %{conn: conn}
  end

  setup :audit_test_metadata

  defp trait!(gall, value, source) do
    {:ok, _} =
      Catalog.assert_trait(
        test_actor(),
        %{gall_id: gall.id, trait: "detachable", value: value},
        confirm(source)
      )
  end

  # Two Galls whose same-date Sources disagree, merged.
  defp conflict! do
    load_vocab!()
    survivor = gall_fixture(name: "Andricus survivus gall")
    absorbed = gall_fixture(name: "Andricus absorbus gall")
    trait!(survivor, "integral", source_fixture("Other", "1959"))
    trait!(absorbed, "detachable", source_fixture("Weld", "1959"))

    {:ok, %{queued: [item_id]}} =
      Import.record_merge(test_actor(), {:gall, absorbed.id, survivor.id})

    %{item: Import.get_queue_item!(item_id), survivor: survivor}
  end

  describe "the Sources list" do
    test "has a row for the open merge questions, leading to their page", %{conn: conn} do
      conflict!()

      {:ok, view, _html} = live(conn, ~p"/admin/review")

      assert has_element?(view, "#merge-conflicts", "Questions from merges")
      assert has_element?(view, "#merge-conflicts [data-role=to-decide]", "1")

      assert {:error, {:live_redirect, %{to: "/admin/review/merges"}}} =
               view |> element("#merge-conflicts a", "Questions from merges") |> render_click()
    end

    test "has no such row when none is open", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/review?filter=all")
      refute has_element?(view, "#merge-conflicts")
    end
  end

  describe "the page" do
    test "lists each question with the merge that raised it", %{conn: conn} do
      %{item: item} = conflict!()

      {:ok, view, html} = live(conn, ~p"/admin/review/merges")

      assert html =~ "Questions from merges"
      assert has_element?(view, "#section-same_date #item-#{item.id}")
      assert has_element?(view, "#item-#{item.id}", "Andricus survivus gall")
    end

    test "acknowledging one takes it off the list", %{conn: conn} do
      %{item: item} = conflict!()
      {:ok, view, _html} = live(conn, ~p"/admin/review/merges")

      view |> element("#item-#{item.id}-row") |> render_click()
      view |> element("#item-#{item.id}-choice-0") |> render_click()
      view |> element("#item-#{item.id}-decide") |> render_click()

      assert Import.get_queue_item!(item.id).status != :open
      refute has_element?(view, "#item-#{item.id}")
      assert has_element?(view, "#review-sections", "No question from a merge is waiting.")
    end

    test "is empty when no merge left a question", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/review/merges")
      assert html =~ "No question from a merge is waiting."
    end
  end
end
