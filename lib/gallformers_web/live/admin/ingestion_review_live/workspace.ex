defmodule GallformersWeb.Admin.IngestionReviewLive.Workspace do
  use GallformersWeb, :live_view

  import GallformersWeb.Admin.FormComponents, only: [alias_collision_warning: 1]

  alias Gallformers.Accounts
  alias Gallformers.Ingestions
  alias Gallformers.Species
  alias GallformersWeb.Admin.IngestionReviewLive.Presenter

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:current_user, session["current_user"])
     |> assign(:current_user_db_id, Accounts.db_user_id(session))
     |> assign(:page_title, "Species Review Workspace")
     |> assign(:review_view, nil)
     |> assign(:source_text, nil)
     |> assign(:selected_entry, nil)
     |> assign(:workspace, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    source_ingestion_id = String.to_integer(id)
    review_view = Presenter.source_ingestion_review_view!(source_ingestion_id)

    source_text =
      case Ingestions.source_ingestion_full_text(source_ingestion_id) do
        {:ok, text} -> text
        _ -> nil
      end

    first_unreviewed =
      Enum.find(review_view.species_entries, &(&1.status == "pending")) ||
        List.first(review_view.species_entries)

    {:noreply,
     socket
     |> assign(:review_view, review_view)
     |> assign(:page_title, "Species Review: #{review_view.display_title}")
     |> assign(:source_text, source_text)
     |> load_workspace_for_entry(first_unreviewed)}
  end

  @impl true
  def handle_event("select_gall", %{"entry-id" => entry_id}, socket) do
    id = String.to_integer(entry_id)
    entry = Enum.find(socket.assigns.review_view.species_entries, &(&1.id == id))
    {:noreply, load_workspace_for_entry(socket, entry)}
  end

  @impl true
  def handle_event("change_gall_review_workspace", %{"workspace" => params}, socket) do
    {:noreply, update_workspace_assign(socket, params)}
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
  def handle_event("search_workspace_species", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Species.search_species_by_name(query, "gall", 10)
      else
        []
      end

    {:noreply,
     update_workspace(socket, fn workspace ->
       workspace
       |> put_in([:species_review, :search_query], query)
       |> put_in([:species_review, :search_results], results)
     end)}
  end

  @impl true
  def handle_event("select_workspace_species", %{"id" => id}, socket) do
    species = Species.get_species!(parse_id(id))

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
  def handle_event("search_workspace_host:" <> host_index, %{"value" => query}, socket) do
    host_index = parse_id(host_index)

    results =
      if String.length(query) >= 2 do
        Species.search_species_by_name(query, "plant", 10)
      else
        []
      end

    {:noreply,
     update_workspace(socket, fn workspace ->
       update_in(
         workspace.host_reviews,
         &update_host_review_search(&1, host_index, query, results)
       )
     end)}
  end

  @impl true
  def handle_event("select_workspace_host:" <> host_index, %{"id" => id}, socket) do
    species = Species.get_species!(parse_id(id))
    host_index = parse_id(host_index)

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
    host_index = parse_id(host_index)

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
      <div :if={@review_view} class="space-y-4">
        <.workspace_breadcrumb review_view={@review_view} />

        <div class="grid gap-6 xl:grid-cols-[280px_minmax(0,1fr)]">
          <aside class="space-y-3 rounded-lg border border-gray-200 bg-gray-50 p-4">
            <div class="text-xs font-medium uppercase tracking-wide text-gray-500">
              Gall Queue
            </div>
            <div class="text-xs text-gray-500">
              {@review_view.counts.species_entries_resolved} reviewed · {@review_view.counts.species_entries_pending} remaining
            </div>
            <div class="space-y-2">
              <button
                :for={entry <- @review_view.species_entries}
                id={"workspace-nav-#{entry.id}"}
                type="button"
                phx-click="select_gall"
                phx-value-entry-id={entry.id}
                class={[
                  "w-full rounded-lg border px-3 py-3 text-left transition",
                  if(@selected_entry && @selected_entry.id == entry.id,
                    do: "border-gf-maroon bg-white shadow-sm",
                    else: "border-gray-200 bg-white hover:border-gray-300"
                  )
                ]}
              >
                <div class="flex items-start justify-between gap-3">
                  <div>
                    <div class="font-medium text-gray-900">
                      {entry.extracted_name || "Unnamed gall"}
                    </div>
                    <div :if={entry.extracted_authority} class="text-sm text-gray-500">
                      {entry.extracted_authority}
                    </div>
                  </div>
                  <.badge variant="info">{entry.status}</.badge>
                </div>
              </button>
            </div>
          </aside>

          <div class="space-y-6">
            <form
              :if={@workspace}
              id="gall-review-workspace-form"
              phx-change="change_gall_review_workspace"
              phx-submit="save_gall_review_workspace"
              class="space-y-6"
            >
              <input type="hidden" name="workspace[id]" value={@workspace.id} />

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

              <section :if={@workspace.extracted_aliases != []} class="space-y-4">
                <div>
                  <h3 class="text-base font-semibold text-gray-900">Aliases</h3>
                  <p class="text-sm text-gray-500">
                    Select aliases to save as scientific synonyms on completion.
                  </p>
                </div>

                <div class="space-y-2">
                  <label
                    :for={alias_name <- @workspace.extracted_aliases}
                    class="flex items-center gap-2 text-sm text-gray-900"
                  >
                    <input
                      type="checkbox"
                      name="workspace[species_review][accepted_aliases][]"
                      value={alias_name}
                      checked={alias_name in (@workspace.species_review.accepted_aliases || [])}
                      class="rounded border-gray-300"
                    />
                    {alias_name}
                    <span class="text-xs text-gray-500">
                      Save as scientific synonym on completion
                    </span>
                  </label>
                </div>
              </section>

              <section class="space-y-4">
                <div>
                  <h3 class="text-base font-semibold text-gray-900">Host Review</h3>
                  <p class="text-sm text-gray-500">
                    Review extracted host mentions and map them to existing host species.
                  </p>
                </div>

                <div :if={@workspace.host_reviews == []} class="text-sm text-gray-500">
                  No host mentions were extracted for this gall.
                </div>

                <div
                  :for={host_review <- @workspace.host_reviews}
                  id={"host-review-#{host_review.index}"}
                  class="rounded-lg border border-gray-200 p-3 space-y-3"
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

                  <div class="flex items-start justify-between gap-3">
                    <div>
                      <div class="text-sm font-medium text-gray-900">
                        {host_review.extracted_name}
                      </div>
                      <div :if={host_review.extracted_authority} class="text-xs text-gray-500">
                        {host_review.extracted_authority}
                      </div>
                    </div>
                    <.badge variant="info">{host_review.decision}</.badge>
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

                <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
                  <div
                    :for={trait_review <- @workspace.trait_reviews}
                    id={"trait-review-#{trait_review.name}"}
                    class="rounded-lg border border-gray-200 p-3 space-y-2"
                  >
                    <h4 class="font-medium text-gray-900">{trait_label(trait_review.name)}</h4>
                    <p class="text-xs text-gray-500">
                      Suggested: {trait_suggested_text(trait_review)}
                    </p>
                    <p class="text-xs text-gray-500">
                      Evidence: {trait_evidence_text(trait_review)}
                    </p>
                  </div>
                </div>
              </section>

              <section class="space-y-4">
                <div>
                  <h3 class="text-base font-semibold text-gray-900">Description Review</h3>
                  <p class="text-sm text-gray-500">
                    Edit the persisted description prose directly.
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
                  rows="6"
                  value={@workspace.description_prose}
                />
              </section>

              <div class="flex flex-wrap justify-end gap-3 border-t border-gray-200 pt-4">
                <.button
                  type="submit"
                  name="workspace[action]"
                  value="save"
                  variant="secondary"
                >
                  Save Review
                </.button>
                <.button
                  type="submit"
                  name="workspace[action]"
                  value="complete"
                  variant="primary"
                >
                  Mark Complete
                </.button>
              </div>
            </form>
            <div :if={!@workspace} class="text-sm text-gray-500">
              No species entries to review.
            </div>
          </div>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  # --- Workspace state management ---

  defp load_workspace_for_entry(socket, nil) do
    socket
    |> assign(:selected_entry, nil)
    |> assign(:workspace, nil)
  end

  defp load_workspace_for_entry(socket, entry) do
    workspace_view = Ingestions.source_ingestion_species_review_workspace!(entry.id)
    workspace = build_workspace_state(workspace_view)

    socket
    |> assign(:selected_entry, entry)
    |> assign(:workspace, workspace)
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
      extracted_aliases: workspace_view.extracted_aliases,
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

  defp update_workspace(socket, fun) do
    case socket.assigns.workspace do
      nil -> socket
      workspace -> assign(socket, :workspace, fun.(workspace))
    end
  end

  defp update_workspace_assign(socket, params) do
    update_workspace(socket, &merge_workspace_params(&1, params))
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
            ) == host_review.index
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

  defp finalize_workspace_save(socket, workspace, source_ingestion_id) do
    case Ingestions.maybe_complete_source_ingestion_review(source_ingestion_id) do
      {:ok, source_ingestion} ->
        reloaded_workspace =
          workspace.id
          |> Ingestions.source_ingestion_species_review_workspace!()
          |> build_workspace_state()

        review_view = Presenter.source_ingestion_review_view!(source_ingestion_id)
        entry = Enum.find(review_view.species_entries, &(&1.id == workspace.id))

        {:noreply,
         socket
         |> put_flash(
           :info,
           workspace_saved_message(reloaded_workspace.status, source_ingestion.status)
         )
         |> assign(:review_view, review_view)
         |> assign(:selected_entry, entry)
         |> assign(:workspace, reloaded_workspace)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error_message(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to finalize review: #{inspect(reason)}")}
    end
  end

  # --- Selection normalization ---

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

  # --- Helpers ---

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

  defp species_summary(species) do
    %{
      id: species.id,
      name: species.name,
      taxoncode: species.taxoncode
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

  defp workspace_saved_message(_workspace_status, "complete"),
    do: "Source ingestion review complete"

  defp workspace_saved_message("complete", _ingestion_status), do: "Gall review marked complete"
  defp workspace_saved_message("skipped", _ingestion_status), do: "Gall review skipped for later"
  defp workspace_saved_message(_workspace_status, _ingestion_status), do: "Gall review saved"

  defp changeset_error_message(changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, error} -> "#{field} #{translate_error(error)}" end)
  end

  defp metadata_value(nil), do: "None"
  defp metadata_value(""), do: "None"
  defp metadata_value(value), do: to_string(value)

  defp nested_param(params, key, default) when is_map(params) do
    Map.get(params, key, Map.get(params, String.to_existing_atom(key), default))
  rescue
    ArgumentError -> Map.get(params, key, default)
  end

  defp nested_param(_params, _key, default), do: default

  defp normalize_indexed_form_values(values) when is_list(values), do: values

  defp normalize_indexed_form_values(values) when is_map(values) do
    values
    |> Enum.map(fn {key, value} ->
      {parse_integer_param(key), Map.put_new(value, "index", key)}
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  defp normalize_indexed_form_values(_), do: []

  defp parse_integer_param(value) when is_integer(value), do: value
  defp parse_integer_param(value) when is_binary(value), do: String.to_integer(value)

  defp parse_id(id) when is_integer(id), do: id
  defp parse_id(id) when is_binary(id), do: String.to_integer(id)

  attr :review_view, :map, required: true

  defp workspace_breadcrumb(assigns) do
    ~H"""
    <nav class="flex items-center rounded-lg border border-gray-200 bg-white px-4 py-2.5 shadow-sm">
      <div class="flex items-center gap-1.5 min-w-0 text-sm">
        <.link navigate={~p"/admin/ingestion-review"} class="shrink-0 text-gf-maroon hover:underline">
          Queue
        </.link>
        <.icon name="ph-caret-right" class="size-3.5 shrink-0 text-gray-400" />
        <.link
          navigate={~p"/admin/ingestion-review/#{@review_view.id}"}
          class="shrink-0 max-w-xs truncate text-gf-maroon hover:underline"
          title={@review_view.display_title}
        >
          {@review_view.display_title}
        </.link>
        <.icon name="ph-caret-right" class="size-3.5 shrink-0 text-gray-400" />
        <span class="shrink-0 text-gray-700">Species Review</span>
      </div>
    </nav>
    """
  end
end
