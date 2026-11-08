defmodule GallformersWeb.Admin.ReviewLive.QuestionCardTest do
  @moduledoc """
  A question's card in the one-at-a-time review (matter `6611`, Task 7):
  a Gall question's candidates, each with its comparison in a sentence and
  the side-by-side behind "Compare".

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

  defp review(conn, package, query),
    do: live(conn, "/admin/review/packages/#{package.id}#{query}")

  # Two Galls of the wasp, both on another Host than the Source's: neither
  # is told apart, and the Source disagrees with both on the Host.
  defp two_galls!(ctx) do
    stem = wasp_gall!(ctx, "Andricus quercuscalifornicus stem gall", host: ctx.marilandica)
    elsewhere = wasp_gall!(ctx, "Andricus quercuscalifornicus bud gall", host: ctx.marilandica)
    {stem, elsewhere}
  end

  test "each candidate Gall says how it compares, the side-by-side behind Compare",
       %{conn: conn} = ctx do
    {stem, _bud} = two_galls!(ctx)
    package = deliver!()
    assert %QueueItem{kind: :ambiguous_match} = item = gall_item(package)

    {:ok, view, _html} = review(conn, package, "?stage=galls")
    card = "#q-#{item.id}"

    assert has_element?(view, "#{card} h2", "Which Gall does Osten Sacken 1862 mean by")
    assert has_element?(view, "#{card} [data-role=summary]", "Differs on Host")
    assert has_element?(view, "#{card} details summary", "Compare")
    assert has_element?(view, "#{card} details [data-role=gall-comparison] th", stem.name)
  end

  test "another generation's Gall: Choose… opens the generations, the held ones disabled",
       %{conn: conn} = ctx do
    wasp_gall!(ctx, "Andricus quercuscalifornicus (sexual)", generation: "sexual")
    wasp_gall!(ctx, "Andricus quercuscalifornicus twig gall", generation: "sexual")
    package = deliver!()
    item = gall_item(package)
    {:ok, view, _html} = review(conn, package, "?stage=galls")
    card = "#q-#{item.id}"

    option =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#{card} [id^='q-#{item.id}-c']")
      |> Enum.filter(&(&1 |> LazyHTML.attribute("id") |> hd() |> String.match?(~r/-c\d+$/)))
      |> Enum.find(&(LazyHTML.text(&1) =~ "It's another generation"))

    [choice] = option |> LazyHTML.query("button") |> LazyHTML.attribute("phx-value-choice")
    button = "#{card} button[phx-value-choice='#{choice}']"
    assert has_element?(view, button, "Choose…")

    view |> element(button) |> render_click()
    picker = "#{card} [data-role=follow] form"
    assert has_element?(view, "#{picker} option[value=sexual][disabled]")
    assert has_element?(view, "#{card} [data-role=effect]", "Choose its generation.")

    view |> form(picker, %{"value" => "agamic"}) |> render_change()
    assert has_element?(view, "#{card} [data-role=effect]", "agamic generation")

    view |> element("#{card} button[phx-click=decide]") |> render_click()
    decided = Import.get_queue_item!(item.id)
    assert decided.status == :decided
    assert decided.decision["generation"] == "agamic"
  end

  describe "a dispute about a Trait term" do
    @words "The galls are ovoid and globular, attached by a small point."

    defp shape_doc do
      words = %{
        "self_ref" => "#/texts/5",
        "label" => "text",
        "content_layer" => "body",
        "text" => @words,
        "prov" => [%{"page_no" => 2, "bbox" => %{}, "charspan" => [0, 0]}],
        "children" => []
      }

      Gallformers.DoclingFixtures.document()
      |> Map.update!("texts", &(&1 ++ [words]))
      |> update_in(["body", "children"], &(&1 ++ [%{"$ref" => "#/texts/5"}]))
    end

    # The producer placed "globular" under globular; a checker disputes it.
    defp shape_dispute! do
      shape = %{
        "id" => "f6",
        "stance" => "confirm",
        "kind" => "trait",
        "gall" => "g1",
        "trait" => "shape",
        "term" => "globular",
        "category" => %{"value" => "globular"},
        "evidence" => [%{"item" => "#/texts/5", "quote" => "globular"}]
      }

      finding = %{
        "batch" => "gall.json",
        "id" => "f6",
        "problem" => "unsupported",
        "reason" => "the quote does not say so",
        "response" => %{"decision" => "disagree", "reason" => "it does"}
      }

      gall =
        batch()
        |> unique_batch_id()
        |> Map.put("format_version", 4)
        |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
        |> Map.update!("facts", &(&1 ++ [shape]))

      package =
        package(gall: gall, doc: shape_doc())
        |> with_review([finding], responded: true)
        |> deliver!()

      [dispute] = Import.list_queue_items(package, kind: :dispute)
      {package, dispute}
    end

    defp map_to(view, card, values) do
      view |> element("#{card}-f6-values") |> render_click()
      for v <- values, do: view |> element("#{card}-f6-list-#{v}") |> render_click()
      view |> element("#{card} button[phx-click=trait_save]") |> render_click()
    end

    test "values other than the producer's are decided as those values", %{conn: conn} do
      {package, dispute} = shape_dispute!()
      {:ok, view, _html} = review(conn, package, "?stage=traits")
      card = "#q-#{dispute.id}"

      assert has_element?(view, "#{card} [data-role=pipeline]", "The producer mapped")
      map_to(view, card, ["globular", "spindle"])

      assert Import.get_queue_item!(dispute.id).decision == %{"values" => ["globular", "spindle"]}
    end

    test "exactly the producer's values keep it as the producer placed it", %{conn: conn} do
      {package, dispute} = shape_dispute!()
      {:ok, view, _html} = review(conn, package, "?stage=traits")
      map_to(view, "#q-#{dispute.id}", ["globular"])

      assert Import.get_queue_item!(dispute.id).decision == %{"keep" => true}
    end
  end
end
