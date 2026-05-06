defmodule GallformersWeb.Admin.IngestionReviewLive.Show do
  use GallformersWeb, :live_view

  alias Gallformers.Accounts
  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.DuplicateResolution
  alias Gallformers.Ingestions
  alias Gallformers.Sources
  alias GallformersWeb.Admin.IngestionReviewLive.Presenter

  @pipeline_stages [
    {:extract, "Extract"},
    {:preprocess, "Preprocess"},
    {:hash_and_dedup, "Hash & Dedup"},
    {:llm_clean, "LLM Clean"},
    {:metadata, "Metadata"},
    {:data_extract, "Data Extract"},
    {:assemble, "Assemble"},
    {:upload, "Upload"}
  ]

  @stage_index @pipeline_stages
               |> Enum.with_index()
               |> Enum.into(%{}, fn {{stage, _label}, idx} -> {Atom.to_string(stage), idx} end)

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:current_user, session["current_user"])
     |> assign(:current_user_db_id, Accounts.db_user_id(session))
     |> assign(:page_title, "Source Ingestion Review")
     |> assign(:review_view, nil)
     |> assign(:selected_source, nil)
     |> assign(:source_search_query, "")
     |> assign(:source_search_results, [])
     |> assign(:source_text, nil)
     |> assign(:source_text_focus, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    ingestion_id = String.to_integer(id)
    socket = load_review_view(socket, ingestion_id)

    if connected?(socket) && socket.assigns.review_view.status == "processing" do
      Broadcaster.subscribe(ingestion_id)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("confirm_duplicate_candidate", %{"id" => id}, socket) do
    with {:ok, reviewed_by_id} <- current_user_db_id(socket),
         {:ok, _source_ingestion} <-
           DuplicateResolution.confirm_duplicate(String.to_integer(id), reviewed_by_id) do
      {:noreply,
       socket
       |> put_flash(:info, "Duplicate confirmed")
       |> reload_review_view()}
    else
      {:error, :missing_db_user, socket} ->
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error_message(changeset))}
    end
  end

  @impl true
  def handle_event("reject_duplicate_candidate", %{"id" => id}, socket) do
    with {:ok, reviewed_by_id} <- current_user_db_id(socket),
         {:ok, _source_ingestion} <-
           DuplicateResolution.reject_duplicate(String.to_integer(id), reviewed_by_id) do
      {:noreply,
       socket
       |> put_flash(:info, "Duplicate candidate rejected")
       |> reload_review_view()}
    else
      {:error, :missing_db_user, socket} ->
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error_message(changeset))}
    end
  end

  @impl true
  def handle_event("promote_ingestion_to_unique", _params, socket) do
    with {:ok, reviewed_by_id} <- current_user_db_id(socket),
         {:ok, _source_ingestion} <-
           DuplicateResolution.promote_to_unique(socket.assigns.review_view.id, reviewed_by_id) do
      {:noreply,
       socket
       |> put_flash(:info, "Marked submission as unique")
       |> reload_review_view()}
    else
      {:error, :missing_db_user, socket} ->
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error_message(changeset))}
    end
  end

  @impl true
  def handle_event("search_sources", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Sources.search_sources(query)
        |> Enum.take(10)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:source_search_query, query)
     |> assign(:source_search_results, results)}
  end

  @impl true
  def handle_event("select_source", %{"id" => id}, socket) do
    source =
      id
      |> parse_integer_param()
      |> Sources.get_source!()

    {:noreply,
     socket
     |> assign(:selected_source, source)
     |> assign(:source_search_query, "")
     |> assign(:source_search_results, [])}
  end

  @impl true
  def handle_event("associate_source", _params, socket) do
    case socket.assigns.selected_source do
      %{id: source_id} ->
        source_ingestion = Ingestions.get_source_ingestion!(socket.assigns.review_view.id)

        case Ingestions.associate_source(source_ingestion, source_id) do
          {:ok, _source_ingestion} ->
            {:noreply,
             socket
             |> put_flash(:info, "Source associated")
             |> reload_review_view()}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, put_flash(socket, :error, changeset_error_message(changeset))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_source_association", _params, socket) do
    if persisted_selected_source?(socket.assigns.review_view, socket.assigns.selected_source) do
      source_ingestion = Ingestions.get_source_ingestion!(socket.assigns.review_view.id)

      case Ingestions.clear_source_association(source_ingestion) do
        {:ok, _source_ingestion} ->
          {:noreply,
           socket
           |> put_flash(:info, "Source association cleared")
           |> reload_review_view()}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, put_flash(socket, :error, changeset_error_message(changeset))}
      end
    else
      {:noreply,
       socket
       |> assign(:selected_source, socket.assigns.review_view.associated_source)
       |> assign(:source_search_query, "")
       |> assign(:source_search_results, [])}
    end
  end

  @impl true
  def handle_event("clear_source_ingestion", _params, socket) do
    case Ingestions.clear_source_ingestion(socket.assigns.review_view.id) do
      {:ok, _source_ingestion} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ingestion cleared")
         |> push_navigate(to: ~p"/admin/ingestion-review")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error_message(changeset))}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed ingestion cleanup failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:stage_complete, _stage}, socket) do
    socket = reload_review_view(socket)

    if terminal_status?(socket.assigns.review_view.status) do
      {:noreply, push_event(socket, "stop_timer", %{})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:error, _stage, _reason}, socket) do
    {:noreply,
     socket
     |> reload_review_view()
     |> push_event("stop_timer", %{})}
  end

  @impl true
  def handle_info({:needs_duplicate_review, _candidates}, socket) do
    {:noreply,
     socket
     |> reload_review_view()
     |> push_event("stop_timer", %{})}
  end

  @impl true
  def handle_info({:review_ready, _ingestion_id}, socket) do
    {:noreply,
     socket
     |> reload_review_view()
     |> push_event("stop_timer", %{})}
  end

  @impl true
  def handle_info({:progress, _stage, _percent}, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <div :if={@review_view} class="space-y-6">
        <.card title="Submission Detail" icon="ph-file-text">
          <div class="space-y-4">
            <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
              <div class="space-y-2">
                <p class="text-sm text-gray-500">Submission</p>
                <h2 class="text-2xl font-semibold text-gf-maroon">
                  {@review_view.display_title}
                </h2>
                <div class="flex flex-wrap gap-2">
                  <.badge variant={status_badge_variant(@review_view.status)}>
                    {status_label(@review_view)}
                  </.badge>
                  <.badge variant="info">
                    {@review_view.counts.duplicate_candidates_pending} pending duplicate candidates
                  </.badge>
                  <.badge variant="info">
                    {@review_view.counts.species_entries_total} extracted gall entries
                  </.badge>
                </div>
              </div>

              <div class="flex items-center gap-3">
                <.button
                  :if={@review_view.clearable?}
                  id="clear-source-ingestion"
                  type="button"
                  variant="danger"
                  phx-click="clear_source_ingestion"
                  data-confirm="Are you sure you want to clear this failed ingestion? This deletes its saved artifacts and cannot be undone."
                >
                  {clear_source_ingestion_label(@review_view)}
                </.button>

                <.button navigate={~p"/admin/ingestion-review"} variant="secondary">
                  Back To Queue
                </.button>
              </div>
            </div>

            <.pipeline_progress
              :if={@review_view.status == "processing"}
              processing_stage={@review_view.processing_stage}
              inserted_at={@review_view.inserted_at}
            />

            <.list>
              <:item title="Input Type">{String.upcase(@review_view.input_type)}</:item>
              <:item title="Stage">{Presenter.processing_stage_label(@review_view)}</:item>
              <:item title="Uploaded">{format_date(@review_view.inserted_at, :short)}</:item>
            </.list>
          </div>
        </.card>

        <.card title="Duplicate Review" icon="ph-copy">
          <div class="space-y-4">
            <.alert
              :if={
                !@review_view.duplicate_review_required? &&
                  @review_view.status == "duplicate_confirmed"
              }
              variant="warning"
            >
              This submission was confirmed as a duplicate of another ingestion and is no longer reviewable.
            </.alert>

            <.alert
              :if={
                !@review_view.duplicate_review_required? &&
                  @review_view.status != "duplicate_confirmed"
              }
              variant="info"
            >
              Duplicate review is complete for this submission.
            </.alert>

            <div :if={@review_view.duplicate_candidates == []} class="text-sm text-gray-500">
              No duplicate candidates were recorded for this submission.
            </div>

            <div
              :for={candidate <- @review_view.duplicate_candidates}
              class="rounded-lg border border-gray-200 p-4 space-y-4"
            >
              <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                <div class="space-y-1">
                  <h3 class="text-lg font-semibold text-gf-maroon">
                    {candidate.candidate_display_title}
                  </h3>
                  <p :if={candidate.candidate_authors != []} class="text-sm text-gray-600">
                    {Enum.join(candidate.candidate_authors, ", ")}
                  </p>
                  <p :if={candidate.candidate_year} class="text-sm text-gray-600">
                    {candidate.candidate_year}
                  </p>
                </div>

                <.badge variant={candidate_status_badge_variant(candidate.status)}>
                  {candidate.status}
                </.badge>
              </div>

              <div class="space-y-2">
                <h4 class="text-sm font-medium text-gray-700">Evidence</h4>

                <div :if={candidate.evidence_rows == []} class="text-sm text-gray-500">
                  No matching evidence details recorded.
                </div>

                <dl :if={candidate.evidence_rows != []} class="space-y-2">
                  <div
                    :for={evidence_row <- candidate.evidence_rows}
                    class="grid gap-1 rounded-md bg-gray-50 px-3 py-2 md:grid-cols-[220px_1fr]"
                  >
                    <dt class="text-sm font-medium text-gray-700">{evidence_row.label}</dt>
                    <dd class="text-sm text-gray-600">{format_evidence_value(evidence_row.value)}</dd>
                  </div>
                </dl>
              </div>

              <div
                :if={@review_view.duplicate_review_required? && candidate.status == "pending"}
                class="flex flex-wrap gap-3"
              >
                <.button
                  id={"confirm-duplicate-candidate-#{candidate.id}"}
                  type="button"
                  variant="warning"
                  phx-click="confirm_duplicate_candidate"
                  phx-value-id={candidate.id}
                >
                  Confirm Duplicate
                </.button>

                <.button
                  id={"reject-duplicate-candidate-#{candidate.id}"}
                  type="button"
                  variant="secondary"
                  phx-click="reject_duplicate_candidate"
                  phx-value-id={candidate.id}
                >
                  Reject Candidate
                </.button>
              </div>
            </div>

            <div :if={@review_view.duplicate_review_required?} class="pt-2">
              <.button
                id="promote-ingestion-to-unique"
                type="button"
                variant="primary"
                phx-click="promote_ingestion_to_unique"
              >
                Promote To Unique
              </.button>
            </div>
          </div>
        </.card>

        <.card title="Source Review" icon="ph-book-open">
          <div
            :if={source_review_locked_for_duplicate?(@review_view)}
            id="source-review-locked"
            class="space-y-3"
          >
            <.alert variant="warning">
              Resolve duplicate review to enable source mapping.
            </.alert>
            <button type="button" class="gf-btn gf-btn-secondary" disabled>
              Create Or Link Source
            </button>
          </div>

          <div :if={!source_review_locked_for_duplicate?(@review_view)} class="space-y-6">
            <div class="space-y-3">
              <h3 class="text-sm font-semibold text-gray-700">Submission Metadata</h3>

              <.list>
                <:item title="Title">{@review_view.display_title}</:item>
                <:item title="Authors">{authors_text(@review_view.authors)}</:item>
                <:item title="Year">{metadata_value(@review_view.publication_year)}</:item>
                <:item title="DOI">{metadata_value(@review_view.doi)}</:item>
              </.list>
            </div>

            <.alert
              :if={!@review_view.source_review_unlocked? && @review_view.status == "processing"}
              variant="info"
            >
              Source review unlocks after automated processing completes.
            </.alert>

            <.alert
              :if={
                !@review_view.source_review_unlocked? && @review_view.status == "duplicate_confirmed"
              }
              variant="warning"
            >
              This submission is a confirmed duplicate, so source review is no longer applicable.
            </.alert>

            <div :if={@review_view.source_review_unlocked?} class="space-y-4 border-t pt-4">
              <div class="flex flex-col gap-3 xl:flex-row xl:items-end xl:justify-between">
                <div class="flex-1">
                  <.typeahead
                    id="source-picker"
                    label="Match To Existing Source"
                    placeholder="Search sources by title or author..."
                    query={@source_search_query}
                    results={@source_search_results}
                    selected={@selected_source}
                    search_event="search_sources"
                    select_event="select_source"
                    clear_event="clear_source_association"
                    display_fn={&source_display/1}
                  >
                    <:result :let={source}>
                      <div class="font-medium text-gray-900">{source.title}</div>
                      <div class="text-sm text-gray-600">
                        {source.author} ({source.pubyear})
                      </div>
                    </:result>
                  </.typeahead>
                </div>

                <.link
                  href={~p"/admin/sources/new"}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="gf-btn gf-btn-secondary"
                >
                  Create New Source
                </.link>
              </div>

              <div
                :if={@selected_source}
                id="selected-source-summary"
                class="rounded-lg border border-gray-200 bg-gray-50 p-4 space-y-1"
              >
                <div class="font-medium text-gray-900">{source_display(@selected_source)}</div>
                <div class="text-sm text-gray-600">{source_details(@selected_source)}</div>
                <p
                  :if={persisted_selected_source?(@review_view, @selected_source)}
                  class="text-sm text-gray-500"
                >
                  This source association is already persisted.
                </p>
                <p
                  :if={!persisted_selected_source?(@review_view, @selected_source)}
                  class="text-sm text-gray-500"
                >
                  This selection is not persisted yet. Use Associate Source to save it.
                </p>
              </div>

              <div class="flex flex-wrap gap-3">
                <.button
                  :if={show_associate_source_action?(@review_view, @selected_source)}
                  id="associate-source"
                  type="button"
                  variant="primary"
                  phx-click="associate_source"
                >
                  Associate Source
                </.button>
              </div>

              <details
                :if={@source_text}
                id="full-source-text-panel"
                class="rounded-lg border border-gray-200"
              >
                <summary class="cursor-pointer px-4 py-3 text-sm font-medium text-gray-900">
                  Full Extracted Text
                </summary>
                <div class="border-t border-gray-200 px-4 py-4 space-y-3">
                  <div
                    :if={@source_text_focus}
                    class="rounded-md bg-amber-50 px-3 py-2 text-sm text-amber-900"
                  >
                    Focused fragment: {@source_text_focus}
                  </div>
                  <pre class="max-h-96 overflow-auto whitespace-pre-wrap text-sm text-gray-700">{@source_text}</pre>
                </div>
              </details>
            </div>
          </div>
        </.card>

        <.card title="Gall Review" icon="gf-gall">
          <div
            :if={species_review_locked_for_duplicate?(@review_view)}
            id="species-review-locked"
            class="space-y-4"
          >
            <.alert variant="warning">
              Duplicate review must be resolved before gall review.
            </.alert>

            <.table
              :if={@review_view.species_entries != []}
              id="species-review-locked-table"
              rows={@review_view.species_entries}
              row_id={&"species-entry-#{&1.id}"}
            >
              <:col :let={entry} label="Gall">
                <div class="space-y-1">
                  <div class="font-medium">{entry.extracted_name || "Unnamed gall"}</div>
                  <div :if={entry.extracted_authority} class="text-sm text-gray-500">
                    {entry.extracted_authority}
                  </div>
                </div>
              </:col>
              <:col :let={entry} label="Status">{entry.status}</:col>
            </.table>
          </div>

          <div :if={!species_review_locked_for_duplicate?(@review_view)} class="space-y-4">
            <div class="flex flex-wrap gap-2">
              <.badge variant="info">
                {@review_view.counts.species_entries_pending} of {@review_view.counts.species_entries_total} galls remaining
              </.badge>
              <.badge variant="info">
                {@review_view.counts.species_entries_resolved} reviewed
              </.badge>
            </div>

            <div :if={@review_view.species_entries == []} class="text-sm text-gray-500">
              No extracted gall entries are ready yet.
            </div>

            <.alert
              :if={@review_view.species_entries != [] && !@review_view.species_review_unlocked?}
              id="species-review-source-locked"
              variant="warning"
            >
              Associate a source to enable gall review.
            </.alert>

            <.alert
              :if={@review_view.species_entries != [] && @review_view.species_review_unlocked?}
              variant="info"
            >
              Source attached. Proceed to the species review workspace to curate gall entries.
            </.alert>

            <div
              :if={@review_view.species_entries != []}
              id="species-review-list"
              class="space-y-2"
            >
              <details
                :for={entry <- @review_view.species_entries}
                id={"species-entry-#{entry.id}"}
                class="rounded-lg border border-gray-200"
              >
                <summary class="cursor-pointer px-4 py-3 flex items-center justify-between gap-3">
                  <div class="flex items-center gap-3">
                    <span class="text-sm text-gray-400">{entry.position}</span>
                    <div>
                      <div class="font-medium text-gray-900">
                        {entry.extracted_name || "Unnamed gall"}
                      </div>
                      <div :if={entry.extracted_authority} class="text-sm text-gray-500">
                        {entry.extracted_authority}
                      </div>
                    </div>
                  </div>
                  <div class="flex items-center gap-2">
                    <span :if={entry.mapped_species_name} class="text-sm text-gray-600">
                      {entry.mapped_species_name}
                    </span>
                    <.badge variant="info">{entry.status}</.badge>
                  </div>
                </summary>
                <div class="border-t border-gray-200 px-4 py-3 space-y-2 text-sm">
                  <div :if={entry.extracted_hosts != []} class="space-y-1">
                    <div class="font-medium text-gray-700">Hosts</div>
                    <div :for={host <- entry.extracted_hosts} class="text-gray-600">
                      {host.name}<span :if={host.authority} class="text-gray-400">
                        {" "}{host.authority}
                      </span>
                    </div>
                  </div>
                  <div :if={entry.extracted_trait_names != []} class="space-y-1">
                    <div class="font-medium text-gray-700">Traits</div>
                    <div class="text-gray-600">
                      {Enum.join(entry.extracted_trait_names, ", ")}
                    </div>
                  </div>
                  <div :if={entry.extracted_aliases != []} class="space-y-1">
                    <div class="font-medium text-gray-700">Aliases</div>
                    <div class="text-gray-600">
                      {Enum.join(entry.extracted_aliases, ", ")}
                    </div>
                  </div>
                  <div
                    :if={
                      entry.extracted_hosts == [] && entry.extracted_trait_names == [] &&
                        entry.extracted_aliases == []
                    }
                    class="text-gray-500"
                  >
                    No extraction summary available.
                  </div>
                </div>
              </details>
            </div>

            <.link
              :if={@review_view.species_review_unlocked?}
              navigate={~p"/admin/ingestion-review/#{@review_view.id}/review"}
              data-role="proceed-to-review"
              class="gf-btn gf-btn-primary inline-block"
            >
              Proceed to Species Review
            </.link>
          </div>
        </.card>
      </div>
    </Layouts.admin>
    """
  end

  defp load_review_view(socket, source_ingestion_id) do
    review_view = Presenter.source_ingestion_review_view!(source_ingestion_id)

    source_text =
      case Ingestions.source_ingestion_full_text(source_ingestion_id) do
        {:ok, text} -> text
        _ -> nil
      end

    socket
    |> assign(:review_view, review_view)
    |> assign(:page_title, review_view.display_title)
    |> assign(:selected_source, review_view.associated_source)
    |> assign(:source_search_query, "")
    |> assign(:source_search_results, [])
    |> assign(:source_text, source_text)
    |> assign(:source_text_focus, nil)
  end

  defp reload_review_view(socket) do
    load_review_view(socket, socket.assigns.review_view.id)
  end

  defp current_user_db_id(socket) do
    case socket.assigns.current_user_db_id do
      user_id when is_integer(user_id) ->
        {:ok, user_id}

      _ ->
        {:error, :missing_db_user,
         put_flash(
           socket,
           :error,
           "You need a database-backed profile to review submissions."
         )}
    end
  end

  defp status_label(review_view), do: Presenter.queue_status_label(review_view)
  defp clear_source_ingestion_label(%{clearability: :abandoned}), do: "Clear Abandoned Ingestion"
  defp clear_source_ingestion_label(_review_view), do: "Clear Failed Ingestion"

  defp status_badge_variant("needs_duplicate_review"), do: "warning"
  defp status_badge_variant("duplicate_confirmed"), do: "warning"
  defp status_badge_variant("failed"), do: "warning"
  defp status_badge_variant("complete"), do: "success"
  defp status_badge_variant(_), do: "info"

  defp candidate_status_badge_variant("confirmed"), do: "success"
  defp candidate_status_badge_variant("auto_confirmed"), do: "success"
  defp candidate_status_badge_variant("rejected"), do: "info"
  defp candidate_status_badge_variant(_), do: "warning"

  defp format_evidence_value(value) when is_binary(value), do: value
  defp format_evidence_value(value) when is_integer(value), do: Integer.to_string(value)

  defp format_evidence_value(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 2)

  defp format_evidence_value(value), do: inspect(value)

  defp metadata_value(nil), do: "None"
  defp metadata_value(""), do: "None"
  defp metadata_value(value), do: to_string(value)

  defp parse_integer_param(value) when is_integer(value), do: value
  defp parse_integer_param(value) when is_binary(value), do: String.to_integer(value)

  defp authors_text([]), do: "None"
  defp authors_text(authors) when is_list(authors), do: Enum.join(authors, ", ")

  defp source_display(source), do: source.title

  defp source_details(source) do
    [source.author, source.pubyear]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp persisted_selected_source?(review_view, %{id: selected_source_id}) do
    review_view.source_id == selected_source_id
  end

  defp persisted_selected_source?(_, _), do: false

  defp show_associate_source_action?(review_view, %{id: selected_source_id}) do
    review_view.source_review_unlocked? and review_view.source_id != selected_source_id
  end

  defp show_associate_source_action?(_, _), do: false

  attr :processing_stage, :string, required: true
  attr :inserted_at, :any, required: true

  defp pipeline_progress(assigns) do
    completed_index = @stage_index[assigns.processing_stage]
    stages = stage_statuses(completed_index)
    assigns = assign(assigns, :stages, stages)

    ~H"""
    <div class="space-y-3">
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-medium text-gray-500">Pipeline Progress</h3>
        <div
          id="elapsed-timer"
          phx-hook="ElapsedTimer"
          data-started-at={DateTime.to_iso8601(@inserted_at)}
          class="text-sm font-mono text-gray-500"
        >
          <span data-timer-display></span>
        </div>
      </div>

      <div class="flex items-center gap-1">
        <div
          :for={{stage_key, label, status} <- @stages}
          class="flex-1 flex flex-col items-center gap-1"
        >
          <div class={[
            "h-2 w-full rounded-full",
            stage_bar_class(status)
          ]} />
          <span class={[
            "text-[10px] leading-tight text-center",
            stage_label_class(status)
          ]}>
            {label}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp stage_statuses(nil) do
    Enum.map(@pipeline_stages, fn {key, label} -> {key, label, :running} end)
    |> List.update_at(0, fn {key, label, _} -> {key, label, :running} end)
  end

  defp stage_statuses(completed_index) do
    @pipeline_stages
    |> Enum.with_index()
    |> Enum.map(fn {{key, label}, idx} ->
      cond do
        idx <= completed_index -> {key, label, :completed}
        idx == completed_index + 1 -> {key, label, :running}
        true -> {key, label, :pending}
      end
    end)
  end

  defp stage_bar_class(:completed), do: "bg-green-500"
  defp stage_bar_class(:running), do: "bg-amber-400 animate-pulse"
  defp stage_bar_class(:pending), do: "bg-gray-200"

  defp stage_label_class(:completed), do: "text-green-700 font-medium"
  defp stage_label_class(:running), do: "text-amber-700 font-medium"
  defp stage_label_class(:pending), do: "text-gray-400"

  defp terminal_status?("needs_review"), do: true
  defp terminal_status?("complete"), do: true
  defp terminal_status?("failed"), do: true
  defp terminal_status?("duplicate_confirmed"), do: true
  defp terminal_status?("needs_duplicate_review"), do: true
  defp terminal_status?(_), do: false

  defp source_review_locked_for_duplicate?(review_view),
    do: review_view.duplicate_review_required?

  defp species_review_locked_for_duplicate?(review_view),
    do: review_view.duplicate_review_required?

  defp changeset_error_message(changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, error} -> "#{field} #{translate_error(error)}" end)
  end
end
