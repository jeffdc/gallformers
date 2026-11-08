defmodule GallformersWeb.Admin.ReviewLive.NotesPageTest do
  @moduledoc """
  The Gallformers Source's review page (`/admin/review/sources/:id`, `6611`
  Task 7): its notes grouped by what they hold, in three tabs (Ready,
  nothing to decide; Needs you; Approved) kept in the URL. A Ready note is
  one line with chips of what it adds, ticked by default, and the ticked
  notes are approved at once; a note with a question that holds it is in
  Needs you, where the question is decided in place.

  Not async: the one Gallformers Source, packages and the Catalog
  vocabularies.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1, test_actor: 0]
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Catalog
  alias Gallformers.DoclingFixtures
  alias Gallformers.Import
  alias Gallformers.Sources
  alias Gallformers.Taxa

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    %{conn: conn}
  end

  setup :audit_test_metadata

  setup do
    load_vocab!()
    gallformers = gallformers_source()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    plant_fixture(name: "Quercus lobata", parent: quercus)
    # The converted seeds' genus Andricus (old taxonomy row 33).
    andricus = Taxa.get_by_legacy_id(:taxonomy, 33)
    wasp = taxon_fixture(name: "Andricus quercuscalifornicus", parent: andricus)
    legacy = source_fixture("Legacy", "1990")

    described = fn name ->
      gall = gall_fixture(name: name)

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
          confirm(legacy)
        )

      gall
    end

    %{
      gallformers: gallformers,
      apple: described.("Andricus quercuscalifornicus apple gall"),
      stem: described.("Andricus quercuscalifornicus stem gall"),
      undescribed: gall_fixture(name: "Andricus q-lobata-bud-gall")
    }
  end

  @seen "Quercus lobata is added as a host based on this observation in California in " <>
          "[June](https://www.inaturalist.org/observations/123)."

  @bud "Small bud galls on Quercus lobata, pale and globular."

  @ruling "Quercus lobata is its only Host; earlier records from other oaks are " <>
            "misidentifications."

  defp host_fact(quote, extra \\ %{}) do
    Map.merge(
      %{
        "id" => "f1",
        "stance" => "confirm",
        "kind" => "relationship",
        "type" => "host_of",
        "subject" => "t2",
        "object" => "g1",
        "evidence" => [%{"item" => "#/texts/0", "quote" => quote}]
      },
      extra
    )
  end

  defp seen_facts do
    [
      host_fact("Quercus lobata is added as a host based on this observation", %{
        "evidence" => [
          %{
            "item" => "#/texts/0",
            "quote" => "Quercus lobata is added as a host based on this observation",
            "observations" => [%{"provider" => "inaturalist", "id" => "123"}]
          }
        ]
      }),
      %{
        "id" => "f2",
        "stance" => "confirm",
        "kind" => "occurrence",
        "gall" => "g1",
        "place" => %{"value" => "US-CA", "as_written" => "California"},
        "evidence" => [%{"item" => "#/texts/0", "quote" => "this observation in California"}]
      }
    ]
  end

  defp bud_facts do
    [
      host_fact("Small bud galls on Quercus lobata"),
      %{
        "id" => "f2",
        "stance" => "confirm",
        "kind" => "trait",
        "gall" => "g1",
        "trait" => "plant_part",
        "value" => %{"value" => "bud", "as_written" => "bud"},
        "evidence" => [%{"item" => "#/texts/0", "quote" => "Small bud galls"}]
      },
      %{
        "id" => "f3",
        "stance" => "confirm",
        "kind" => "trait",
        "gall" => "g1",
        "trait" => "shape",
        "value" => %{"value" => "globular", "as_written" => "globular"},
        "evidence" => [%{"item" => "#/texts/0", "quote" => "pale and globular"}]
      }
    ]
  end

  defp ruling_facts, do: [host_fact("Quercus lobata is its only Host")]

  # A note package for `gall` (its note `text`, stored as the Gall's note,
  # and the Facts read from it), delivered. With `findings`, the checker's
  # findings, answered by the producer.
  defp note!(gall, text, facts, findings \\ nil) do
    gallformers = Sources.get_gallformers_source()
    {:ok, _} = Sources.store_note(test_actor(), gallformers, gall.id, text)

    doc =
      DoclingFixtures.document()
      |> Map.put("texts", [
        %{
          "self_ref" => "#/texts/0",
          "label" => "text",
          "content_layer" => "body",
          "text" => text,
          "prov" => [],
          "children" => []
        }
      ])
      |> Map.put("body", %{"self_ref" => "#/body", "children" => [%{"$ref" => "#/texts/0"}]})
      |> Map.merge(%{"tables" => [], "pictures" => []})

    doc_json = DoclingFixtures.document_json(doc)

    batch = %{
      "format" => "gallformers-import",
      "format_version" => 3,
      "vocabulary_version" => "2026-10-11",
      "batch_type" => "gall",
      "mode" => "add",
      "batch_id" => "note-#{System.unique_integer([:positive])}-0000",
      "produced_at" => "2026-10-30T14:00:00Z",
      "producer" => %{"name" => "notes", "version" => "0"},
      "source" => %{
        "gallformers" => true,
        "note" => %{"gallformers_gall_id" => gall.id, "stated_on" => "2026-10-30"},
        "document" => %{"file" => "document.json", "sha256" => sha256(doc_json)}
      },
      "taxa" => [
        %{
          "ref" => "t1",
          "name_as_written" => "Andricus quercuscalifornicus",
          "rank" => "species"
        },
        %{"ref" => "t2", "name_as_written" => "Quercus lobata", "rank" => "species"}
      ],
      "galls" => [
        %{
          "ref" => "g1",
          "name_as_written" => "the gall",
          "identified_by" => %{"inducer" => "t1"},
          "gallformers_gall_id" => gall.id
        }
      ],
      "facts" => facts
    }

    files = %{"document.json" => doc_json, "gall.json" => Jason.encode!(batch)}

    case findings do
      nil -> deliver!(files, review: false)
      findings -> files |> with_review(findings, responded: true) |> deliver!()
    end
  end

  defp dispute_finding do
    %{
      "batch" => "gall.json",
      "id" => "f1",
      "problem" => "unsupported",
      "reason" => "The note names no Observation of this Host.",
      "response" => %{"decision" => "disagree", "reason" => "It names the Host plainly."}
    }
  end

  defp page(conn, _source, query \\ ""),
    do: live(conn, ~p"/admin/review/notes" <> query)

  describe "Ready" do
    test "groups the notes by what they hold, one line each with chips, ticked", ctx do
      bud = note!(ctx.undescribed, @bud, bud_facts())
      seen = note!(ctx.apple, @seen, seen_facts())
      ruling = note!(ctx.stem, @ruling, ruling_facts())

      for p <- [bud, seen, ruling], do: assert(p.status == :awaiting_review)
      for p <- [bud, seen, ruling], do: assert(Import.list_queue_items(p) == [])

      {:ok, view, _html} = page(ctx.conn, ctx.gallformers)

      assert has_element?(view, "#tab-ready", "Ready, nothing to decide (3)")
      assert has_element?(view, "#tab-needs", "Needs you (0)")
      assert has_element?(view, "#tab-approved", "Approved (0)")

      assert has_element?(view, "#note-group-undescribed", "Undescribed Galls")
      assert has_element?(view, "#note-group-undescribed #note-#{bud.id}", "q-lobata-bud-gall")
      assert has_element?(view, "#note-#{bud.id} [data-role=chip]", "Host Quercus lobata")
      assert has_element?(view, "#note-#{bud.id} [data-role=chip]", "plant part")
      assert has_element?(view, "#note-#{bud.id} [data-role=chip]", "shape")

      assert has_element?(
               view,
               "#note-group-observations #note-#{seen.id}",
               "Andricus quercuscalifornicus apple gall"
             )

      assert has_element?(view, "#note-#{seen.id} [data-role=chip]", "seen in")

      assert has_element?(
               view,
               "#note-group-other #note-#{ruling.id}",
               "Andricus quercuscalifornicus stem gall"
             )

      for p <- [bud, seen, ruling] do
        assert has_element?(view, "#tick-#{p.id}[checked]")

        assert has_element?(
                 view,
                 "#note-#{p.id} a[href='/admin/review/packages/#{p.id}']",
                 "View the note"
               )
      end

      assert has_element?(view, "#approve-notes", "Approve 3 ticked notes")
    end

    test "untick a note, then approve: only the ticked are approved", ctx do
      bud = note!(ctx.undescribed, @bud, bud_facts())
      seen = note!(ctx.apple, @seen, seen_facts())
      ruling = note!(ctx.stem, @ruling, ruling_facts())

      {:ok, view, _html} = page(ctx.conn, ctx.gallformers)

      view |> element("#tick-#{seen.id}") |> render_click()
      refute has_element?(view, "#tick-#{seen.id}[checked]")
      assert has_element?(view, "#approve-notes", "Approve 2 ticked notes")

      html = view |> element("#approve-notes") |> render_click()
      assert html =~ "Approved 2 notes"

      assert Import.get_package!(bud.id).status == :approved
      assert Import.get_package!(ruling.id).status == :approved
      assert Import.get_package!(seen.id).status == :awaiting_review

      assert has_element?(view, "#tab-ready", "(1)")
      assert has_element?(view, "#tab-approved", "Approved (2)")
      assert has_element?(view, "#note-#{seen.id}")
      refute has_element?(view, "#note-#{bud.id}")
    end

    test "a group's own button approves only that group's ticked notes", ctx do
      bud = note!(ctx.undescribed, @bud, bud_facts())
      seen = note!(ctx.apple, @seen, seen_facts())

      {:ok, view, _html} = page(ctx.conn, ctx.gallformers)

      view
      |> element("#note-group-observations #approve-group-observations", "Approve 1 ticked here")
      |> render_click()

      assert Import.get_package!(seen.id).status == :approved
      assert Import.get_package!(bud.id).status == :awaiting_review
    end
  end

  describe "Needs you" do
    test "holds a note with a dispute; deciding it moves the note to Ready", ctx do
      ready = note!(ctx.apple, @seen, seen_facts())
      disputed = note!(ctx.undescribed, @bud, bud_facts(), [dispute_finding()])
      [dispute] = Import.list_queue_items(disputed, kind: :dispute)

      {:ok, view, _html} = page(ctx.conn, ctx.gallformers)
      assert has_element?(view, "#note-#{ready.id}")
      refute has_element?(view, "#note-#{disputed.id}")
      assert has_element?(view, "#tab-needs", "Needs you (1)")

      view |> element("#tab-needs") |> render_click()
      assert_patch(view, ~p"/admin/review/notes?tab=needs")

      assert has_element?(view, "#note-#{disputed.id}", "1 to decide")
      assert has_element?(view, "#note-#{disputed.id} #item-#{dispute.id}")

      # The dispute opens in place and is decided there.
      view |> element("#item-#{dispute.id}-row") |> render_click()
      assert has_element?(view, "#item-#{dispute.id}-detail", "Keep it")

      view |> element("#item-#{dispute.id}-choice-0") |> render_click()

      view |> element("#item-#{dispute.id}-decide") |> render_click()

      assert Import.get_queue_item!(dispute.id).decision == %{"keep" => true}
      refute has_element?(view, "#note-#{disputed.id}")
      assert has_element?(view, "#tab-needs", "Needs you (0)")
      assert has_element?(view, "#tab-ready", "Ready, nothing to decide (2)")

      view |> element("#tab-ready") |> render_click()
      assert has_element?(view, "#note-#{disputed.id}")
      assert has_element?(view, "#tick-#{disputed.id}[checked]")
    end
  end

  describe "tabs" do
    test "are in the URL", ctx do
      seen = note!(ctx.apple, @seen, seen_facts())
      {:ok, _} = Import.approve_package(test_actor(), seen)

      {:ok, view, _html} = page(ctx.conn, ctx.gallformers, "?tab=approved")
      assert has_element?(view, "#tab-approved[aria-pressed=true]")
      assert has_element?(view, "#note-#{seen.id}", "Andricus quercuscalifornicus apple gall")
      refute has_element?(view, "#tick-#{seen.id}")

      view |> element("#tab-ready") |> render_click()
      assert_patch(view, ~p"/admin/review/notes")
      assert has_element?(view, "#tab-ready[aria-pressed=true]")
      refute has_element?(view, "#note-#{seen.id}")
      assert has_element?(view, "#notes", "No note is ready to approve.")
    end
  end
end
