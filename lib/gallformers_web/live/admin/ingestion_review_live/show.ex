defmodule GallformersWeb.Admin.IngestionReviewLive.Show do
  use GallformersWeb, :live_view

  import GallformersWeb.Admin.FormComponents, only: [alias_collision_warning: 1]

  alias Gallformers.Accounts
  alias Gallformers.Galls
  alias Gallformers.IngestionPipeline.DuplicateResolution
  alias Gallformers.Ingestions
  alias Gallformers.Sources
  alias Gallformers.Species
  alias GallformersWeb.Admin.IngestionReviewLive.Presenter

  @detachable_options [
    {"Unknown", "unknown"},
    {"Integral", "integral"},
    {"Detachable", "detachable"},
    {"Both", "both"}
  ]

  @trait_filter_keys %{
    "color" => :colors,
    "shape" => :shapes,
    "texture" => :textures,
    "walls" => :walls,
    "cells" => :cells,
    "alignment" => :alignments,
    "plant_part" => :plant_parts,
    "form" => :forms,
    "season" => :seasons,
    "detachable" => :detachable
  }

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:current_user, session["current_user"])
     |> assign(:current_user_db_id, resolve_current_user_db_id(session["current_user"]))
     |> assign(:page_title, "Source Ingestion Review")
     |> assign(:review_view, nil)
     |> assign(:selected_source, nil)
     |> assign(:source_search_query, "")
     |> assign(:source_search_results, [])
     |> assign(:filter_options, Galls.get_all_filter_options())
     |> assign(:workspace, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    {:noreply, load_review_view(socket, String.to_integer(id))}
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
  def handle_event("open_gall_review_workspace", %{"id" => id}, socket) do
    if socket.assigns.review_view.species_review_unlocked? do
      workspace =
        id
        |> parse_integer_param()
        |> Ingestions.source_ingestion_species_review_workspace!()
        |> build_workspace_state()

      {:noreply, assign(socket, :workspace, workspace)}
    else
      {:noreply, put_flash(socket, :error, "Associate a source before opening gall review.")}
    end
  end

  @impl true
  def handle_event("close_gall_review_workspace", _params, socket) do
    {:noreply, assign(socket, :workspace, nil)}
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
  def handle_event("change_gall_review_workspace", %{"workspace" => params}, socket) do
    {:noreply, update_workspace_assign(socket, params)}
  end

  @impl true
  def handle_event("search_workspace_species", %{"value" => query}, socket) do
    {:noreply, update_workspace_species_search(socket, query)}
  end

  @impl true
  def handle_event("select_workspace_species", %{"id" => id}, socket) do
    species = Species.get_species!(parse_integer_param(id))

    {:noreply,
     update_workspace(socket, fn workspace ->
       workspace
       |> put_in([:species_review, :selected_species], species_summary(species))
       |> put_in([:species_review, :species_id], species.id)
       |> put_in([:species_review, :search_query], "")
       |> put_in([:species_review, :search_results], [])
       |> maybe_default_species_review_decision("mapped")
     end)}
  end

  @impl true
  def handle_event("clear_workspace_species", _params, socket) do
    {:noreply,
     update_workspace(socket, fn workspace ->
       workspace
       |> put_in([:species_review, :selected_species], nil)
       |> put_in([:species_review, :species_id], nil)
       |> put_in([:species_review, :search_query], "")
       |> put_in([:species_review, :search_results], [])
     end)}
  end

  @impl true
  def handle_event("toggle_trait_value", %{"value" => encoded_value}, socket) do
    {:noreply, toggle_workspace_trait_value(socket, encoded_value)}
  end

  @impl true
  def handle_event("save_gall_review_workspace", %{"workspace" => params}, socket) do
    case current_user_db_id(socket) do
      {:ok, reviewed_by_id} ->
        socket = update_workspace_assign(socket, params)
        workspace = socket.assigns.workspace
        source_ingestion_species = Ingestions.get_source_ingestion_species!(workspace.id)

        case Ingestions.update_source_ingestion_species_review(
               source_ingestion_species,
               workspace_update_attrs(workspace, params),
               reviewed_by_id
             ) do
          {:ok, _source_ingestion_species} ->
            finalize_workspace_save(
              socket,
              workspace,
              source_ingestion_species.source_ingestion_id
            )

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, put_flash(socket, :error, changeset_error_message(changeset))}
        end

      {:error, :missing_db_user, socket} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("search_workspace_host:" <> host_index, %{"value" => query}, socket) do
    {:noreply, update_workspace_host_search(socket, parse_integer_param(host_index), query)}
  end

  @impl true
  def handle_event("select_workspace_host:" <> host_index, %{"id" => id}, socket) do
    species = Species.get_species!(parse_integer_param(id))
    host_index = parse_integer_param(host_index)

    {:noreply,
     update_workspace(socket, fn workspace ->
       update_in(workspace.host_reviews, fn host_reviews ->
         Enum.map(host_reviews, fn host_review ->
           if host_review.index == host_index do
             host_review
             |> Map.put(:selected_species, species_summary(species))
             |> Map.put(:species_id, species.id)
             |> Map.put(:decision, "mapped")
             |> Map.put(:search_query, "")
             |> Map.put(:search_results, [])
           else
             host_review
           end
         end)
       end)
     end)}
  end

  @impl true
  def handle_event("clear_workspace_host:" <> host_index, _params, socket) do
    host_index = parse_integer_param(host_index)

    {:noreply,
     update_workspace(socket, fn workspace ->
       update_in(workspace.host_reviews, fn host_reviews ->
         Enum.map(host_reviews, fn host_review ->
           if host_review.index == host_index do
             host_review
             |> Map.put(:selected_species, nil)
             |> Map.put(:species_id, nil)
             |> Map.put(:decision, "unresolved")
             |> Map.put(:search_query, "")
             |> Map.put(:search_results, [])
           else
             host_review
           end
         end)
       end)
     end)}
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
              Gall rows are now unlocked and can be reviewed one at a time in the workspace.
            </.alert>

            <.table
              :if={@review_view.species_entries != []}
              id="species-review-table"
              rows={@review_view.species_entries}
              row_id={&"species-entry-#{&1.id}"}
            >
              <:col :let={entry} label="#">
                {entry.position}
              </:col>
              <:col :let={entry} label="Extracted Gall">
                <div class="space-y-1">
                  <div class="font-medium">{entry.extracted_name || "Unnamed gall"}</div>
                  <div :if={entry.extracted_authority} class="text-sm text-gray-500">
                    {entry.extracted_authority}
                  </div>
                </div>
              </:col>
              <:col :let={entry} label="Mapped Species">
                {entry.mapped_species_name || "Unmapped"}
              </:col>
              <:col :let={entry} label="Hosts">{entry.host_count}</:col>
              <:col :let={entry} label="Status">{entry.status}</:col>
              <:action :let={entry}>
                <.button
                  :if={@review_view.species_review_unlocked?}
                  id={"review-species-entry-#{entry.id}"}
                  type="button"
                  size="sm"
                  variant="secondary"
                  phx-click="open_gall_review_workspace"
                  phx-value-id={entry.id}
                >
                  Review Gall
                </.button>
              </:action>
            </.table>
          </div>
        </.card>

        <.modal
          :if={@workspace}
          id="gall-review-workspace-modal"
          show
          on_cancel={Phoenix.LiveView.JS.push("close_gall_review_workspace")}
          class="max-w-5xl"
        >
          <:header>
            Review Gall {@workspace.position}: {@workspace.extracted_name || "Unnamed gall"}
          </:header>

          <:body>
            <form
              id="gall-review-workspace-form"
              phx-change="change_gall_review_workspace"
              phx-submit="save_gall_review_workspace"
              class="space-y-6"
            >
              <input type="hidden" name="workspace[id]" value={@workspace.id} />

              <div class="grid gap-6 xl:grid-cols-[minmax(0,1.2fr)_minmax(0,1fr)]">
                <div class="space-y-6">
                  <section class="space-y-4">
                    <div>
                      <h3 class="text-base font-semibold text-gray-900">Species Review</h3>
                      <p class="text-sm text-gray-500">
                        Confirm the extracted gall against an existing gall species or defer it for later.
                      </p>
                    </div>

                    <.alias_collision_warning collisions={@workspace.species_alias_collisions} />

                    <div class="rounded-lg border border-gray-200 bg-gray-50 p-4 space-y-4">
                      <div class="grid gap-3 md:grid-cols-2">
                        <div>
                          <div class="text-xs font-medium uppercase tracking-wide text-gray-500">
                            Extracted Name
                          </div>
                          <div class="text-sm text-gray-900">
                            {@workspace.extracted_name || "Unnamed gall"}
                          </div>
                        </div>
                        <div>
                          <div class="text-xs font-medium uppercase tracking-wide text-gray-500">
                            Authority
                          </div>
                          <div class="text-sm text-gray-900">
                            {metadata_value(@workspace.extracted_authority)}
                          </div>
                        </div>
                      </div>

                      <.radio_group
                        id="workspace-species-decision"
                        name="workspace[species_review][decision]"
                        label="Decision"
                        value={@workspace.species_review.decision}
                        options={[
                          %{value: "mapped", label: "Map to existing species"},
                          %{value: "skip", label: "Skip for later"}
                        ]}
                      />

                      <div :if={@workspace.species_review.decision != "skip"} class="space-y-3">
                        <.typeahead
                          id="workspace-species-picker"
                          label="Species"
                          placeholder="Search existing gall species..."
                          query={@workspace.species_review.search_query}
                          results={@workspace.species_review.search_results}
                          selected={@workspace.species_review.selected_species}
                          search_event="search_workspace_species"
                          select_event="select_workspace_species"
                          clear_event="clear_workspace_species"
                          display_fn={& &1.name}
                        >
                          <:result :let={species}>
                            <div class="font-medium text-gray-900">{species.name}</div>
                            <div class="text-sm text-gray-600">{species.taxoncode}</div>
                          </:result>
                        </.typeahead>
                      </div>

                      <.input
                        id="workspace-species-notes"
                        name="workspace[species_review][notes]"
                        type="textarea"
                        label="Reviewer Notes"
                        rows="3"
                        value={@workspace.species_review.notes}
                      />
                    </div>
                  </section>

                  <section class="space-y-4">
                    <div>
                      <h3 class="text-base font-semibold text-gray-900">Host Review</h3>
                      <p class="text-sm text-gray-500">
                        Review extracted host mentions without writing host associations into the taxonomy yet.
                      </p>
                    </div>

                    <div :if={@workspace.host_reviews == []} class="text-sm text-gray-500">
                      No host mentions were extracted for this gall.
                    </div>

                    <div
                      :for={host_review <- @workspace.host_reviews}
                      id={"host-review-#{host_review.index}"}
                      class="rounded-lg border border-gray-200 p-4 space-y-4"
                    >
                      <input
                        type="hidden"
                        name={"workspace[host_reviews][#{host_review.index}][extracted_name]"}
                        value={host_review.extracted_name || ""}
                      />
                      <input
                        type="hidden"
                        name={"workspace[host_reviews][#{host_review.index}][extracted_authority]"}
                        value={host_review.extracted_authority || ""}
                      />

                      <div class="grid gap-3 md:grid-cols-2">
                        <div>
                          <div class="text-xs font-medium uppercase tracking-wide text-gray-500">
                            Extracted Host
                          </div>
                          <div class="text-sm text-gray-900">{host_review.extracted_name}</div>
                        </div>
                        <div>
                          <div class="text-xs font-medium uppercase tracking-wide text-gray-500">
                            Authority
                          </div>
                          <div class="text-sm text-gray-900">
                            {metadata_value(host_review.extracted_authority)}
                          </div>
                        </div>
                      </div>

                      <.radio_group
                        id={"host-review-decision-#{host_review.index}"}
                        name={"workspace[host_reviews][#{host_review.index}][decision]"}
                        label="Decision"
                        value={host_review.decision}
                        options={[
                          %{value: "mapped", label: "Map to existing host"},
                          %{value: "unresolved", label: "Leave unresolved"},
                          %{value: "skip", label: "Skip"}
                        ]}
                      />

                      <div :if={host_review.decision == "mapped"} class="space-y-3">
                        <.typeahead
                          id={"host-review-picker-#{host_review.index}"}
                          label="Host Species"
                          placeholder="Search existing host species..."
                          query={host_review.search_query}
                          results={host_review.search_results}
                          selected={host_review.selected_species}
                          search_event={"search_workspace_host:#{host_review.index}"}
                          select_event={"select_workspace_host:#{host_review.index}"}
                          clear_event={"clear_workspace_host:#{host_review.index}"}
                          display_fn={& &1.name}
                        >
                          <:result :let={species}>
                            <div class="font-medium text-gray-900">{species.name}</div>
                            <div class="text-sm text-gray-600">{species.taxoncode}</div>
                          </:result>
                        </.typeahead>
                      </div>
                    </div>
                  </section>
                </div>

                <div class="space-y-6">
                  <section class="space-y-4">
                    <div>
                      <h3 class="text-base font-semibold text-gray-900">Trait Review</h3>
                      <p class="text-sm text-gray-500">
                        Use the extracted evidence and canonical vocab options to capture the reviewed trait values.
                      </p>
                    </div>

                    <div :if={@workspace.trait_reviews == []} class="text-sm text-gray-500">
                      No structured traits were extracted for this gall.
                    </div>

                    <div
                      :for={trait_review <- @workspace.trait_reviews}
                      id={"trait-review-#{trait_review.name}"}
                      class="rounded-lg border border-gray-200 p-4 space-y-3"
                    >
                      <div class="flex flex-col gap-1">
                        <h4 class="font-medium text-gray-900">{trait_label(trait_review.name)}</h4>
                        <p class="text-sm text-gray-500">
                          Suggested: {trait_suggested_text(trait_review)}
                        </p>
                        <p class="text-sm text-gray-500">
                          Evidence: {trait_evidence_text(trait_review)}
                        </p>
                      </div>

                      <.multi_select
                        id={"trait-values-#{trait_review.name}"}
                        label="Selected Values"
                        options={workspace_trait_options(@filter_options, trait_review)}
                        selected={workspace_trait_selected_values(trait_review)}
                        on_toggle="toggle_trait_value"
                      />
                    </div>
                  </section>

                  <section class="space-y-4">
                    <div>
                      <h3 class="text-base font-semibold text-gray-900">Description Review</h3>
                      <p class="text-sm text-gray-500">
                        Edit the persisted description prose directly. Saving marks whether the prose changed during review.
                      </p>
                    </div>

                    <div
                      :if={@workspace.description_evidence != []}
                      class="rounded-lg border border-gray-200 bg-gray-50 p-4 space-y-2"
                    >
                      <div class="text-xs font-medium uppercase tracking-wide text-gray-500">
                        Extracted Evidence
                      </div>
                      <p
                        :for={evidence <- @workspace.description_evidence}
                        class="text-sm text-gray-700"
                      >
                        {evidence}
                      </p>
                    </div>

                    <.input
                      id="workspace-description-prose"
                      name="workspace[description_prose]"
                      type="textarea"
                      label="Reviewed Description"
                      rows="10"
                      value={@workspace.description_prose}
                    />
                  </section>
                </div>
              </div>
            </form>
          </:body>

          <:footer>
            <div class="flex flex-wrap justify-end gap-3">
              <.button
                type="button"
                variant="secondary"
                phx-click="close_gall_review_workspace"
              >
                Close
              </.button>
              <.button
                type="submit"
                form="gall-review-workspace-form"
                name="workspace[action]"
                value="save"
                variant="secondary"
              >
                Save Review
              </.button>
              <.button
                type="submit"
                form="gall-review-workspace-form"
                name="workspace[action]"
                value="complete"
                variant="primary"
              >
                Mark Complete
              </.button>
            </div>
          </:footer>
        </.modal>
      </div>
    </Layouts.admin>
    """
  end

  defp load_review_view(socket, source_ingestion_id) do
    review_view = Presenter.source_ingestion_review_view!(source_ingestion_id)

    socket
    |> assign(:review_view, review_view)
    |> assign(:page_title, review_view.display_title)
    |> assign(:selected_source, review_view.associated_source)
    |> assign(:source_search_query, "")
    |> assign(:source_search_results, [])
    |> assign(:workspace, nil)
  end

  defp reload_review_view(socket) do
    load_review_view(socket, socket.assigns.review_view.id)
  end

  defp finalize_workspace_save(socket, workspace, source_ingestion_id) do
    case Ingestions.maybe_complete_source_ingestion_review(source_ingestion_id) do
      {:ok, source_ingestion} ->
        reloaded_workspace =
          workspace.id
          |> Ingestions.source_ingestion_species_review_workspace!()
          |> build_workspace_state()

        socket = reload_review_view(socket)

        {:noreply,
         socket
         |> put_flash(
           :info,
           workspace_saved_message(reloaded_workspace.status, source_ingestion.status)
         )
         |> assign(:workspace, reloaded_workspace)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error_message(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to finalize review: #{inspect(reason)}")}
    end
  end

  defp update_workspace(socket, fun) do
    case socket.assigns.workspace do
      nil -> socket
      workspace -> assign(socket, :workspace, fun.(workspace))
    end
  end

  defp update_workspace_assign(socket, params) do
    update_workspace(socket, &merge_workspace_params(&1, params))
  end

  defp update_workspace_species_search(socket, query) do
    results =
      if String.length(query) >= 2 do
        Species.search_species_by_name(query, "gall", 10)
      else
        []
      end

    update_workspace(socket, fn workspace ->
      workspace
      |> put_in([:species_review, :search_query], query)
      |> put_in([:species_review, :search_results], results)
    end)
  end

  defp update_workspace_host_search(socket, host_index, query) do
    results =
      if String.length(query) >= 2 do
        Species.search_species_by_name(query, "plant", 10)
      else
        []
      end

    update_workspace(socket, fn workspace ->
      update_in(
        workspace.host_reviews,
        &update_host_review_search(&1, host_index, query, results)
      )
    end)
  end

  defp toggle_workspace_trait_value(socket, encoded_value) do
    update_workspace(socket, fn workspace ->
      case decode_trait_value(encoded_value) do
        {trait_name, value} ->
          update_in(workspace.trait_reviews, &toggle_trait_review_value(&1, trait_name, value))

        :error ->
          workspace
      end
    end)
  end

  defp build_workspace_state(workspace_view) do
    %{
      id: workspace_view.id,
      source_ingestion_id: workspace_view.source_ingestion_id,
      position: workspace_view.position,
      extracted_name: workspace_view.extracted_name,
      extracted_authority: workspace_view.extracted_authority,
      status: workspace_view.status,
      description_prose: workspace_view.description_prose,
      description_evidence: workspace_view.description_evidence,
      species_alias_collisions:
        Species.find_species_with_alias(workspace_view.extracted_name || ""),
      species_review:
        workspace_view.species_review
        |> Map.put(:search_query, "")
        |> Map.put(:search_results, []),
      host_reviews:
        Enum.map(workspace_view.host_reviews, fn host_review ->
          host_review
          |> Map.put(:search_query, "")
          |> Map.put(:search_results, [])
        end),
      trait_reviews: workspace_view.trait_reviews
    }
  end

  defp merge_workspace_params(workspace, params) do
    species_review_params = nested_param(params, "species_review", %{})
    host_review_params = normalize_indexed_form_values(nested_param(params, "host_reviews", %{}))

    species_review =
      workspace.species_review
      |> Map.put(
        :decision,
        nested_param(species_review_params, "decision", workspace.species_review.decision)
      )
      |> Map.put(
        :notes,
        nested_param(species_review_params, "notes", workspace.species_review.notes)
      )
      |> normalize_species_review_selection()

    host_reviews =
      Enum.map(workspace.host_reviews, fn host_review ->
        params_for_host =
          Enum.find(host_review_params, %{}, fn host_review_param ->
            parse_integer_param(
              nested_param(host_review_param, "index", Integer.to_string(host_review.index))
            ) ==
              host_review.index
          end)

        host_review
        |> Map.put(
          :decision,
          nested_param(params_for_host, "decision", host_review.decision)
        )
        |> normalize_host_review_selection()
      end)

    workspace
    |> Map.put(:species_review, species_review)
    |> Map.put(:host_reviews, host_reviews)
    |> Map.put(
      :description_prose,
      nested_param(params, "description_prose", workspace.description_prose)
    )
  end

  defp normalize_species_review_selection(species_review) do
    if species_review.decision == "skip" do
      species_review
      |> Map.put(:species_id, nil)
      |> Map.put(:selected_species, nil)
    else
      species_review
    end
  end

  defp normalize_host_review_selection(host_review) do
    if host_review.decision == "mapped" do
      host_review
    else
      host_review
      |> Map.put(:species_id, nil)
      |> Map.put(:selected_species, nil)
    end
  end

  defp maybe_default_species_review_decision(workspace, decision) do
    case workspace.species_review.decision do
      nil -> put_in(workspace, [:species_review, :decision], decision)
      "" -> put_in(workspace, [:species_review, :decision], decision)
      _ -> workspace
    end
  end

  defp workspace_update_attrs(workspace, params) do
    %{
      "action" => nested_param(params, "action", "save"),
      "description_prose" => workspace.description_prose,
      "species_review" => %{
        "decision" => workspace.species_review.decision,
        "species_id" => workspace.species_review.species_id,
        "notes" => workspace.species_review.notes
      },
      "host_reviews" =>
        Enum.into(workspace.host_reviews, %{}, fn host_review ->
          {
            Integer.to_string(host_review.index),
            %{
              "index" => host_review.index,
              "extracted_name" => host_review.extracted_name,
              "extracted_authority" => host_review.extracted_authority,
              "decision" => host_review.decision,
              "species_id" => host_review.species_id
            }
          }
        end),
      "trait_reviews" =>
        Enum.into(workspace.trait_reviews, %{}, fn trait_review ->
          {trait_review.name, %{"selected_values" => trait_review.selected_values}}
        end)
    }
  end

  defp update_host_review_search(host_reviews, host_index, query, results) do
    Enum.map(host_reviews, fn host_review ->
      if host_review.index == host_index do
        host_review
        |> Map.put(:search_query, query)
        |> Map.put(:search_results, results)
      else
        host_review
      end
    end)
  end

  defp toggle_trait_review_value(trait_reviews, trait_name, value) do
    Enum.map(trait_reviews, fn trait_review ->
      if trait_review.name == trait_name do
        Map.update!(trait_review, :selected_values, &toggle_string_in_list(&1, value))
      else
        trait_review
      end
    end)
  end

  # TODO: this is straight copy pasta from ingestion_review_live/index.ex
  # I also think that this code is basically implemented elsewhere as we have
  # other places that get the user info from Auth0
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

  defp resolve_current_user_db_id(nil), do: nil

  defp resolve_current_user_db_id(current_user) do
    case current_auth0_user(current_user) do
      %Accounts.Auth0User{} = auth0_user ->
        case Accounts.get_user_by_auth0_id(auth0_user.id) || sync_user_from_auth0(auth0_user) do
          %Accounts.User{id: id} -> id
          _ -> nil
        end

      nil ->
        nil
    end
  end

  defp current_auth0_user(%Accounts.Auth0User{} = current_user), do: current_user

  defp current_auth0_user(current_user) when is_map(current_user) do
    case current_auth0_id(current_user) do
      auth0_id when is_binary(auth0_id) ->
        %Accounts.Auth0User{
          id: auth0_id,
          email: Map.get(current_user, :email) || Map.get(current_user, "email"),
          name: Map.get(current_user, :name) || Map.get(current_user, "name"),
          nickname: Map.get(current_user, :nickname) || Map.get(current_user, "nickname"),
          picture: Map.get(current_user, :picture) || Map.get(current_user, "picture"),
          roles: Map.get(current_user, :roles) || Map.get(current_user, "roles") || []
        }

      _ ->
        nil
    end
  end

  defp current_auth0_user(_), do: nil

  defp current_auth0_id(current_user) when is_map(current_user) do
    Map.get(current_user, :id) || Map.get(current_user, "id")
  end

  defp sync_user_from_auth0(auth0_user) do
    case Accounts.sync_user_from_auth0(auth0_user) do
      {:ok, %Accounts.User{} = user} -> user
      {:error, _changeset} -> nil
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

  defp species_summary(species) do
    %{
      id: species.id,
      name: species.name,
      taxoncode: species.taxoncode
    }
  end

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

  defp source_review_locked_for_duplicate?(review_view),
    do: review_view.duplicate_review_required?

  defp species_review_locked_for_duplicate?(review_view),
    do: review_view.duplicate_review_required?

  defp changeset_error_message(changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, error} -> "#{field} #{translate_error(error)}" end)
  end

  defp workspace_saved_message(_workspace_status, "complete"),
    do: "Source ingestion review complete"

  defp workspace_saved_message("complete", _ingestion_status), do: "Gall review marked complete"
  defp workspace_saved_message("skipped", _ingestion_status), do: "Gall review skipped for later"
  defp workspace_saved_message(_workspace_status, _ingestion_status), do: "Gall review saved"

  defp workspace_trait_options(filter_options, trait_review) do
    trait_review.name
    |> trait_value_options(filter_options, trait_review)
    |> Enum.map(fn {label, value} ->
      %{label: label, value: encode_trait_value(trait_review.name, value)}
    end)
  end

  defp workspace_trait_selected_values(trait_review) do
    Enum.map(trait_review.selected_values, &encode_trait_value(trait_review.name, &1))
  end

  defp trait_value_options("detachable", _filter_options, trait_review) do
    known_values = Enum.map(@detachable_options, fn {label, value} -> {label, value} end)
    merge_trait_option_values(known_values, trait_review)
  end

  defp trait_value_options(trait_name, filter_options, trait_review) do
    known_values =
      trait_name
      |> then(&Map.get(@trait_filter_keys, &1))
      |> case do
        nil ->
          []

        key ->
          filter_options
          |> Map.get(key, [])
          |> Enum.map(fn option -> {option.field, option.field} end)
      end

    merge_trait_option_values(known_values, trait_review)
  end

  defp merge_trait_option_values(known_values, trait_review) do
    extra_values =
      (trait_review.selected_values ++ trait_review.suggested_values)
      |> Enum.uniq()
      |> Enum.reject(fn value ->
        Enum.any?(known_values, fn {_label, known_value} -> known_value == value end)
      end)
      |> Enum.map(&{&1, &1})

    known_values ++ extra_values
  end

  defp trait_label(trait_name) do
    trait_name
    |> String.replace("_", " ")
    |> Phoenix.Naming.humanize()
  end

  defp trait_suggested_text(%{suggested_values: []}), do: "No suggestions recorded"

  defp trait_suggested_text(%{suggested_values: suggested_values}),
    do: Enum.join(suggested_values, ", ")

  defp trait_evidence_text(%{raw_evidence: []}), do: "No raw evidence recorded"
  defp trait_evidence_text(%{raw_evidence: raw_evidence}), do: Enum.join(raw_evidence, "; ")

  defp encode_trait_value(trait_name, value), do: "#{trait_name}::#{value}"

  defp decode_trait_value(encoded_value) do
    case String.split(encoded_value, "::", parts: 2) do
      [trait_name, value] when trait_name != "" and value != "" -> {trait_name, value}
      _ -> :error
    end
  end

  defp toggle_string_in_list(values, value) do
    if value in values do
      Enum.reject(values, &(&1 == value))
    else
      values ++ [value]
    end
  end

  defp normalize_indexed_form_values(values) when is_list(values), do: values

  defp normalize_indexed_form_values(values) when is_map(values) do
    values
    |> Enum.map(fn {key, value} ->
      {parse_integer_param(key), Map.put_new(value, "index", key)}
    end)
    |> Enum.sort_by(fn {index, _value} -> index end)
    |> Enum.map(fn {_index, value} -> value end)
  end

  defp normalize_indexed_form_values(_), do: []

  defp nested_param(params, key, default) when is_map(params) do
    Map.get(params, key, default)
  end

  defp nested_param(_params, _key, default), do: default
end
