defmodule GallformersWeb.Admin.ReviewLive.GallsStepTest do
  @moduledoc """
  The Galls step (matter `d213`, Task 19): Galls of named species and
  Undescribed Galls; each candidate Gall compared side by side with what
  the Source says; another generation's Gall created with its generation
  chosen.

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
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Repo

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    %{conn: conn}
  end

  setup :audit_test_metadata

  setup do
    load_vocab!()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    nigra = plant_fixture(name: "Quercus nigra", parent: quercus)
    marilandica = plant_fixture(name: "Quercus marilandica", parent: quercus)
    andricus = taxon_fixture(name: "Andricus", rank: :genus, kingdom: "Animalia")
    wasp = taxon_fixture(name: "Andricus quercuscalifornicus", parent: andricus)
    taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")
    legacy = source_fixture("Legacy", "1990")

    %{quercus: quercus, nigra: nigra, marilandica: marilandica, wasp: wasp, legacy: legacy}
  end

  # A Gall of the wasp, on `host` when given.
  defp wasp_gall!(ctx, name, opts) do
    gall = gall_fixture(Keyword.merge([name: name], Keyword.take(opts, [:generation])))

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: ctx.wasp.id, object_gall_id: gall.id},
        confirm(ctx.legacy)
      )

    if host = opts[:host] do
      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "host_of", subject_taxon_id: host.id, object_gall_id: gall.id},
          confirm(ctx.legacy)
        )
    end

    gall
  end

  # The fixture gall batch by Osten Sacken 1862: its Gall, of no
  # generation, on Quercus nigra, or on `host` (`{name, rank}`).
  defp deliver!, do: deliver_on!({"Quercus nigra", "species"})

  defp deliver_on!({name, rank}) do
    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "On the Cynipidae of the North American Oaks")
      |> put_in(["source", "authors"], ["Osten Sacken, C. R."])
      |> put_in(["source", "authored"], %{"date" => "1862", "as_written" => "1862"})
      |> put_in(["taxa", Access.at(1)], %{
        "ref" => "t2",
        "name_as_written" => name,
        "rank" => rank
      })
      |> update_in(["galls", Access.at(0), "identified_by"], &Map.delete(&1, "generation"))

    package(gall: gall) |> with_review() |> deliver!()
  end

  defp gall_item(package),
    do: Enum.find(Import.list_queue_items(package), &(&1.statement_ref == "g1"))

  defp step(conn, package), do: live(conn, ~p"/admin/review/packages/#{package.id}/galls")

  defp open_row(view, item), do: view |> element("#item-#{item.id}-row") |> render_click()

  defp choose(view, item, label) do
    id =
      view
      |> element("#item-#{item.id}-choices label", label)
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("input")
      |> LazyHTML.attribute("id")
      |> List.first()

    view |> element("##{id}") |> render_click()
  end

  # Two Galls of the wasp, both on another Host than the Source's: neither
  # is told apart, and the Source disagrees with both on the Host.
  defp two_galls!(ctx) do
    stem = wasp_gall!(ctx, "Andricus quercuscalifornicus stem gall", host: ctx.marilandica)
    elsewhere = wasp_gall!(ctx, "Andricus quercuscalifornicus bud gall", host: ctx.marilandica)
    {stem, elsewhere}
  end

  test "a Gall of a named species is asked in its section, each candidate compared",
       %{conn: conn} = ctx do
    {on_nigra, elsewhere} = two_galls!(ctx)
    package = deliver!()
    assert %QueueItem{kind: :ambiguous_match} = item = gall_item(package)

    {:ok, view, _html} = step(conn, package)
    assert has_element?(view, "#section-named_galls h2", "Galls of named species")
    assert has_element?(view, "#section-named_galls #item-#{item.id}", "On Quercus nigra")

    open_row(view, item)

    assert has_element?(
             view,
             "#item-#{item.id}-detail [data-role=question]",
             "Which Gall does Osten Sacken 1862 mean by “the large stem galls”?"
           )

    choices = "#item-#{item.id}-choices"
    assert has_element?(view, "#{choices} [data-role=gall-comparison] th", "Osten Sacken 1862")
    assert has_element?(view, "#{choices} [data-role=gall-comparison] th", on_nigra.name)

    assert has_element?(
             view,
             "#{choices} [data-role=gall-comparison] tr[data-mark=differ]",
             "Quercus nigra"
           )

    assert has_element?(
             view,
             "#{choices} [data-role=gall-comparison] tr[data-mark=differ]",
             "Quercus marilandica"
           )

    assert has_element?(
             view,
             "#{choices} [data-role=gall-meta] a[href='/gall/#{elsewhere.id}?edit']",
             "Open ↗"
           )
  end

  test "a conflict is tagged, and the row says to check", %{conn: conn} = ctx do
    {on_nigra, elsewhere} = two_galls!(ctx)
    package = deliver!()
    item = gall_item(package)

    fields = %{
      "host" => "differ",
      "where" => "conflict",
      "detachable" => "none",
      "generation" => "none",
      "form" => "none"
    }

    comparisons =
      for id <- [on_nigra.id, elsewhere.id],
          do: %{"gall_id" => id, "agrees" => 0, "conflicts" => ["where"], "fields" => fields}

    item
    |> Ecto.Changeset.change(
      proposal: %{"candidate_ids" => [on_nigra.id, elsewhere.id], "comparisons" => comparisons}
    )
    |> Repo.update!()

    {:ok, view, _html} = step(conn, package)

    assert has_element?(
             view,
             "#item-#{item.id}-row [data-role=answer]",
             "Check: both Galls conflict with what Osten Sacken 1862 says"
           )

    open_row(view, item)

    assert has_element?(
             view,
             "#item-#{item.id}-choices [data-role=tag-conflict]",
             "Conflicts: where on the plant"
           )

    assert has_element?(view, "#item-#{item.id}-choices tr[data-mark=conflict]")
  end

  test "another generation's Gall is created with its generation chosen", %{conn: conn} = ctx do
    wasp_gall!(ctx, "Andricus quercuscalifornicus (sexual)", generation: "sexual")
    wasp_gall!(ctx, "Andricus quercuscalifornicus twig gall", generation: "sexual")
    package = deliver!()
    item = gall_item(package)
    {:ok, view, _html} = step(conn, package)
    open_row(view, item)

    choose(view, item, "It's another generation: add a new Gall")
    picker = "#item-#{item.id}-picker"
    assert has_element?(view, "#{picker} option[value=sexual][disabled]")
    assert has_element?(view, "#{picker} option[value=agamic]")
    refute has_element?(view, "#{picker} option[value=agamic][disabled]")
    assert has_element?(view, "#item-#{item.id}-effect", "Choose its generation.")

    view |> form(picker, %{"value" => "agamic"}) |> render_change()
    refute has_element?(view, "#item-#{item.id}-decide[disabled]")

    assert has_element?(
             view,
             "#item-#{item.id}-effect",
             "It is created as the agamic generation."
           )

    view |> element("#item-#{item.id}-decide") |> render_click()
    assert render(view) =~ "Decision recorded."
    assert Import.get_queue_item!(item.id).decision == %{"new" => true, "generation" => "agamic"}

    assert has_element?(
             view,
             "#item-#{item.id}-row [data-role=answer]",
             "Created as the agamic generation's Gall"
           )
  end
end
