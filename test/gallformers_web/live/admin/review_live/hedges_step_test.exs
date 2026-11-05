defmodule GallformersWeb.Admin.ReviewLive.HedgesStepTest do
  @moduledoc """
  The Hedges step (matter `d213`, Task 21): one page, the statements set
  aside as hedged grouped by what each is about (`subject["topic"]`; none
  under Other), each group with "Leave the rest out (N)", each row naming
  its Gall and the producer's note.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1, test_actor: 0]
  import Gallformers.ImportFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.DoclingFixtures
  alias Gallformers.Import

  @words "It is probably on the black oak, and may also occur on the white oak, perhaps in " <>
           "Texas; the walls are lignified."

  # The fixture document with the hedges' words.
  defp doc do
    words = %{
      "self_ref" => "#/texts/5",
      "label" => "text",
      "content_layer" => "body",
      "text" => @words,
      "prov" => [%{"page_no" => 2, "bbox" => %{}, "charspan" => [0, 0]}],
      "children" => []
    }

    DoclingFixtures.document()
    |> Map.update!("texts", &(&1 ++ [words]))
    |> update_in(["body", "children"], &(&1 ++ [%{"$ref" => "#/texts/5"}]))
  end

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    load_vocab!()
    %{conn: conn}
  end

  setup :audit_test_metadata

  defp hedge(term, topic, note \\ nil) do
    %{
      "term" => term,
      "slot" => "other",
      "gall" => "g1",
      "evidence" => [%{"item" => "#/texts/5", "quote" => term}],
      "note" => note
    }
    |> then(&if(topic, do: Map.put(&1, "topic", topic), else: &1))
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp delivered! do
    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "Galls of the oaks")
      |> put_in(["source", "authors"], ["Ashmead, W. H."])
      |> put_in(["source", "authored"], %{"date" => "1897", "as_written" => "1897"})
      |> Map.put("unmapped", [
        hedge("probably on the black oak", "host", "Hedged Host (\"probably\")."),
        hedge("may also occur on the white oak", "host"),
        hedge("perhaps in Texas", "range"),
        hedge("lignified", nil)
      ])

    package = package(gall: gall, doc: doc()) |> with_review() |> deliver!()
    items = Import.list_queue_items(package, kind: :set_aside_statement)
    by_term = Map.new(items, &{&1.subject["term"], &1})
    %{package: package, items: by_term}
  end

  defp page(conn, package), do: live(conn, ~p"/admin/review/packages/#{package.id}/hedges")

  test "hedges are grouped by what each is about", %{conn: conn} do
    %{package: package, items: items} = delivered!()
    {:ok, view, _html} = page(conn, package)

    assert has_element?(view, "#step-head", "Ashmead 1897 hedges these")

    host = "#section-hedge_host"
    assert has_element?(view, host, "About Hosts")
    assert has_element?(view, host, "Which plants the Gall is on.")
    assert has_element?(view, "#{host} #item-#{items["probably on the black oak"].id}")
    assert has_element?(view, "#{host} #item-#{items["may also occur on the white oak"].id}")

    assert has_element?(view, "#section-hedge_range", "About range")
    assert has_element?(view, "#section-hedge_range #item-#{items["perhaps in Texas"].id}")

    # A hedge with no topic is under Other.
    assert has_element?(view, "#section-hedge_other", "Other")
    assert has_element?(view, "#section-hedge_other #item-#{items["lignified"].id}")

    refute has_element?(view, "#section-hedge_names")
    refute has_element?(view, "#section-set_aside_statements")
  end

  test "each row names its Gall and the producer's note, and recommends leaving it out",
       %{conn: conn} do
    %{package: package, items: items} = delivered!()
    item = items["probably on the black oak"]
    {:ok, view, _html} = page(conn, package)

    row = "#item-#{item.id}-row"
    assert has_element?(view, row, "probably on the black oak")
    assert has_element?(view, row, "the large stem galls. Hedged Host (\"probably\").")
    assert has_element?(view, "#{row} [data-role=answer]", "Leave it out")

    assert has_element?(
             view,
             "#{row} [data-role=answer]",
             "A hedge stays out unless you state it"
           )

    view |> element(row) |> render_click()

    assert has_element?(
             view,
             "#item-#{item.id}-detail [data-role=question]",
             "Should this hedged statement go in as a Fact?"
           )

    assert has_element?(view, "#item-#{item.id}-choices", "State it…")
  end

  test "Leave the rest out decides a group's open hedges as left out", %{conn: conn} do
    %{package: package, items: items} = delivered!()
    black = items["probably on the black oak"]
    white = items["may also occur on the white oak"]

    # One already decided: the rest of the group is the other.
    {:ok, _} = Import.decide_queue_item(test_actor(), black, %{"keep" => true})

    {:ok, view, _html} = page(conn, package)
    assert has_element?(view, "#leave-rest-hedge_host", "Leave the rest out (1)")
    assert has_element?(view, "#leave-rest-hedge_range", "Leave the rest out (1)")

    html = view |> element("#leave-rest-hedge_host") |> render_click()
    assert html =~ "Left 1 hedge out."

    assert Import.get_queue_item!(white.id).decision == %{"keep" => true}
    assert Import.get_queue_item!(items["perhaps in Texas"].id).status == :open
    refute has_element?(view, "#leave-rest-hedge_host")
  end
end
