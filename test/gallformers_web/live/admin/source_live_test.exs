defmodule GallformersWeb.Admin.SourceLiveTest do
  @moduledoc """
  The Source editor (matter a856, Task 10): `/admin/sources` lists and
  searches the Sources, paginated; `/admin/sources/:id` edits a Source's
  details with today's rules, retracts it (the notice picked from the
  Sources, a date) and undoes a retraction, each through
  `Gallformers.Import.record_source_edit/2` as the signed-in admin. There is
  no delete.

  The audit trail records one actor per database transaction and a test
  runs in one, so the fixtures that write audited tables write as the
  signed-in admin too.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  import Ecto.Query, only: [from: 2]
  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [test_audit_changes: 0]
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Audit.Actor
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Repo
  alias Gallformers.Sources

  setup %{conn: conn} do
    {conn, user} = log_in_admin(conn, "Sam Sources")
    %{conn: conn, actor: Actor.user(user.id, "Sam Sources")}
  end

  defp fact_supported_by(actor, source) do
    {:ok, fact} = Facts.create_fact(actor, %{kind: "trait"})
    {:ok, _} = Facts.attribute(actor, confirm(source, %{fact_id: fact.id}))
    fact
  end

  defp standing(fact), do: Facts.get_fact!(fact.id).standing

  defp source_edits, do: for(e <- Import.list_replay_entries(), e.kind == :source_edit, do: e)

  describe "the list" do
    test "searches the Sources by title or author and links each to its editor", %{conn: conn} do
      source = source_fixture("Zzyzx cynipid survey", "1957")

      {:ok, view, _html} = live(conn, ~p"/admin/sources")

      html = view |> form("#source-search-form", %{query: "zzyzx"}) |> render_change()

      assert html =~ "Zzyzx cynipid survey"
      assert has_element?(view, "a[href='/admin/sources/#{source.id}']")
      refute has_element?(view, "a[href^='/admin/sources/new']")
    end

    test "pages through the results", %{conn: conn} do
      prefix = "Paged #{System.unique_integer([:positive])}"

      for n <- 1..26,
          do: source_fixture("#{prefix} #{String.pad_leading("#{n}", 2, "0")}", "1990")

      {:ok, view, _html} = live(conn, ~p"/admin/sources")
      view |> form("#source-search-form", %{query: prefix}) |> render_change()

      assert has_element?(view, "#sources-table", "#{prefix} 01")
      refute has_element?(view, "#sources-table", "#{prefix} 26")

      view |> element("nav[aria-label='Pagination'] button", "Next") |> render_click()

      assert has_element?(view, "#sources-table", "#{prefix} 26")
      refute has_element?(view, "#sources-table", "#{prefix} 01")
    end

    test "marks a retracted Source", %{conn: conn, actor: actor} do
      source = source_fixture("Yyzzx retracted", "2019")
      notice = source_fixture("Yyzzx notice", "2021")
      {:ok, _} = Import.record_source_edit(actor, {:retract, source, notice, ~D[2021-06-01]})

      {:ok, view, _html} = live(conn, ~p"/admin/sources")
      view |> form("#source-search-form", %{query: "yyzzx"}) |> render_change()

      assert has_element?(view, "#source-#{source.id}", "Retracted")
      refute has_element?(view, "#source-#{notice.id}", "Retracted")
    end
  end

  describe "editing the details" do
    test "saves today's columns and the new fields as the signed-in admin", %{conn: conn} do
      source = source_fixture("Editable source", "1957")

      {:ok, view, html} = live(conn, ~p"/admin/sources/#{source.id}")
      assert html =~ source.title
      refute has_element?(view, "button", "Delete")

      view
      |> form("#source-form",
        source: %{
          title: "Edited source",
          pubyear: "1958",
          kind: "publication",
          authors: "Weld, L. H.\nKinsey, A. C.\n",
          authored: "1958-04",
          doi: "10.1000/edited"
        }
      )
      |> render_submit()

      assert render(view) =~ "Source saved"

      updated = Sources.get_source!(source.id)
      assert updated.title == "Edited source"
      assert updated.pubyear == "1958"
      assert updated.authors == ["Weld, L. H.", "Kinsey, A. C."]
      assert updated.authored_date == ~D[1958-04-01]
      assert updated.doi == "10.1000/edited"

      assert [%{key: %{"op" => "update_details"}}] = source_edits()

      assert [%{transaction: %{meta: %{"actor" => %{"name" => "Sam Sources"}}}}] =
               Repo.all(
                 from(c in test_audit_changes(),
                   where: c.table_name == "replay_log",
                   preload: :transaction
                 )
               )
    end

    test "shows today's validation and saves nothing while it fails", %{conn: conn} do
      source = source_fixture("Validated source", "1957")
      {:ok, view, _html} = live(conn, ~p"/admin/sources/#{source.id}")

      html =
        view
        |> form("#source-form", source: %{title: "", pubyear: "57", link: "nope"})
        |> render_change()

      assert html =~ "can&#39;t be blank"
      assert html =~ "must be a valid 4-digit year"
      assert html =~ "must be a valid URL"

      view
      |> form("#source-form", source: %{title: "", pubyear: "57"})
      |> render_submit()

      assert Sources.get_source!(source.id).title == source.title
      assert source_edits() == []
    end

    test "a read-only license shows its canonical link", %{conn: conn} do
      source = source_fixture("Licensed source", "1957")
      {:ok, view, _html} = live(conn, ~p"/admin/sources/#{source.id}")

      view |> form("#source-form", source: %{license: "CC-BY"}) |> render_change()

      assert has_element?(
               view,
               "#source-form input[readonly][value='https://creativecommons.org/licenses/by/4.0/']"
             )
    end
  end

  describe "retracting" do
    test "picks the notice, takes a date and recomputes the standings", %{
      conn: conn,
      actor: actor
    } do
      source = source_fixture("Fabricated results", "2019")
      notice = source_fixture("Qqxv retraction notice", "2021")
      fact = fact_supported_by(actor, source)

      {:ok, view, _html} = live(conn, ~p"/admin/sources/#{source.id}")
      refute has_element?(view, "#retraction", "Retracted by")

      render_hook(view, "search_notice", %{"value" => "qqxv"})
      view |> element("#notice-picker-results button", notice.title) |> render_click()

      view
      |> form("#retract-form", retract: %{retracted_on: "2021-06-01"})
      |> render_submit()

      assert has_element?(view, "#retraction", "Retracted by")
      assert has_element?(view, "#retraction a[href='/admin/sources/#{notice.id}']")

      updated = Sources.get_source!(source.id)
      assert updated.retracted_by_id == notice.id
      assert updated.retracted_on == ~D[2021-06-01]
      assert standing(fact) == :retracted
      assert [%{key: %{"op" => "retract"}}] = source_edits()
    end

    test "needs a notice and a date", %{conn: conn} do
      source = source_fixture("Not yet retracted", "2019")
      {:ok, view, _html} = live(conn, ~p"/admin/sources/#{source.id}")

      html =
        view
        |> form("#retract-form", retract: %{retracted_on: "2021-06-01"})
        |> render_submit()

      assert html =~ "Pick the retraction notice"
      assert Sources.get_source!(source.id).retracted_by_id == nil
    end

    test "un-retracting restores the standings", %{conn: conn, actor: actor} do
      source = source_fixture("Retracted by mistake", "2019")
      notice = source_fixture("Mistaken notice", "2021")
      fact = fact_supported_by(actor, source)
      {:ok, _} = Import.record_source_edit(actor, {:retract, source, notice, ~D[2021-06-01]})
      assert standing(fact) == :retracted

      {:ok, view, _html} = live(conn, ~p"/admin/sources/#{source.id}")
      view |> element("#unretract-button") |> render_click()

      assert render(view) =~ "Retraction undone"
      assert Sources.get_source!(source.id).retracted_by_id == nil
      assert standing(fact) == :current
      refute has_element?(view, "#unretract-button")
    end
  end

  test "an unknown Source goes back to the list", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/admin/sources"}}} =
             live(conn, ~p"/admin/sources/999999999")
  end
end
