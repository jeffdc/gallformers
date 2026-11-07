defmodule GallformersWeb.Admin.ReviewLive.UndoTest do
  @moduledoc """
  Undo on a decided question's row (matter `f14c`, "Undo rule"): a decided
  row, opened, offers Undo beside what it was decided as; undoing opens the
  question again and the page loads again. When something since depends on
  the decision, the row says why and links to the record in the taxonomy
  admin, and nothing changes. On a Source's step page and on the
  cross-Source pages alike (`GallformersWeb.Admin.ReviewLive.ItemRow`).

  Not async: packages create Sources and the vocabularies are loaded.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1, test_actor: 0]
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Catalog
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Repo
  alias Gallformers.Taxa

  # Signing in makes the admin the test's actor, so it comes first.
  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    %{conn: conn}
  end

  setup :audit_test_metadata

  defp open_row(view, item), do: view |> element("#item-#{item.id}-row") |> render_click()

  # Another curator's later change to a row, in the audit trail as Carbonite
  # records it: a test runs in one database transaction.
  defp edited_later!(who, table, pk, data) do
    id = System.unique_integer([:positive, :monotonic]) + 3_000_000_000_000
    at = NaiveDateTime.utc_now() |> NaiveDateTime.add(60) |> NaiveDateTime.truncate(:second)

    Repo.query!(
      "INSERT INTO carbonite_default.transactions (id, xact_id, meta, inserted_at) VALUES ($1, $2::xid8, $3, $4)",
      [id, id, %{actor: %{type: "user", id: 99, name: who}, operation: "test.edit"}, at]
    )

    Repo.query!(
      """
      INSERT INTO carbonite_default.changes
        (transaction_id, transaction_xact_id, op, table_prefix, table_name, table_pk, data, changed)
      VALUES ($1, $2::xid8, 'update', 'public', $3, $4, $5, '{}')
      """,
      [id, id, table, [to_string(pk)], data]
    )
  end

  describe "a package's step page" do
    setup do
      load_vocab!()
      quercus = plant_fixture(name: "Quercus", rank: :genus)
      lobata = plant_fixture(name: "Quercus lobata", parent: quercus)

      gall =
        batch()
        |> unique_batch_id()
        |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobatus")

      package = package(gall: gall) |> with_review() |> deliver!()
      host = Enum.find(Import.list_queue_items(package), &(&1.statement_ref == "t2"))
      %{package: package, host: host, lobata: lobata}
    end

    test "Undo opens a decided question again", %{conn: conn} = ctx do
      {:ok, _} =
        Import.decide_queue_item(test_actor(), ctx.host, %{
          "taxon_id" => ctx.lobata.id,
          "add_synonym" => true
        })

      {:ok, view, _html} = live(conn, ~p"/admin/review/packages/#{ctx.package.id}/names")
      open_row(view, ctx.host)
      assert has_element?(view, "#item-#{ctx.host.id}-decided")

      view |> element("#item-#{ctx.host.id}-undo") |> render_click()

      assert render(view) =~ "Decision undone."
      assert %QueueItem{status: :open} = Repo.get!(QueueItem, ctx.host.id)
      assert Taxa.list_synonyms(ctx.lobata) == []
      refute has_element?(view, "#item-#{ctx.host.id}-decided")
    end

    test "a refused Undo says why, and links to the taxonomy admin", %{conn: conn} = ctx do
      {:ok, _} =
        Import.decide_queue_item(test_actor(), ctx.host, %{
          "taxon_id" => ctx.lobata.id,
          "add_synonym" => true
        })

      [synonym] = Taxa.list_synonyms(ctx.lobata)

      edited_later!("Bea Curator", "taxon_names", synonym.id, %{
        "id" => synonym.id,
        "taxon_id" => ctx.lobata.id,
        "name" => "Quercus lobatus"
      })

      {:ok, view, _html} = live(conn, ~p"/admin/review/packages/#{ctx.package.id}/names")
      open_row(view, ctx.host)
      view |> element("#item-#{ctx.host.id}-undo") |> render_click()

      refusal = "#item-#{ctx.host.id}-undo-refusal"
      assert view |> element(refusal) |> render() =~ "was edited by Bea Curator"
      assert has_element?(view, "#{refusal} a[href='/admin/taxonomy/#{ctx.lobata.id}']")
      assert %QueueItem{status: :decided} = Repo.get!(QueueItem, ctx.host.id)
    end
  end

  describe "the rename proposals" do
    test "Undo opens a decided proposal again, its Gall's name put back", %{conn: conn} do
      load_vocab!()
      source = source_fixture("Undowell", "1961")
      genus = taxon_fixture(rank: :genus, name: "Undometa", kingdom: "Animalia")
      species = taxon_fixture(name: "Undometa alba", parent: genus, kingdom: "Animalia")
      gall = gall_fixture(name: "Undometa alba (agamic)", generation: "agamic")

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: species.id, object_gall_id: gall.id},
          confirm(source)
        )

      {:ok, _} = Taxa.rename(test_actor(), species, "Undometa nigra")
      [item] = Enum.filter(Import.list_gall_renames(), &(&1.subject["gall_id"] == gall.id))
      {:ok, _} = Import.decide_queue_item(test_actor(), item, %{"accept" => true})

      {:ok, view, _html} = live(conn, ~p"/admin/review/renames")
      view |> element("#show-decided") |> render_click()
      open_row(view, item)
      view |> element("#item-#{item.id}-undo") |> render_click()

      assert render(view) =~ "Decision undone."
      assert %QueueItem{status: :open} = Repo.get!(QueueItem, item.id)
      assert Catalog.get_gall!(gall.id).name == "Undometa alba (agamic)"
    end
  end
end
