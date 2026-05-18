defmodule GallformersWeb.Admin.IngestionReviewLive.WorkspaceDescriptionTest do
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Ingestions
  alias Gallformers.Sources

  # A canonical evidence_prose list used across tests. Document-order is the
  # order in this list (the component sorts by char_start when present).
  # Chunk offsets are chosen to be the exact length of their text so that the
  # modal's <mark> region maps to the literal paragraph string.
  @chunks [
    {"S_0010", 1, 0, "High relevance opening paragraph.", "high", true, false, []},
    {"S_0020", 1, 50, "Medium importance middle paragraph.", "medium", false, false, []},
    {"S_0030", 2, 100, "Cited but low relevance trailing.", "low", false, true,
     ["gall_traits.color", "hosts[0].scientific_name"]},
    {"S_0040", 2, 150, "Plain low-relevance background paragraph.", "low", false, false, []}
  ]

  defp prose_fixture do
    Enum.map(@chunks, fn {span_id, page, char_start, text, relevance, mention, cited, fields} ->
      %{
        "span_id" => span_id,
        "page" => page,
        "char_start" => char_start,
        "char_end" => char_start + String.length(text),
        "text" => text,
        "is_mention" => mention,
        "name_occurrences" => if(mention, do: 2, else: 0),
        "is_cited" => cited,
        "cited_by_fields" => fields,
        "relevance" => relevance
      }
    end)
  end

  defp normalized_text_fixture do
    base = String.duplicate(".", 250)

    Enum.reduce(@chunks, base, fn {_id, _page, start, text, _r, _m, _c, _f}, acc ->
      prefix = String.slice(acc, 0, start)
      suffix = String.slice(acc, (start + String.length(text))..-1//1) || ""
      prefix <> text <> suffix
    end)
  end

  describe "initial state — disclosure default and selection" do
    test "default disclosure_level :high shows only high or is_cited chunks", %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      html = render(view)

      assert html =~ "High relevance opening paragraph."
      # Cited (with low relevance) is shown because is_cited == true
      assert html =~ "Cited but low relevance trailing."
      refute html =~ "Medium importance middle paragraph."
      refute html =~ "Plain low-relevance background paragraph."
    end

    test "disclosure_level :medium shows high + medium (plus cited)", %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      html =
        view
        |> element("#workspace-section-description button[phx-value-level=\"medium\"]")
        |> render_click()

      assert html =~ "High relevance opening paragraph."
      assert html =~ "Medium importance middle paragraph."
      assert html =~ "Cited but low relevance trailing."
      refute html =~ "Plain low-relevance background paragraph."
    end

    test "disclosure_level :all shows everything", %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      html =
        view
        |> element("#workspace-section-description button[phx-value-level=\"all\"]")
        |> render_click()

      assert html =~ "High relevance opening paragraph."
      assert html =~ "Medium importance middle paragraph."
      assert html =~ "Cited but low relevance trailing."
      assert html =~ "Plain low-relevance background paragraph."
    end

    test "initial selection includes high-relevance AND is_cited chunks", %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      # Expand to :all so all checkboxes are visible.
      view
      |> element("#workspace-section-description button[phx-value-level=\"all\"]")
      |> render_click()

      html = render(view)

      # S_0010 (high) and S_0030 (cited) checked; S_0020 and S_0040 unchecked.
      assert html =~
               ~r/<input[^>]+phx-value-span-id="S_0010"[^>]+checked/s

      assert html =~
               ~r/<input[^>]+phx-value-span-id="S_0030"[^>]+checked/s

      refute html =~ ~r/<input[^>]+phx-value-span-id="S_0020"[^>]+checked/s
      refute html =~ ~r/<input[^>]+phx-value-span-id="S_0040"[^>]+checked/s
    end

    test "initial draft is concatenation of selected-chunk texts in document order",
         %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      html = render(view)

      expected_draft =
        "High relevance opening paragraph.\n\nCited but low relevance trailing."

      # The draft is rendered into a textarea/div with whitespace-pre-wrap; just
      # assert the literal substring is present in the rendered HTML.
      assert html =~ expected_draft
    end
  end

  describe "toggle behavior" do
    test "clicking an unchecked chunk's checkbox adds it to selection", %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      view
      |> element("#workspace-section-description button[phx-value-level=\"medium\"]")
      |> render_click()

      view
      |> element("#workspace-section-description input[phx-value-span-id=\"S_0020\"]")
      |> render_click()

      html = render(view)

      assert html =~ ~r/<input[^>]+phx-value-span-id="S_0020"[^>]+checked/s
      # Draft now contains medium paragraph text.
      assert html =~ "Medium importance middle paragraph."
    end

    test "clicking a checked chunk's checkbox removes it from selection", %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      view
      |> element("#workspace-section-description input[phx-value-span-id=\"S_0010\"]")
      |> render_click()

      html = render(view)

      refute html =~ ~r/<input[^>]+phx-value-span-id="S_0010"[^>]+checked/s
    end

    test "after toggling while clean, draft is recomputed from new selection",
         %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      # Initial draft preview contains the high paragraph.
      assert draft_preview_text(render(view)) =~ "High relevance opening paragraph."

      # Deselect S_0010 (was checked by default).
      view
      |> element("#workspace-section-description input[phx-value-span-id=\"S_0010\"]")
      |> render_click()

      html = render(view)
      preview = draft_preview_text(html)

      # Draft no longer contains the high paragraph; still contains the cited.
      refute preview =~ "High relevance opening paragraph."
      assert preview =~ "Cited but low relevance trailing."
    end
  end

  describe "edit mode and dirty flow" do
    test "clicking Edit draft toggles to textarea", %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      view
      |> element("#workspace-section-description button[phx-click=\"open_edit\"]")
      |> render_click()

      html = render(view)

      assert html =~ "id=\"workspace-description-draft-textarea\""
    end

    test "update_draft flips draft_dirty true and renders phx-confirm on checkboxes",
         %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      view
      |> element("#workspace-section-description button[phx-click=\"open_edit\"]")
      |> render_click()

      view
      |> element("#workspace-description-draft-textarea")
      |> render_blur(%{"value" => "Curator-written description."})

      html = render(view)

      assert html =~ "Curator-written description."
      assert html =~ ~r/<input[^>]+phx-value-span-id="S_0010"[^>]+phx-confirm=/s
    end

    test "clean checkboxes do NOT carry phx-confirm", %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      html = render(view)

      refute html =~ ~r/<input[^>]+phx-value-span-id="S_0010"[^>]+phx-confirm=/s
    end

    test "regenerate_draft recomputes draft and clears draft_dirty", %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      view
      |> element("#workspace-section-description button[phx-click=\"open_edit\"]")
      |> render_click()

      view
      |> element("#workspace-description-draft-textarea")
      |> render_blur(%{"value" => "Curator-written description."})

      view
      |> element("#workspace-section-description button[phx-click=\"regenerate_draft\"]")
      |> render_click()

      html = render(view)

      refute html =~ "Curator-written description."
      assert html =~ "High relevance opening paragraph."
      # Dirty cleared: phx-confirm gone from checkboxes again.
      refute html =~ ~r/<input[^>]+phx-value-span-id="S_0010"[^>]+phx-confirm=/s
    end
  end

  describe "view-in-context modal" do
    test "modal absent when context_span_id == nil", %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      html = render(view)

      refute html =~ "workspace-description-context-modal"
    end

    test "open_context sets context_span_id and renders modal", %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      view
      |> element(
        ~s(#workspace-section-description button[phx-click="open_context"][phx-value-span-id="S_0010"])
      )
      |> render_click()

      html = render(view)

      assert html =~ "workspace-description-context-modal"
      # Modal header surfaces page number and span id.
      assert html =~ "S_0010"
      assert html =~ "p. 1"
      # Modal body wraps target chunk in a <mark>.
      assert html =~ "<mark>High relevance opening paragraph.</mark>"
    end

    test "close_context clears context_span_id", %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      view
      |> element(
        ~s(#workspace-section-description button[phx-click="open_context"][phx-value-span-id="S_0010"])
      )
      |> render_click()

      # The modal close X button triggers data-cancel via JS.exec, which
      # LiveViewTest cannot follow. Drive the underlying component event by
      # using render_hook against the modal's phx-hook'd <pre>; render_hook
      # dispatches the event to the live_component owning the element.
      view
      |> element("#workspace-description-context-pre")
      |> render_hook("close_context", %{})

      html = render(view)

      refute html =~ "<mark>"
    end
  end

  describe "mode selector" do
    test "mode control hidden when existing_gall == nil", %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      html = render(view)

      refute html =~ "Apply as"
      refute html =~ "phx-value-mode=\"keep\""
    end

    test "mode control visible and defaults to :replace when existing_gall.description present",
         %{conn: conn} do
      view =
        setup_review_with_existing_description(
          conn,
          prose_fixture(),
          normalized_text_fixture(),
          "An existing description text."
        )

      html = render(view)

      assert html =~ "Apply as"
      assert html =~ "phx-value-mode=\"keep\""
      assert html =~ "phx-value-mode=\"append\""
      assert html =~ "phx-value-mode=\"replace\""
      # Default mode is replace — that button should reflect active state.
      assert html =~ ~r/phx-value-mode="replace"[^>]*class="[^"]*bg-white/s
    end

    test "set_mode event updates the mode", %{conn: conn} do
      view =
        setup_review_with_existing_description(
          conn,
          prose_fixture(),
          normalized_text_fixture(),
          "An existing description text."
        )

      view
      |> element("#workspace-section-description button[phx-value-mode=\"keep\"]")
      |> render_click()

      html = render(view)

      assert html =~ ~r/phx-value-mode="keep"[^>]*class="[^"]*bg-white/s
    end
  end

  describe "badges and chips" do
    test "is_mention=true chunks render a mention badge", %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      html = render(view)

      # S_0010 has is_mention=true; the badge text "mention" should appear in
      # its rendered card.
      assert html =~ "mention"
    end

    test "non-empty cited_by_fields renders one chip per field", %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      html = render(view)

      # S_0030 has cited_by_fields = ["gall_traits.color", "hosts[0].scientific_name"]
      assert html =~ "gall_traits.color"
      assert html =~ "hosts[0].scientific_name"
    end

    test "empty cited_by_fields renders no chips for that chunk", %{conn: conn} do
      view = setup_review(conn, prose_fixture(), normalized_text_fixture())

      html = render(view)

      # S_0010 has cited_by_fields = []; we just assert the only cited-by chip
      # text on the page is from S_0030.
      assert html =~ "gall_traits.color"
      refute html =~ "name_occurrences"
    end
  end

  # --- Helpers ---

  # Returns the inner text of the draft preview div (or textarea body) so we
  # can assert on draft content without false-positives from the chunk list.
  defp draft_preview_text(html) do
    case Regex.run(
           ~r/id="workspace-description-draft-preview"[^>]*>(.*?)<\/div>/s,
           html
         ) do
      [_, body] ->
        body

      _ ->
        case Regex.run(
               ~r/id="workspace-description-draft-textarea"[^>]*>(.*?)<\/textarea>/s,
               html
             ) do
          [_, body] -> body
          _ -> ""
        end
    end
  end

  defp setup_review(conn, evidence_prose, normalized_text) do
    reviewer = db_user_fixture("Desc Reviewer")
    source = source_fixture(%{title: "Desc Source"})

    ingestion =
      review_ready_ingestion_fixture(%{
        uploaded_by_id: reviewer.id,
        source_id: source.id,
        normalized_text: normalized_text
      })

    source_ingestion_species_fixture(ingestion, 0, %{
      extracted_name: "Some new gall",
      evidence_prose: evidence_prose
    })

    conn = superadmin_conn(conn, reviewer)
    {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")
    view
  end

  defp setup_review_with_existing_description(
         conn,
         evidence_prose,
         normalized_text,
         existing_description
       ) do
    reviewer = db_user_fixture("Desc Existing Reviewer")
    source = source_fixture(%{title: "Desc Existing Source"})

    # species id 100 exists in the test seed data and is mapped from
    # "Andricus quercuscalifornicus" — the workspace's auto-match logic relies
    # on that.
    {:ok, _} =
      Sources.create_species_source(%{
        species_id: 100,
        source_id: source.id,
        description: existing_description
      })

    ingestion =
      review_ready_ingestion_fixture(%{
        uploaded_by_id: reviewer.id,
        source_id: source.id,
        normalized_text: normalized_text
      })

    source_ingestion_species_fixture(ingestion, 0, %{
      extracted_name: "Andricus quercuscalifornicus",
      evidence_prose: evidence_prose
    })

    conn = superadmin_conn(conn, reviewer)
    {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")
    view
  end

  defp superadmin_conn(conn, db_user) do
    auth0_user = %Auth0User{
      id: db_user.auth0_id,
      email: "superadmin@test.com",
      name: db_user.display_name,
      nickname: db_user.nickname,
      picture: nil,
      roles: ["admin", "superadmin"]
    }

    conn
    |> init_test_session(%{})
    |> put_session(:current_user, auth0_user)
    |> put_session(:db_display_name, db_user.display_name)
  end

  defp db_user_fixture(display_name) do
    {:ok, user} =
      Accounts.create_user(%{
        auth0_id: "auth0|workspace-desc-#{System.unique_integer([:positive])}",
        display_name: display_name
      })

    user
  end

  defp source_fixture(attrs) do
    merged_attrs =
      Map.merge(
        %{
          title: "Source #{System.unique_integer([:positive])}",
          author: "Author",
          pubyear: "2026",
          link: "https://example.com/source",
          citation: "Author. 2026. Source.",
          license: "CC-BY",
          licenselink: "https://creativecommons.org/licenses/by/4.0/"
        },
        attrs
      )

    {:ok, source} = Sources.create_source(merged_attrs)
    source
  end

  defp review_ready_ingestion_fixture(attrs) do
    merged =
      attrs
      |> Map.new()
      |> Map.put_new(:input_type, "pdf")
      |> Map.put_new(:status, "needs_review")
      |> Map.put_new(:processing_stage, "review")

    {:ok, ingestion} = Ingestions.create_source_ingestion(merged)
    ingestion
  end

  defp source_ingestion_species_fixture(source_ingestion, position, attrs) do
    default_payload = %{
      "hosts" => [],
      "traits" => %{},
      "description_evidence" => []
    }

    merged =
      attrs
      |> Map.new()
      |> Map.put_new(:source_ingestion_id, source_ingestion.id)
      |> Map.put_new(:position, position)
      |> Map.put_new(:status, "pending")
      |> Map.put_new(:extracted_authority, "Author")
      |> Map.put_new(:extraction_payload, default_payload)

    {:ok, source_ingestion_species} = Ingestions.create_source_ingestion_species(merged)
    source_ingestion_species
  end
end
