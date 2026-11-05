defmodule GallformersWeb.Admin.ReviewLive.TitlesTest do
  @moduledoc """
  Each review page names itself once: in the admin layout's title bar, as
  every admin page does, not again in a heading of its own.

  Not async: packages create Sources (unique titles).
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.DataCase, only: [audit_test_metadata: 1]
  import Gallformers.ImportFixtures
  import GallformersWeb.AdminLiveHelpers

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    %{conn: conn}
  end

  setup :audit_test_metadata

  defp awaiting! do
    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "Galls of the oaks")
      |> put_in(["source", "authors"], ["Ashmead, W. H."])
      |> put_in(["source", "authored"], %{"date" => "1897", "as_written" => "1897"})

    package(gall: gall) |> with_review() |> deliver!()
  end

  defp headings(html),
    do: html |> LazyHTML.from_document() |> LazyHTML.query("h1") |> Enum.count()

  test "the Sources to review", %{conn: conn} do
    awaiting!()
    {:ok, _view, html} = live(conn, ~p"/admin/review")
    assert headings(html) == 1
  end

  test "a Source's overview and its step pages", %{conn: conn} do
    package = awaiting!()

    {:ok, _view, html} = live(conn, ~p"/admin/review/packages/#{package.id}")
    assert headings(html) == 1

    {:ok, _view, html} = live(conn, ~p"/admin/review/packages/#{package.id}/names")
    assert headings(html) == 1
  end

  test "the Gall rename proposals", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/review/renames")
    assert headings(html) == 1
  end
end
