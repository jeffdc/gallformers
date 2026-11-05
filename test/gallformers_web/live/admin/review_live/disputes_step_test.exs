defmodule GallformersWeb.Admin.ReviewLive.DisputesStepTest do
  @moduledoc """
  The Disputes step (matter `d213`, Task 20): disputes about the same
  statement are one question listing every Gall, kept with exceptions or
  dropped together (`Gallformers.Import.decide_group/3`); each side's
  position in a sentence, the full arguments behind a disclosure, nothing
  recommended; disputes about Trait terms are on the Traits step.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1, test_actor: 0]
  import Gallformers.ImportFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Import

  # A batch-local ref (t24, g1, f5, a2) as a word.
  @ref ~r/\b[tgfa]\d+\b/

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    load_vocab!()
    %{conn: conn}
  end

  setup :audit_test_metadata

  defp finding(id, reason, response, opts \\ []) do
    %{
      "batch" => "gall.json",
      "id" => id,
      "problem" => "unsupported",
      "reason" => reason,
      "reviewer" => "model-2",
      "response" => %{"decision" => "disagree", "reason" => response}
    }
    |> then(&if(opts[:summary], do: Map.put(&1, "summary", opts[:summary]), else: &1))
    |> then(fn f ->
      if opts[:answer],
        do: put_in(f, ["response", "summary"], opts[:answer]),
        else: f
    end)
  end

  @host_reason "The Host is only an unknown oak. The red oak pairing is about another Gall."
  @host_response "Ashmead uses oak for the genus throughout. He pairs it with Quercus."

  # g1 and g2, each on Q. lobata (f2, f8), both disputed; and g1's color
  # term (f6) disputed too.
  defp delivered!(opts \\ []) do
    gall =
      batch()
      |> unique_batch_id()
      |> Map.put("format_version", 4)
      |> put_in(["source", "title"], "Galls of the oaks")
      |> put_in(["source", "authors"], ["Ashmead, W. H."])
      |> put_in(["source", "authored"], %{"date" => "1897", "as_written" => "1897"})
      |> then(fn gall ->
        case opts[:host] do
          nil ->
            gall

          {name, rank} ->
            put_in(gall, ["taxa", Access.at(1)], %{
              "ref" => "t2",
              "name_as_written" => name,
              "rank" => rank
            })
        end
      end)
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
            %{
              "id" => "f6",
              "stance" => "confirm",
              "kind" => "trait",
              "gall" => "g1",
              "trait" => "color",
              "term" => "pale tan",
              "category" => %{"value" => "tan"},
              "evidence" => [%{"item" => "#/texts/1", "quote" => "pale tan"}]
            },
            %{
              "id" => "f8",
              "stance" => "confirm",
              "kind" => "relationship",
              "type" => "host_of",
              "subject" => "t2",
              "object" => "g2",
              "evidence" => [
                %{"item" => "#/texts/2", "quote" => "earlier records from Q. douglasii"}
              ]
            }
          ]
      end)

    findings = [
      finding("f2", @host_reason, @host_response,
        summary: "An unnamed oak is never paired with a scientific name.",
        answer: "Ashmead uses oak for the genus."
      ),
      finding("f8", @host_reason, @host_response),
      finding("f6", "Only the dried gall is tan.", "Ashmead saw it so.")
    ]

    findings =
      if opts[:single_host], do: Enum.reject(findings, &(&1["id"] == "f8")), else: findings

    package = package(gall: gall) |> with_review(findings, responded: true) |> deliver!()
    disputes = package |> Import.list_queue_items(kind: :dispute) |> Enum.sort_by(& &1.id)
    host = Enum.filter(disputes, &(&1.statement_ref in ["f2", "f8"]))
    [trait] = Enum.filter(disputes, &(&1.statement_ref == "f6"))
    %{package: package, host: host, trait: trait}
  end

  defp page(conn, package), do: live(conn, ~p"/admin/review/packages/#{package.id}/disputes")

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

  @keep "Keep it: Q. lobata is the Host, for these 2 Galls"

  test "identical disputes are one question listing every Gall", %{conn: conn} do
    %{package: package, host: [first, second]} = delivered!()
    {:ok, view, _html} = page(conn, package)

    section = "#section-disputes"
    assert has_element?(view, "#{section} #item-#{first.id}", "Q. lobata is the Host")
    assert has_element?(view, "#{section} #item-#{first.id}", "2 Galls")
    refute has_element?(view, "#item-#{second.id}-row")
    assert has_element?(view, "#item-#{first.id}-row [data-role=answer]", "Keep or drop?")

    open_row(view, first)

    assert has_element?(
             view,
             "#item-#{first.id}-detail [data-role=question]",
             "Should this statement go in for these 2 Galls: Q. lobata is the Host?"
           )

    # Nothing is recommended on a dispute.
    refute has_element?(view, "#item-#{first.id}-choices [data-role=recommended]")

    choose(view, first, @keep)

    # Every Gall, with its quote and its passage, ticked to start with.
    galls = "#item-#{first.id}-keep"

    assert has_element?(
             view,
             "#{galls} #item-#{first.id}-keep-#{first.id}",
             "the large stem galls"
           )

    assert has_element?(
             view,
             "#{galls} #item-#{first.id}-keep-#{first.id}",
             "Common on Q. lobata"
           )

    assert has_element?(
             view,
             "#{galls} #item-#{first.id}-keep-#{second.id}",
             "earlier records from Q. douglasii"
           )

    assert has_element?(view, "#{galls} input#item-#{first.id}-keep-#{second.id}-tick[checked]")
    assert has_element?(view, "#{galls} [data-role=passage]")
    assert has_element?(view, "#item-#{first.id}-effect", "It goes in for both Galls")

    for part <- ["[data-role=question]", "#item-#{first.id}-choices", "#item-#{first.id}-sides"] do
      text = view |> element("#item-#{first.id}-detail #{part}") |> render() |> visible_text()
      refute text =~ @ref
    end
  end

  test "keeping it for every Gall but those unticked", %{conn: conn} do
    %{package: package, host: [first, second]} = delivered!()
    {:ok, view, _html} = page(conn, package)
    open_row(view, first)
    choose(view, first, @keep)

    view |> element("#item-#{first.id}-keep-#{second.id}-tick") |> render_click()
    refute has_element?(view, "input#item-#{first.id}-keep-#{second.id}-tick[checked]")
    assert has_element?(view, "#item-#{first.id}-effect", "Kept for 1 of the 2 Galls; 1 dropped")

    view |> element("#item-#{first.id}-keep-#{first.id}-tick") |> render_click()
    assert has_element?(view, "#item-#{first.id}-decide[disabled]")
    assert has_element?(view, "#item-#{first.id}-effect", "choose “Drop it for both” instead")

    view |> element("#item-#{first.id}-keep-#{first.id}-tick") |> render_click()
    view |> element("#item-#{first.id}-decide") |> render_click()
    assert render(view) =~ "Decision recorded."

    assert Import.get_queue_item!(first.id).decision == %{"keep" => true}
    assert Import.get_queue_item!(second.id).decision == %{"skip" => true}

    # Decided, the one row says how.
    assert has_element?(view, "#item-#{first.id}-row", "Kept for 1 Gall; dropped for 1")
  end

  test "a single Host dispute kept as another plant says so once decided", %{conn: conn} do
    plant = plant_fixture(name: "Quercus fixtdouglasii")
    %{package: package, host: [single]} = delivered!(single_host: true)

    {:ok, _} =
      Import.decide_queue_item(test_actor(), single, %{
        "keep" => true,
        "host_reading" => %{"name" => "Q. lobata", "taxon_id" => plant.id}
      })

    {:ok, view, _html} = page(conn, package)

    assert has_element?(
             view,
             "#item-#{single.id}-row",
             "Kept, its Host read as Quercus fixtdouglasii"
           )
  end

  test "keeping it for every Gall, its Host read as another plant", %{conn: conn} do
    plant = plant_fixture(name: "Quercus fixtdouglasii")
    %{package: package, host: [first, second]} = delivered!()
    {:ok, view, _html} = page(conn, package)
    open_row(view, first)
    choose(view, first, "Keep it for these 2 Galls, as another plant")

    assert has_element?(view, "#item-#{first.id}-decide[disabled]")
    assert has_element?(view, "#item-#{first.id}-effect", "Pick the plant meant from the search.")

    view
    |> with_target("#item-row-#{first.id}")
    |> render_hook("search_plant", %{"value" => "fixtdouglasii"})

    view
    |> element("#item-#{first.id}-picker-results button", "Quercus fixtdouglasii")
    |> render_click()

    assert has_element?(
             view,
             "#item-#{first.id}-effect",
             "It goes in for every Gall, on Quercus fixtdouglasii. Ashmead 1897's “Q. lobata” " <>
               "is read as Quercus fixtdouglasii throughout this Source"
           )

    view |> element("#item-#{first.id}-decide") |> render_click()
    assert render(view) =~ "Decision recorded."

    reading = %{"name" => "Q. lobata", "taxon_id" => plant.id, "sensu" => "Ashmead 1897"}

    for item <- [first, second] do
      assert Import.get_queue_item!(item.id).decision == %{
               "keep" => true,
               "host_reading" => reading
             }
    end
  end

  test "a disputed Host that is a genus: its sections are listed first for the plant meant",
       %{conn: conn} do
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    lobatae = plant_fixture(name: "Lobatae", rank: :section, parent: quercus)
    plant_fixture(name: "Quercus", rank: :section, parent: quercus)
    plant_fixture(name: "Quercus fixtvelutina", parent: lobatae)
    {:ok, _} = Gallformers.Taxa.add_common_name(test_actor(), lobatae, "Red Oaks")

    %{package: package, host: [first, second]} = delivered!(host: {"Quercus", "genus"})
    {:ok, view, _html} = page(conn, package)
    open_row(view, first)
    choose(view, first, "Keep it for these 2 Galls, as another plant")

    results = "#item-#{first.id}-picker-results"
    assert has_element?(view, "#{results} button", "Lobatae")
    assert has_element?(view, "#{results} button", "Red Oaks")

    # The search finds sections too.
    view
    |> with_target("#item-row-#{first.id}")
    |> render_hook("search_plant", %{"value" => "Lobatae"})

    assert has_element?(view, "#{results} button", "Lobatae")

    view |> element("#{results} button", "Lobatae") |> render_click()

    # The genus is Ashmead's name for many Galls: the plant goes in for these only.
    assert has_element?(
             view,
             "#item-#{first.id}-effect",
             "It goes in on Lobatae, for these 2 Galls only. Ashmead 1897's other “Quercus” " <>
               "statements stay as they are."
           )

    view |> element("#item-#{first.id}-decide") |> render_click()
    assert render(view) =~ "Decision recorded."

    for item <- [first, second] do
      assert Import.get_queue_item!(item.id).decision == %{
               "keep" => true,
               "host_taxon_id" => lobatae.id
             }
    end

    assert Gallformers.Taxa.list_synonyms(lobatae.id) == []
    assert has_element?(view, "#item-#{first.id}-row", "Kept for both Galls, on sect. Lobatae")
  end

  test "a single genus Host dispute kept on a section says so once decided", %{conn: conn} do
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    lobatae = plant_fixture(name: "Lobatae", rank: :section, parent: quercus)

    %{package: package, host: [single]} =
      delivered!(single_host: true, host: {"Quercus", "genus"})

    {:ok, _} =
      Import.decide_queue_item(test_actor(), single, %{
        "keep" => true,
        "host_taxon_id" => lobatae.id
      })

    {:ok, view, _html} = page(conn, package)
    assert has_element?(view, "#item-#{single.id}-row", "Kept, its Host set to sect. Lobatae")
  end

  test "dropping it for every Gall", %{conn: conn} do
    %{package: package, host: [first, second]} = delivered!()
    {:ok, view, _html} = page(conn, package)
    open_row(view, first)
    choose(view, first, "Drop it for both")
    view |> element("#item-#{first.id}-decide") |> render_click()

    assert Import.get_queue_item!(first.id).decision == %{"skip" => true}
    assert Import.get_queue_item!(second.id).decision == %{"skip" => true}
    assert has_element?(view, "#item-#{first.id}-row", "Dropped for both Galls")
  end

  test "both positions in a sentence, side by side; the full arguments behind a disclosure",
       %{conn: conn} do
    %{package: package, host: [first, _second]} = delivered!()
    {:ok, view, _html} = page(conn, package)
    open_row(view, first)

    sides = "#item-#{first.id}-sides"
    assert has_element?(view, sides, "The producer kept it")
    assert has_element?(view, sides, "Ashmead uses oak for the genus.")
    assert has_element?(view, sides, "A checker questioned it")
    assert has_element?(view, sides, "An unnamed oak is never paired with a scientific name.")
    refute has_element?(view, sides, "The red oak pairing is about another Gall.")

    arguments = "#item-#{first.id}-arguments"
    assert has_element?(view, "details#{arguments}", "The full arguments")
    assert has_element?(view, arguments, @host_reason)
    assert has_element?(view, arguments, @host_response)
  end

  test "disputes about Trait terms are on the Traits step", %{conn: conn} do
    %{package: package, trait: trait} = delivered!()
    {:ok, view, _html} = page(conn, package)

    refute has_element?(view, "#item-#{trait.id}-row")

    assert has_element?(
             view,
             "#trait-disputes-moved",
             "1 dispute about a Trait term (“pale tan”) is on the Traits step"
           )

    assert has_element?(
             view,
             "#trait-disputes-moved a[href='/admin/review/packages/#{package.id}/traits']"
           )
  end
end
