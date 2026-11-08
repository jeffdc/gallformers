defmodule GallformersWeb.Admin.ReviewLive.TraitTermsTest do
  @moduledoc """
  The "Trait terms to settle" section of a Source's Traits step (matter
  `d213`, Task D; the step and question layout of Tasks 15 and 16): one
  row per term the readers didn't place alike, opening onto the first
  Gall's quote, the categories in play with their definitions, the
  choices (place the term for every Source, a category per Gall, no
  category, or keep it as text), and behind a disclosure each Gall it
  covers with what the producer suggested and what the checker placed. It
  holds nothing.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1, test_actor: 0]
  import Gallformers.ImportFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Catalog
  alias Gallformers.DoclingFixtures
  alias Gallformers.Import

  # A batch-local ref (t24, g1, f5, a2) as a word.
  @ref ~r/\b[tgfa]\d+\b/

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    load_vocab!()
    %{conn: conn}
  end

  setup :audit_test_metadata

  @words "The galls are pale tan, rough; the bud galls pale tan and lumpy."

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

  defp trait(id, gall, quote) do
    %{
      "id" => id,
      "stance" => "confirm",
      "kind" => "trait",
      "gall" => gall,
      "trait" => "color",
      "term" => "pale tan",
      "category" => %{"value" => "tan"},
      "evidence" => [%{"item" => "#/texts/5", "quote" => quote}]
    }
  end

  # g1 and g2 with the color term "pale tan": the producer says tan for
  # both; the checker white for g1 (with its reason) and tan for g2.
  defp delivered!(placements \\ nil, findings \\ []) do
    gall =
      batch()
      |> unique_batch_id()
      |> Map.put("format_version", 4)
      |> put_in(["source", "title"], "Galls of the oaks")
      |> put_in(["source", "authors"], ["Ashmead, W. H."])
      |> Map.update!("galls", fn galls ->
        galls ++
          [
            %{
              "ref" => "g2",
              "name_as_written" => "the small bud galls",
              "new" => true,
              "identified_by" => %{"inducer" => "t1"}
            }
          ]
      end)
      |> Map.update!("facts", fn facts ->
        facts ++
          [
            %{
              "id" => "f5",
              "stance" => "confirm",
              "kind" => "relationship",
              "type" => "inducer_of",
              "subject" => "t1",
              "object" => "g2",
              "evidence" => [%{"item" => "#/texts/1", "quote" => "Andricus quercuscalifornicus"}]
            },
            trait("f6", "g1", "pale tan, rough"),
            trait("f7", "g2", "pale tan and lumpy")
          ]
      end)

    placements =
      placements ||
        [
          %{"id" => "f6", "category" => %{"value" => "white"}, "reason" => "pale reads as white"},
          %{"id" => "f7", "category" => %{"value" => "tan"}}
        ]

    package =
      package(gall: gall, doc: doc())
      |> with_review(findings, placements: placements, responded: true)
      |> deliver!()

    [item] = Import.list_queue_items(package, kind: :trait_term)
    %{package: package, item: item}
  end

  defp page(conn, package), do: live(conn, ~p"/admin/review/packages/#{package.id}/traits")

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

  defp visible_text(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.text()

  # The same package, read by two checkers: the producer and checker 1
  # say tan for both Galls, checker 2 white.
  defp two_checkers! do
    placements =
      for id <- ["f6", "f7"], {reviewer, c} <- [{"model-1", "tan"}, {"model-2", "white"}] do
        %{"id" => id, "reviewer" => reviewer, "category" => %{"value" => c}}
      end

    delivered!(placements)
  end

  defp toggle_value(view, item, value),
    do:
      view
      |> element("#item-#{item.id}-picker input[type=checkbox][value='#{value}']")
      |> render_click()

  test "a term is one row in its own section, holding nothing", %{conn: conn} do
    %{package: package, item: item} = delivered!()
    {:ok, view, _html} = page(conn, package)

    section = "#section-trait_terms"
    assert has_element?(view, section, "Trait terms to settle")
    # The section says once who the readers are, and what an open term means.
    assert has_element?(view, section, "the producer, the AI that read the Source")
    assert has_element?(view, section, "You can approve the Source with terms still open.")
    assert has_element?(view, "#{section} #item-#{item.id}", "pale tan")
    assert has_element?(view, "#{section} #item-#{item.id}", "2 Galls")
    assert has_element?(view, "#{section} #item-#{item.id}", "New term")
    # The readers split on g1: nothing is recommended.
    assert has_element?(view, "#item-#{item.id}-row [data-role=answer]", "No recommendation")
    refute has_element?(view, "#section-set_aside_terms")
    refute has_element?(view, "#section-trait_disputes")

    refute has_element?(view, "#approve-wait", "Traits")
    # No "Accept all" on Traits: each term is accepted on its own.
    refute has_element?(view, "#bulk-trait_terms")
    refute has_element?(view, "#{section} button", "Accept")

    text = view |> element(section) |> render() |> visible_text()
    refute text =~ @ref
  end

  test "opening it asks what the words mean, with the first Gall's quote and each Gall's readers",
       %{conn: conn} do
    %{package: package, item: item} = delivered!()
    {:ok, view, _html} = page(conn, package)
    open_row(view, item)

    detail = "#item-#{item.id}-detail"
    assert has_element?(view, "#{detail} [data-role=question]", "What color value is “pale tan”?")

    assert has_element?(
             view,
             "#{detail} [data-role=scope]",
             "The 2 Galls here that use them get the value now"
           )

    assert has_element?(view, "#item-#{item.id}-quotes", "pale tan, rough")
    assert has_element?(view, "#item-#{item.id}-quotes", "Used for 1 more Gall")

    # Each value a reader chose is an option, with who chose it.
    assert has_element?(
             view,
             "#item-#{item.id}-choices [data-role=tally]",
             "Most readers chose it for 1 of the 2 Galls"
           )

    readers = "#item-#{item.id}-readers"
    g1 = "#{readers} #item-#{item.id}-said-g1"
    assert has_element?(view, g1, "the large stem galls")
    assert has_element?(view, g1, "pale tan, rough")
    assert has_element?(view, g1, "The producer suggested tan.")
    assert has_element?(view, g1, "The checker placed it under white: pale reads as white.")
    assert has_element?(view, "#item-#{item.id}-said-g2", "The checker placed it under tan.")

    text = view |> element(readers) |> render() |> visible_text()
    refute text =~ @ref
  end

  test "what most readers chose is recommended, the readers named", %{conn: conn} do
    %{package: package, item: item} = two_checkers!()
    {:ok, view, _html} = page(conn, package)

    row = "#item-#{item.id}-row [data-role=answer]"
    assert has_element?(view, row, "tan")
    assert has_element?(view, row, "Chosen by the producer and checker 1, for both Galls")

    open_row(view, item)

    assert has_element?(
             view,
             "#item-#{item.id}-choices [data-recommended]",
             "Chosen by the producer and checker 1, for both Galls"
           )

    assert has_element?(
             view,
             "#item-#{item.id}-choices :not([data-recommended]) > label [data-role=tally]",
             "Chosen by checker 2, for both Galls"
           )

    # Accepting it is choosing it, one term at a time.
    choose(view, item, "Chosen by the producer and checker 1")

    assert has_element?(
             view,
             "#item-#{item.id}-effect",
             "The 2 Galls here get tan. From now on, “pale tan” means tan in every Source."
           )

    view |> element("#item-#{item.id}-decide") |> render_click()
    assert Import.get_queue_item!(item.id).decision == %{"place" => "tan"}
  end

  test "another value, searched and defined", %{conn: conn} do
    %{package: package, item: item} = delivered!()
    {:ok, view, _html} = page(conn, package)
    open_row(view, item)
    choose(view, item, "Another color")

    assert has_element?(view, "#item-#{item.id}-effect", "Choose a color value from the list.")

    view |> element("#item-#{item.id}-picker-filter") |> render_change(%{"q" => "bro"})
    assert has_element?(view, "#item-#{item.id}-picker input[value=brown]")
    refute has_element?(view, "#item-#{item.id}-picker input[value=red]")

    view |> element("#item-#{item.id}-picker input[value=brown]") |> render_click()
    assert has_element?(view, "#item-#{item.id}-effect", "The 2 Galls here get brown.")

    view |> element("#item-#{item.id}-decide") |> render_click()
    assert render(view) =~ "Decision recorded."
    assert Import.get_queue_item!(item.id).decision == %{"place" => "brown"}

    assert %{status: :placed, categories: ["brown"], placed_by: :curator} =
             Catalog.get_term("color", "pale tan")
  end

  test "more than one value: the readers' ticked first, at least two", %{conn: conn} do
    %{package: package, item: item} = delivered!()
    {:ok, view, _html} = page(conn, package)
    open_row(view, item)
    choose(view, item, "More than one color")

    # The readers' values come first, ticked.
    assert has_element?(view, "#item-#{item.id}-picker input[value=tan][checked]")
    assert has_element?(view, "#item-#{item.id}-picker input[value=white][checked]")
    assert has_element?(view, "#item-#{item.id}-picker", "a reader chose it")

    toggle_value(view, item, "white")

    assert has_element?(
             view,
             "#item-#{item.id}-effect",
             "Tick at least two color values, or choose a single value above."
           )

    assert has_element?(view, "#item-#{item.id}-decide[disabled]")

    toggle_value(view, item, "brown")
    assert has_element?(view, "#item-#{item.id}-effect", "The 2 Galls here get tan and brown.")

    view |> element("#item-#{item.id}-decide") |> render_click()
    assert render(view) =~ "Decision recorded."

    assert %{"place" => placed} = Import.get_queue_item!(item.id).decision
    assert Enum.sort(placed) == ["brown", "tan"]
    assert Enum.sort(Catalog.get_term("color", "pale tan").categories) == ["brown", "tan"]

    # The decided row names both.
    assert has_element?(view, "#item-#{item.id}-row", "tan and brown")
  end

  test "it depends on the Gall: per-Gall choices, the recommended ones filled on request",
       %{conn: conn} do
    %{package: package, item: item} = delivered!()
    {:ok, view, _html} = page(conn, package)
    open_row(view, item)

    # The per-Gall choices show only once the option is chosen.
    refute has_element?(view, "#item-#{item.id}-galls")
    choose(view, item, "It depends on the Gall")

    # g2's readers agree on tan (recommended for it); g1's split. Nothing is
    # chosen for a Gall until the curator does.
    assert has_element?(view, "#item-#{item.id}-gall-g2 [data-recommended]", "tan")
    refute has_element?(view, "#item-#{item.id}-gall-g1 [data-recommended]")
    refute has_element?(view, "#item-#{item.id}-galls input[checked]")
    assert has_element?(view, "#item-#{item.id}-decide[disabled]")
    assert has_element?(view, "#item-#{item.id}-effect", "Choose for 2 more Galls.")

    view
    |> element("#item-#{item.id}-fill", "Use the recommended answer for the 1 Gall that has one")
    |> render_click()

    assert has_element?(view, "#item-#{item.id}-gall-g2 input[value=tan][checked]")
    assert has_element?(view, "#item-#{item.id}-effect", "Choose for 1 more Gall.")

    view |> element("#item-#{item.id}-gall-g1-category-__text__") |> render_click()

    assert has_element?(
             view,
             "#item-#{item.id}-effect",
             "1 Gall gets the value you chose; 1 keeps the Source's words."
           )

    view |> element("#item-#{item.id}-decide") |> render_click()
    assert render(view) =~ "Decision recorded."

    assert Import.get_queue_item!(item.id).decision == %{
             "categories" => %{"g1" => nil, "g2" => "tan"}
           }

    assert Catalog.get_term("color", "pale tan").status == :ambiguous
  end

  test "a term used in more than one sense opens on its per-Gall choices", %{conn: conn} do
    %{item: first} = delivered!()

    {:ok, _} =
      Import.decide_queue_item(test_actor(), first, %{
        "categories" => %{"g1" => "white", "g2" => "tan"}
      })

    %{package: package, item: item} = delivered!()
    assert item.subject["status"] == "ambiguous"
    {:ok, view, _html} = page(conn, package)

    assert has_element?(view, "#item-#{item.id}-row", "Used in more than one sense")
    open_row(view, item)

    assert has_element?(
             view,
             "#item-#{item.id}-detail [data-role=question]",
             "What color value does “pale tan” mean, Gall by Gall?"
           )

    assert has_element?(view, "#item-#{item.id}-choices [data-chosen] #item-#{item.id}-galls")
    refute has_element?(view, "#item-#{item.id}-choices label", "Another color")
    assert has_element?(view, "#item-#{item.id}-choices label", "Keep as text")
  end

  test "a term that fits no value goes to superadmins", %{conn: conn} do
    %{package: package, item: item} = delivered!()
    {:ok, view, _html} = page(conn, package)
    open_row(view, item)
    choose(view, item, "Fits no color")

    assert has_element?(
             view,
             "#item-#{item.id}-effect",
             "Both Galls keep the Source's words. “pale tan” goes to the superadmins' list"
           )

    view |> element("#item-#{item.id}-decide") |> render_click()

    assert Import.get_queue_item!(item.id).decision == %{"no_fit" => true}
    assert %{status: :no_fit} = Catalog.get_term("color", "pale tan")

    # Decided rows say what was decided.
    assert has_element?(view, "#item-#{item.id}-row", "Fits no color")
  end

  # `c8c3` item 7: a dispute about a Fact of a term in question is asked once, in the term's
  # question.
  test "a disputed term is asked in its term's question, the checker's case shown",
       %{conn: conn} do
    finding = %{
      "batch" => "gall.json",
      "id" => "f6",
      "problem" => "unsupported",
      "reason" => "Pale tan is the color of the dried gall only. The fresh gall is green.",
      "summary" => "Only the dried gall is pale tan.",
      "reviewer" => "model-2",
      "response" => %{
        "decision" => "disagree",
        "reason" => "Ashmead describes the gall as he saw it. That is the gall.",
        "summary" => "Ashmead describes the gall as he saw it."
      }
    }

    %{package: package, item: item} = delivered!(nil, [finding])
    assert Import.list_queue_items(package, kind: :dispute, status: :all) == []
    {:ok, view, _html} = page(conn, package)

    open_row(view, item)
    said = "#item-#{item.id}-said-g1"
    assert has_element?(view, said, "The fresh gall is green.")
    assert has_element?(view, said, "Ashmead describes the gall as he saw it.")
    # It holds nothing.
    refute has_element?(view, "#approve-wait", "Traits")
  end

  # The Source in context (d213, Task 22).
  test "each Gall's quote shows its passage, and Read the Source marks them all",
       %{conn: conn} do
    %{package: package, item: item} = delivered!()
    {:ok, view, _html} = page(conn, package)
    open_row(view, item)

    assert has_element?(
             view,
             "#item-#{item.id}-quotes [data-role=passage] [data-cited]",
             "pale tan, rough"
           )

    assert has_element?(
             view,
             "#item-#{item.id}-said-g1 [data-role=passage] [data-cited]",
             "pale tan, rough"
           )

    view |> element("#item-#{item.id}-read-source") |> render_click()
    assert has_element?(view, "#source-reader-body [data-cited]", @words)
  end
end
