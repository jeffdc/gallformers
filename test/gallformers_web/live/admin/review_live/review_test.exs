defmodule GallformersWeb.Admin.ReviewLive.ReviewTest do
  @moduledoc """
  One Source's review, one thing at a time (matter `6611`, Task 8): the
  first question and the rail, deciding in one click and moving on with
  Undo, skipping, the hedged statements, the Everything list, what
  approving will add, Approve and Deny, and a Trait term answered Gall by
  Gall.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1]
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.DoclingFixtures
  alias Gallformers.Import
  alias Gallformers.Import.Package
  alias Gallformers.Import.QueueItem
  alias Gallformers.Repo

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    %{conn: conn}
  end

  setup :audit_test_metadata

  @unmapped %{
    "term" => "lignified",
    "slot" => "other",
    "gall" => "g1",
    "evidence" => [%{"item" => "#/texts/3", "quote" => "an external parasitoid"}],
    "note" => "for one Host only"
  }

  # A package awaiting review, by Ashmead: its Host and names wait (holding
  # approval), a hedged statement apart.
  defp awaiting! do
    load_vocab!()

    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "Galls of the oaks")
      |> put_in(["source", "authored"], %{"date" => "1897", "as_written" => "1897"})
      |> put_in(["source", "authors"], ["Ashmead, W. H."])
      |> Map.put("unmapped", [@unmapped])

    package(gall: gall) |> with_review() |> deliver!()
  end

  # A package whose names all resolve: only its hedged statement is open.
  defp settled! do
    plant_fixture(name: "Quercus lobata")
    taxon_fixture(name: "Andricus quercuscalifornicus", kingdom: "Animalia")
    taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")
    load_vocab!()

    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "A ready paper")
      |> put_in(["source", "authors"], ["Ashmead, W. H."])
      |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
      |> put_in(["galls", Access.at(0), "new"], true)
      |> Map.put("unmapped", [@unmapped])

    package(gall: gall) |> with_review() |> deliver!()
  end

  @words "The galls are pale tan, rough; the bud galls pale tan and lumpy, tannish all over."

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

  defp trait(id, gall, quote, term \\ "pale tan") do
    %{
      "id" => id,
      "stance" => "confirm",
      "kind" => "trait",
      "gall" => gall,
      "trait" => "color",
      "term" => term,
      "category" => %{"value" => "tan"},
      "evidence" => [%{"item" => "#/texts/5", "quote" => quote}]
    }
  end

  # g1 and g2 with the color term "pale tan": the producer says tan for
  # both; the checker white for g1 (with its reason) and tan for g2.
  defp delivered!(placements \\ nil, findings \\ [], more \\ []) do
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
          ] ++ more
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

    [item | _] = Import.list_queue_items(package, kind: :trait_term)
    %{package: package, item: item}
  end

  # Two new color terms most readers placed under tan (the producer and
  # checker 1; checker 2 says white): two suggested answers, the readers'
  # own, not a proposal the back end stored.
  defp agreed_terms! do
    placements =
      for id <- ["f6", "f7", "f8"], {reviewer, c} <- [{"model-1", "tan"}, {"model-2", "white"}] do
        %{"id" => id, "reviewer" => reviewer, "category" => %{"value" => c}}
      end

    %{package: package} =
      delivered!(placements, [], [trait("f8", "g1", "tannish all over", "tannish")])

    {package, Import.list_queue_items(package, kind: :trait_term)}
  end

  defp review(conn, package, query \\ ""),
    do: live(conn, "/admin/review/packages/#{package.id}#{query}")

  defp open_items(package),
    do: package |> Import.list_queue_items() |> Enum.filter(&(&1.status == :open))

  # The question on the page: its item's ID, from the card's id.
  defp current_id(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[id^=q-][id$=-card]")
    |> LazyHTML.attribute("id")
    |> List.first()
    |> then(&(&1 && &1 |> String.trim_leading("q-") |> String.trim_trailing("-card")))
  end

  # The one-click answer labelled `label` on the current card.
  defp use_answer(view, label) do
    id = current_id(view)

    option =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[id^='q-#{id}-c']")
      |> Enum.filter(&(&1 |> LazyHTML.attribute("id") |> hd() |> String.match?(~r/-c\d+$/)))
      |> Enum.find(&(LazyHTML.text(LazyHTML.query(&1, "[data-role=label]")) =~ label))

    assert option, "no answer “#{label}” on question #{id}"
    value = option |> LazyHTML.query("button") |> LazyHTML.attribute("phx-value-choice") |> hd()
    view |> element("#q-#{id} button[phx-value-choice='#{value}']") |> render_click()
    id
  end

  describe "one at a time" do
    test "opens on the first question, the rail saying how far along", %{conn: conn} do
      package = awaiting!()
      open = open_items(package)
      {:ok, view, _html} = review(conn, package)

      assert has_element?(view, "h1", "Ashmead 1897")
      assert current_id(view) != nil
      assert has_element?(view, "[data-role=answered]", "0 of")
      assert has_element?(view, "button[phx-click=approve][disabled]")
      assert has_element?(view, "[data-role=approve-why]", "marked questions")
      assert has_element?(view, "nav[aria-label=Stages] [aria-current=step]", "Names")
      assert length(open) > 1
    end

    test "asks “Which Source this is” first, answered in one click", %{conn: conn} do
      package = awaiting!()
      [batch] = Import.list_batches(package)
      held = source_fixture("Galls of the oaks, again", "1897")

      item =
        %QueueItem{}
        |> QueueItem.create_changeset(%{
          package_id: package.id,
          batch_id: batch.id,
          kind: :ambiguous_match,
          statement_ref: "source",
          subject: %{"title" => "Galls of the oaks", "citation" => "Ashmead 1897."},
          proposal: %{"candidate_ids" => [held.id]}
        })
        |> Repo.insert!()

      {:ok, view, _html} = review(conn, package)

      assert current_id(view) == "#{item.id}"
      assert has_element?(view, "#q-#{item.id} h2", "a Source we already have")

      use_answer(view, held.title)
      assert Import.get_queue_item!(item.id).decision == %{"source_id" => held.id}
    end

    test "a Host question says in a line what WCVP has for the name", %{conn: conn} do
      package = awaiting!()
      host = Enum.find(open_items(package), &(&1.kind == :unresolved_host))
      {:ok, view, _html} = review(conn, package)

      assert current_id(view) == "#{host.id}"
      render_async(view)
      assert has_element?(view, "#q-#{host.id} p[data-role=wcvp]", "WCVP")
    end

    test "Skip for now moves on to the next question, the skipped one last", %{conn: conn} do
      package = awaiting!()
      {:ok, view, _html} = review(conn, package)
      first = current_id(view)

      view |> element("#q-#{first} button[phx-click=skip]") |> render_click()

      refute current_id(view) == first
    end

    test "an answer is taken in one click; the page says so, moves on, and can undo it",
         %{conn: conn} do
      package = awaiting!()
      {:ok, view, _html} = review(conn, package)

      id = use_answer(view, "Leave this Host out")

      assert Import.get_queue_item!(String.to_integer(id)).status == :decided
      assert has_element?(view, "#saved", "Saved:")
      refute current_id(view) == id

      view |> element("#saved button", "Undo") |> render_click()

      assert Import.get_queue_item!(String.to_integer(id)).status == :open
      refute has_element?(view, "#saved")
    end

    test "the hedged statements open from the rail, and Back returns", %{conn: conn} do
      package = awaiting!()
      {:ok, view, _html} = review(conn, package)

      view |> element("button[phx-click=hedges]") |> render_click()
      assert_patched(view, "/admin/review/packages/#{package.id}?hedges=")
      assert has_element?(view, "#unit h2", "Hedged statements")
      assert has_element?(view, "#unit li", "lignified")

      view |> element("#unit button", "Back to the questions") |> render_click()
      assert current_id(view) != nil
    end

    test "a hedged statement's Add it… opens its question", %{conn: conn} do
      package = awaiting!()
      hedge = Enum.find(open_items(package), &(&1.subject["term"] == "lignified"))
      {:ok, view, _html} = review(conn, package, "?hedges")

      refute has_element?(view, "#q-#{hedge.id}-card")
      view |> element("#unit li[data-id='#{hedge.id}'] button", "Add it…") |> render_click()

      assert has_element?(view, "#q-#{hedge.id}-card [data-role=label]", "Leave it out")
    end

    test "with nothing left, it shows what approving will add, and Approve applies",
         %{conn: conn} do
      package = settled!()
      {:ok, view, _html} = review(conn, package)

      assert has_element?(view, "#unit h2", "What approving will add")
      render_async(view, 5_000)
      assert has_element?(view, "#facts")

      refute has_element?(view, "button[phx-click=approve][disabled]")
      view |> element("button[phx-click=approve]") |> render_click()

      assert Import.get_package!(package.id).status in [:approved, :applying, :applied]
    end

    test "Deny asks for a reason, then denies the Source", %{conn: conn} do
      package = awaiting!()
      {:ok, view, _html} = review(conn, package)

      view |> element("button[phx-click=deny_open]") |> render_click()
      assert has_element?(view, "#deny-modal")

      view |> form("#deny-form", deny: %{reason: "Not a gall paper"}) |> render_submit()

      assert %Package{status: :denied} = Import.get_package!(package.id)
    end
  end

  describe "a Trait term" do
    test "is answered Gall by Gall, what most readers chose ticked to start with",
         %{conn: conn} do
      %{package: package, item: item} = delivered!()
      {:ok, view, _html} = review(conn, package, "?stage=traits")
      card = "#q-#{item.id}"

      assert has_element?(view, "#{card} h2", "What does “pale tan” mean for these 2 Galls?")
      assert has_element?(view, "#{card}-gall-g1 [data-role=pipeline]", "couldn't agree")
      assert has_element?(view, "#{card}-gall-g2 [data-role=pipeline]", "suggests tan")
      assert has_element?(view, "#{card}-g2-values[checked]")
      assert has_element?(view, "#{card}-g2-list-tan[checked]")
      assert has_element?(view, "#{card} button[phx-click=trait_save][disabled]")

      view |> element("#{card}-g1-values") |> render_click()
      view |> element("#{card}-g1-list-white") |> render_click()
      view |> element("#{card} button[phx-click=trait_save]") |> render_click()

      decided = Import.get_queue_item!(item.id)
      assert decided.status == :decided
      assert decided.decision == %{"categories" => %{"g1" => ["white"], "g2" => ["tan"]}}
    end

    test "one Gall's answer can be used for the others", %{conn: conn} do
      %{package: package, item: item} = delivered!()
      {:ok, view, _html} = review(conn, package, "?stage=traits")
      card = "#q-#{item.id}"

      view
      |> element("#{card}-gall-g2 button[phx-click=trait_all]", "Use this for the other 1 Gall")
      |> render_click()

      assert has_element?(view, "#{card}-g1-list-tan[checked]")
      view |> element("#{card} button[phx-click=trait_save]") |> render_click()

      assert Import.get_queue_item!(item.id).status == :decided
    end
  end

  describe "the way in" do
    # A delivered package of `source`, which Gallformers holds.
    defp matched!(source) do
      gall =
        batch()
        |> unique_batch_id()
        |> put_in(["source", "title"], "Galls of the oaks")
        |> put_in(["source", "citation"], source.citation)

      package = package(gall: gall) |> with_review() |> deliver!()
      assert package.source_id == source.id
      package
    end

    # Open questions that count as left: all but what was set aside.
    defp questions_left(package) do
      Enum.count(
        Import.list_queue_items(package),
        &(&1.status == :open and
            &1.kind not in [:set_aside_term, :set_aside_statement, :trait_term])
      )
    end

    test "the Sources list and the Source's page link to its review, with the questions left",
         %{conn: conn} do
      source = source_fixture("Ashmead, W. H. 1897. Galls of the oaks", "1897")
      package = matched!(source)
      left = questions_left(package)
      assert left > 1

      {:ok, view, _html} = live(conn, ~p"/admin/sources")
      view |> form("#source-search-form", %{query: source.title}) |> render_change()

      assert has_element?(
               view,
               "#source-#{source.id} a[href='/admin/review/sources/#{source.id}']",
               "Being reviewed: #{left} questions left"
             )

      {:ok, view, _html} = live(conn, ~p"/admin/sources/#{source.id}")

      assert has_element?(
               view,
               "#source-review a[href='/admin/review/sources/#{source.id}']",
               "Being reviewed: #{left} questions left"
             )

      {:ok, view, _html} = live(conn, ~p"/admin/review/sources/#{source.id}")
      assert has_element?(view, "h1", "Weld 1897")
      assert has_element?(view, "aside a[href='/admin/sources/#{source.id}']")
    end

    test "the Gallformers notes Source opens its notes page", %{conn: conn} do
      gallformers = Gallformers.Sources.get_gallformers_source()

      assert {:error, {:live_redirect, %{to: "/admin/review/notes"}}} =
               live(conn, ~p"/admin/review/sources/#{gallformers.id}")
    end
  end

  describe "a batch of suggested answers" do
    test "Accept all decides each as suggested", %{conn: conn} do
      {package, [_, _] = items} = agreed_terms!()
      {:ok, view, _html} = review(conn, package, "?stage=traits")

      assert has_element?(view, "#unit h2", "have suggested answers")
      view |> element("#unit button[phx-click=accept_batch]", "Accept all 2") |> render_click()

      for item <- items do
        assert %{status: :decided, decision: %{"place" => "tan"}} =
                 Import.get_queue_item!(item.id)
      end

      assert has_element?(view, "#saved", "Accepted 2 suggested answers.")
    end

    test "an unticked one isn't accepted and comes next on its own", %{conn: conn} do
      {package, [first, second]} = agreed_terms!()
      {:ok, view, _html} = review(conn, package, "?stage=traits")

      view |> element("#unit input[phx-value-id='#{second.id}']") |> render_click()

      view
      |> element("#unit button[phx-click=accept_batch]", "Accept the 1 ticked")
      |> render_click()

      assert Import.get_queue_item!(first.id).status == :decided
      assert Import.get_queue_item!(second.id).status == :open
      assert current_id(view) == "#{second.id}"
    end
  end

  describe "everything" do
    test "lists every open question by section; a row opens its card", %{conn: conn} do
      package = awaiting!()
      [item | _] = open_items(package) |> Enum.reject(&(&1.kind == :set_aside_term))
      {:ok, view, _html} = review(conn, package, "?view=all")

      assert has_element?(view, "#everything")
      assert has_element?(view, "#row-#{item.id}")
      refute has_element?(view, "#q-#{item.id}-card")

      view |> element("#row-#{item.id} button") |> render_click()
      assert has_element?(view, "#q-#{item.id}-card")
    end
  end
end
