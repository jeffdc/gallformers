defmodule GallformersWeb.Admin.IngestionReviewLive.Workspace do
  use GallformersWeb, :live_view

  alias Gallformers.Accounts
  alias Gallformers.Galls
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
     |> assign(:species_entries, [])
     |> assign(:current_id, nil)
     |> assign(:selected_species, nil)
     |> assign(:workspace, nil)
     |> assign(:existing_gall, nil)
     |> assign(:suggested_match, nil)
     |> assign(:filter_options, %{})
     |> assign(:drawer_open, false)
     |> assign(:source_text, nil)
     |> assign(:saved_at, nil)
     |> assign(:create_host_modal, nil)
     |> assign(:dirty, false)}
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

    species_entries = Enum.sort_by(review_view.species_entries, & &1.extracted_name)
    filter_options = Galls.get_all_filter_options()

    first_unreviewed =
      Enum.find(species_entries, &(&1.status == "pending")) ||
        List.first(species_entries)

    {:noreply,
     socket
     |> assign(:review_view, review_view)
     |> assign(:species_entries, species_entries)
     |> assign(:page_title, "Species Review: #{review_view.display_title}")
     |> assign(:source_text, source_text)
     |> assign(:filter_options, filter_options)
     |> load_workspace_for_entry(first_unreviewed)}
  end

  # --- Events ---

  @impl true
  def handle_event("select_species", %{"entry-id" => entry_id}, socket) do
    id = String.to_integer(entry_id)
    entry = Enum.find(socket.assigns.species_entries, &(&1.id == id))
    {:noreply, load_workspace_for_entry(socket, entry)}
  end

  @impl true
  def handle_event("toggle_drawer", _params, socket) do
    {:noreply, assign(socket, :drawer_open, !socket.assigns.drawer_open)}
  end

  @impl true
  def handle_event("save_draft", _params, socket) do
    case save_current_workspace(socket, "save") do
      {:ok, socket} ->
        {:noreply,
         socket
         |> assign(:saved_at, Calendar.strftime(DateTime.utc_now(), "%H:%M"))
         |> put_flash(:info, "Draft saved")}

      {:error, socket} ->
        {:noreply, put_flash(socket, :error, "Failed to save draft")}
    end
  end

  @impl true
  def handle_event("commit_species", _params, socket) do
    case save_current_workspace(socket, "complete") do
      {:ok, socket} ->
        {:noreply, advance_to_next_unreviewed(socket)}

      {:error, socket} ->
        {:noreply, put_flash(socket, :error, "Failed to commit")}
    end
  end

  @impl true
  def handle_event("skip_species", _params, socket) do
    workspace = socket.assigns.workspace
    entry = Ingestions.get_source_ingestion_species!(workspace.id)
    reviewer_id = socket.assigns.current_user_db_id

    attrs = %{
      action: "save",
      species_review: %{decision: "skip"},
      host_reviews: %{},
      trait_reviews: %{},
      description_prose: workspace.description_prose
    }

    with {:ok, _updated} <-
           Ingestions.update_source_ingestion_species_review(entry, attrs, reviewer_id),
         :ok <- save_sibling_entries(workspace.sibling_ids, attrs, reviewer_id) do
      socket = reload_species_entries(socket)
      {:noreply, advance_to_next_unreviewed(socket)}
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to skip")}
    end
  end

  @impl true
  def handle_event("cancel_create_host", _params, socket) do
    {:noreply, assign(socket, :create_host_modal, nil)}
  end

  @impl true
  def handle_event("keydown", %{"key" => key}, socket) do
    case key do
      k when k in ["j", "ArrowDown"] ->
        {:noreply, navigate_species(socket, :next)}

      k when k in ["k", "ArrowUp"] ->
        {:noreply, navigate_species(socket, :prev)}

      "Escape" ->
        {:noreply, assign(socket, :drawer_open, false)}

      _ ->
        {:noreply, socket}
    end
  end

  # --- Section component messages ---

  @impl true
  def handle_info({:identity_resolved, resolution, mapped_species}, socket) do
    existing_gall =
      if resolution == :existing && mapped_species,
        do: Presenter.load_existing_gall_data(mapped_species.id),
        else: nil

    species_id = if mapped_species, do: mapped_species.id
    decision = if resolution == :existing, do: "mapped", else: "new"

    {:noreply,
     socket
     |> assign(:existing_gall, existing_gall)
     |> update_workspace(fn workspace ->
       workspace
       |> put_in([:species_review, :decision], decision)
       |> put_in([:species_review, :species_id], species_id)
       |> put_in([:species_review, :selected_species], mapped_species)
     end)
     |> mark_dirty()}
  end

  @impl true
  def handle_info({:identity_reset}, socket) do
    {:noreply,
     socket
     |> assign(:existing_gall, nil)
     |> update_workspace(fn workspace ->
       workspace
       |> put_in([:species_review, :decision], nil)
       |> put_in([:species_review, :species_id], nil)
       |> put_in([:species_review, :selected_species], nil)
     end)
     |> mark_dirty()}
  end

  @impl true
  def handle_info({:host_decision, index, action}, socket) do
    {:noreply,
     socket
     |> update_workspace(fn workspace ->
       Map.update!(workspace, :host_reviews, fn reviews ->
         Enum.map(reviews, fn review ->
           if review.index == index, do: %{review | decision: action}, else: review
         end)
       end)
     end)
     |> mark_dirty()}
  end

  @impl true
  def handle_info({:host_search_results, index, query, results}, socket) do
    {:noreply,
     update_workspace(socket, fn workspace ->
       Map.update!(workspace, :host_reviews, fn reviews ->
         Enum.map(reviews, fn review ->
           if review.index == index,
             do: %{review | search_query: query, search_results: results},
             else: review
         end)
       end)
     end)}
  end

  @impl true
  def handle_info({:host_mapped, index, species}, socket) do
    {:noreply,
     socket
     |> update_workspace(fn workspace ->
       Map.update!(workspace, :host_reviews, fn reviews ->
         Enum.map(reviews, fn review ->
           if review.index == index do
             %{
               review
               | species_id: species.id,
                 selected_species: species,
                 decision: "mapped",
                 search_query: "",
                 search_results: []
             }
           else
             review
           end
         end)
       end)
     end)
     |> mark_dirty()}
  end

  @impl true
  def handle_info({:alias_toggled, index, accepted}, socket) do
    {:noreply,
     socket
     |> update_workspace(fn workspace ->
       Map.update!(workspace, :extracted_aliases, fn aliases ->
         aliases
         |> Enum.with_index()
         |> Enum.map(fn {alias_entry, i} ->
           if i == index, do: Map.put(alias_entry, :accepted, accepted), else: alias_entry
         end)
       end)
     end)
     |> mark_dirty()}
  end

  @impl true
  def handle_info({:trait_updated, name, selected_values}, socket) do
    {:noreply,
     socket
     |> update_workspace(fn workspace ->
       Map.update!(workspace, :trait_reviews, fn reviews ->
         Enum.map(reviews, fn review ->
           if review.name == name,
             do: %{review | selected_values: selected_values},
             else: review
         end)
       end)
     end)
     |> mark_dirty()}
  end

  @impl true
  def handle_info({:request_create_host, index, name}, socket) do
    {:noreply, assign(socket, :create_host_modal, %{index: index, name: name})}
  end

  @impl true
  def handle_info({:cancel_create_host}, socket) do
    {:noreply, assign(socket, :create_host_modal, nil)}
  end

  @impl true
  def handle_info({:host_created_and_mapped, index, host}, socket) do
    {:noreply,
     socket
     |> assign(:create_host_modal, nil)
     |> update_workspace(fn workspace ->
       Map.update!(workspace, :host_reviews, fn reviews ->
         Enum.map(reviews, fn review ->
           if review.index == index do
             %{
               review
               | species_id: host.id,
                 selected_species: %{id: host.id, name: host.name},
                 decision: "mapped",
                 search_query: "",
                 search_results: []
             }
           else
             review
           end
         end)
       end)
     end)
     |> mark_dirty()}
  end

  @impl true
  def handle_info({:description_updated, _mode, text}, socket) do
    {:noreply,
     socket
     |> update_workspace(fn workspace ->
       Map.put(workspace, :description_prose, text)
     end)
     |> mark_dirty()}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <div :if={@review_view} class="flex flex-col gap-4" phx-window-keydown="keydown">
        <.workspace_top_bar
          review_view={@review_view}
          species_entries={@species_entries}
          saved_at={@saved_at}
          drawer_open={@drawer_open}
        />

        <div class="grid gap-6 xl:grid-cols-[280px_minmax(0,1fr)]">
          <.workspace_sidebar
            species_entries={@species_entries}
            current_id={@current_id}
          />

          <div class="space-y-6">
            <div :if={@workspace} id="workspace-detail" class="space-y-6">
              <.live_component
                module={GallformersWeb.Admin.IngestionReviewLive.WorkspaceIdentity}
                id="workspace-identity"
                workspace={@workspace}
                suggested_match={@suggested_match}
              />
              <.live_component
                module={GallformersWeb.Admin.IngestionReviewLive.WorkspaceHosts}
                id="workspace-hosts"
                workspace={@workspace}
                existing_gall={@existing_gall}
              />
              <.live_component
                module={GallformersWeb.Admin.IngestionReviewLive.WorkspaceAliases}
                id="workspace-aliases"
                workspace={@workspace}
                existing_gall={@existing_gall}
              />
              <.live_component
                module={GallformersWeb.Admin.IngestionReviewLive.WorkspaceTraits}
                id="workspace-traits"
                workspace={@workspace}
                existing_gall={@existing_gall}
                filter_options={@filter_options}
              />
              <.live_component
                module={GallformersWeb.Admin.IngestionReviewLive.WorkspaceDescription}
                id="workspace-description"
                workspace={@workspace}
                existing_gall={@existing_gall}
              />
              <.workspace_action_bar
                workspace={@workspace}
                selected_species={@selected_species}
                dirty={@dirty}
              />
            </div>
            <div :if={!@workspace} class="text-sm text-gray-500">
              No species entries to review.
            </div>
          </div>
        </div>
      </div>

      <.live_component
        module={GallformersWeb.Admin.IngestionReviewLive.WorkspaceDrawer}
        id="workspace-drawer"
        drawer_open={@drawer_open}
        source_text={@source_text}
      />

      <.modal
        :if={@create_host_modal}
        id="create-host-modal"
        show
        on_cancel={JS.push("cancel_create_host")}
      >
        <:header>Create new host</:header>
        <:body>
          <.live_component
            module={GallformersWeb.Admin.IngestionReviewLive.WorkspaceCreateHost}
            id="workspace-create-host"
            index={@create_host_modal.index}
            name={@create_host_modal.name}
          />
        </:body>
      </.modal>
    </Layouts.admin>
    """
  end

  # --- Template components ---

  attr :review_view, :map, required: true
  attr :species_entries, :list, required: true
  attr :saved_at, :string, default: nil
  attr :drawer_open, :boolean, default: false

  defp workspace_top_bar(assigns) do
    completed =
      Enum.count(assigns.species_entries, &(&1.status in ~w(complete mapped created skipped)))

    total = length(assigns.species_entries)
    progress_pct = if total > 0, do: round(completed / total * 100), else: 0

    assigns =
      assigns
      |> assign(:completed, completed)
      |> assign(:total, total)
      |> assign(:progress_pct, progress_pct)

    ~H"""
    <div class="space-y-3">
      <nav class="flex items-center rounded-lg border border-gray-200 bg-white px-4 py-2.5 shadow-sm">
        <div class="flex items-center gap-1.5 min-w-0 text-sm flex-1">
          <.link
            navigate={~p"/admin/ingestion-review"}
            class="shrink-0 text-gf-maroon hover:underline"
          >
            Ingestions
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
          <span class="shrink-0 text-gray-700">Species review</span>
        </div>

        <div class="flex items-center gap-3">
          <span :if={@saved_at} class="text-xs text-gray-500">
            Saved {@saved_at}
          </span>
          <button
            type="button"
            phx-click="toggle_drawer"
            class={[
              "inline-flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-xs font-medium transition",
              if(@drawer_open,
                do: "bg-gf-maroon text-white",
                else: "bg-gray-100 text-gray-700 hover:bg-gray-200"
              )
            ]}
          >
            <.icon name="ph-file-text" class="size-3.5" /> Source text
          </button>
        </div>
      </nav>

      <div class="flex items-center gap-3">
        <div class="text-xs text-gray-500">
          {@review_view.display_title}
          <span :if={@review_view.authors != []}>
            · {Enum.join(List.wrap(@review_view.authors), ", ")}
          </span>
          <span :if={@review_view.publication_year}>({@review_view.publication_year})</span>
        </div>
        <div class="flex-1" />
        <div class="flex items-center gap-2">
          <div class="h-2 w-24 rounded-full bg-gray-200 overflow-hidden">
            <div
              class="h-full rounded-full bg-green-500 transition-all duration-300"
              style={"width: #{@progress_pct}%"}
            />
          </div>
          <span class="text-xs text-gray-500">{@completed}/{@total}</span>
        </div>
      </div>
    </div>
    """
  end

  attr :species_entries, :list, required: true
  attr :current_id, :integer, default: nil

  defp workspace_sidebar(assigns) do
    ~H"""
    <aside class="space-y-3 rounded-lg border border-gray-200 bg-gray-50 p-4">
      <div class="flex items-center justify-between">
        <div class="text-xs font-medium uppercase tracking-wide text-gray-500">
          Species in source
        </div>
        <div class="text-xs text-gray-500">{length(@species_entries)}</div>
      </div>

      <div class="space-y-1">
        <button
          :for={entry <- @species_entries}
          id={"workspace-nav-#{entry.id}"}
          type="button"
          phx-click="select_species"
          phx-value-entry-id={entry.id}
          class={[
            "w-full rounded px-3 py-2 text-left text-sm transition",
            if(entry.id == @current_id,
              do: "border-l-2 border-gf-maroon bg-white shadow-sm",
              else: "hover:bg-white"
            )
          ]}
        >
          <div class="flex items-center gap-2">
            <div class="min-w-0 flex-1">
              <div class="truncate font-medium italic text-gray-900">
                {entry.extracted_name || "Unnamed"}
              </div>
              <div :if={entry.extracted_authority} class="truncate text-xs text-gray-500">
                {entry.extracted_authority}
              </div>
            </div>
            <.entry_status_mark status={entry.status} />
          </div>
        </button>
      </div>

      <div class="text-xs text-gray-400 pt-2 border-t border-gray-200">
        <kbd class="font-mono">J</kbd>/<kbd class="font-mono">K</kbd> to navigate
      </div>
    </aside>
    """
  end

  attr :status, :string, required: true

  defp entry_status_mark(assigns) do
    ~H"""
    <span
      :if={@status in ~w(complete mapped created)}
      class="size-2 rounded-full bg-green-500"
      title="Complete"
    />
    <span :if={@status == "skipped"} class="size-2 rounded-full bg-gray-400" title="Skipped" />
    <span
      :if={@status == "in_progress"}
      class="size-2 rounded-full bg-amber-400"
      title="In progress"
    />
    """
  end

  # --- Workspace state management ---

  defp load_workspace_for_entry(socket, nil) do
    socket
    |> assign(:current_id, nil)
    |> assign(:selected_species, nil)
    |> assign(:workspace, nil)
    |> assign(:existing_gall, nil)
    |> assign(:suggested_match, nil)
  end

  defp load_workspace_for_entry(socket, entry) do
    sibling_ids = Map.get(entry, :sibling_ids, [])
    workspace_view = Ingestions.source_ingestion_species_review_workspace!(entry.id)

    sibling_views =
      Enum.map(sibling_ids, &Ingestions.source_ingestion_species_review_workspace!/1)

    workspace =
      workspace_view
      |> merge_sibling_data(sibling_views)
      |> build_workspace_state()
      |> Map.put(:sibling_ids, sibling_ids)
      |> auto_match_hosts()

    existing_gall =
      if workspace.species_review.species_id,
        do: Presenter.load_existing_gall_data(workspace.species_review.species_id),
        else: nil

    suggested_match =
      if is_nil(workspace.species_review.decision) do
        Presenter.load_suggested_match(workspace.extracted_name)
      end

    socket
    |> assign(:current_id, entry.id)
    |> assign(:selected_species, entry)
    |> assign(:workspace, workspace)
    |> assign(:existing_gall, existing_gall)
    |> assign(:suggested_match, suggested_match)
    |> assign(:dirty, false)
  end

  defp merge_sibling_data(primary, []), do: primary

  defp merge_sibling_data(primary, siblings) do
    %{
      primary
      | extracted_authority:
          primary.extracted_authority ||
            Enum.find_value(siblings, & &1.extracted_authority),
        host_reviews:
          merge_unique_by(
            primary.host_reviews,
            Enum.flat_map(siblings, & &1.host_reviews),
            & &1.extracted_name
          )
          |> Enum.with_index()
          |> Enum.map(fn {review, i} -> %{review | index: i} end),
        extracted_aliases:
          Enum.uniq(primary.extracted_aliases ++ Enum.flat_map(siblings, & &1.extracted_aliases)),
        trait_reviews: merge_trait_reviews(primary.trait_reviews, siblings),
        description_prose: merge_description_prose(primary, siblings),
        description_evidence:
          Enum.uniq(
            primary.description_evidence ++ Enum.flat_map(siblings, & &1.description_evidence)
          )
    }
  end

  defp merge_unique_by(primary_list, sibling_list, key_fn) do
    existing_keys = MapSet.new(primary_list, key_fn)

    primary_list ++
      Enum.reject(sibling_list, &MapSet.member?(existing_keys, key_fn.(&1)))
  end

  defp merge_trait_reviews(primary_traits, siblings) do
    sibling_traits =
      siblings
      |> Enum.flat_map(& &1.trait_reviews)
      |> Enum.group_by(& &1.name)

    existing_names = MapSet.new(primary_traits, & &1.name)

    new_traits =
      sibling_traits
      |> Enum.reject(fn {name, _} -> MapSet.member?(existing_names, name) end)
      |> Enum.map(fn {_name, [first | _]} -> first end)

    primary_traits ++ new_traits
  end

  defp merge_description_prose(primary, siblings) do
    all_prose =
      [primary.description_prose | Enum.map(siblings, & &1.description_prose)]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    Enum.join(all_prose, "\n\n")
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
      extracted_aliases:
        Enum.map(workspace_view.extracted_aliases, fn name ->
          %{name: name, accepted: true}
        end),
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

  defp auto_match_hosts(workspace) do
    Map.update!(workspace, :host_reviews, fn reviews ->
      Enum.map(reviews, &maybe_auto_match_host/1)
    end)
  end

  defp maybe_auto_match_host(%{species_id: id} = review) when not is_nil(id), do: review
  defp maybe_auto_match_host(%{decision: "skip"} = review), do: review

  defp maybe_auto_match_host(review) do
    case find_exact_species(review.extracted_name, "plant") do
      nil -> review
      match -> %{review | selected_species: match, species_id: match.id, decision: "mapped"}
    end
  end

  defp find_exact_species(nil, _taxoncode), do: nil
  defp find_exact_species("", _taxoncode), do: nil

  defp find_exact_species(name, taxoncode) do
    name_downcased = String.downcase(name)
    results = Species.search_species_by_name(name, taxoncode, 5)

    case Enum.find(results, &(String.downcase(&1.name) == name_downcased)) do
      nil -> exact_match_for_abbreviated_genus(name, results)
      match -> match
    end
  end

  # When the query is in "X. species" form and the smart search returned a single
  # result, treat that as the unambiguous match.
  defp exact_match_for_abbreviated_genus(name, [single]) do
    if Regex.match?(~r/^\s*[A-Z]\.\s+\S+/, name), do: single, else: nil
  end

  defp exact_match_for_abbreviated_genus(_name, _results), do: nil

  defp update_workspace(socket, fun) do
    case socket.assigns.workspace do
      nil -> socket
      workspace -> assign(socket, :workspace, fun.(workspace))
    end
  end

  defp mark_dirty(socket), do: assign(socket, :dirty, true)

  # --- Action bar ---

  attr :workspace, :map, required: true
  attr :selected_species, :any, required: true
  attr :dirty, :boolean, required: true

  defp workspace_action_bar(assigns) do
    decision = assigns.workspace.species_review.decision
    resolved = decision in ["mapped", "new"]

    commit_label =
      case decision do
        "mapped" -> "Update gall"
        "new" -> "Create gall"
        _ -> "Commit"
      end

    skip_disabled =
      case assigns.selected_species do
        %{status: status} when status != "pending" -> true
        _ -> false
      end

    assigns =
      assigns
      |> assign(:resolved, resolved)
      |> assign(:commit_label, commit_label)
      |> assign(:skip_disabled, skip_disabled)

    ~H"""
    <div class="flex items-center justify-end gap-3 rounded-lg border border-gray-200 bg-gray-50 p-4">
      <button
        type="button"
        phx-click="skip_species"
        disabled={@skip_disabled}
        class={[
          "rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium",
          if(@skip_disabled,
            do: "text-gray-300 cursor-not-allowed",
            else: "text-gray-700 hover:bg-gray-50"
          )
        ]}
      >
        Skip
      </button>
      <button
        type="button"
        phx-click="save_draft"
        disabled={!@dirty}
        class={[
          "rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium",
          if(@dirty,
            do: "text-gray-700 hover:bg-gray-50",
            else: "text-gray-300 cursor-not-allowed"
          )
        ]}
      >
        Save draft
      </button>
      <button
        type="button"
        phx-click="commit_species"
        disabled={!@resolved || !@dirty}
        class={[
          "rounded-md px-4 py-2 text-sm font-medium text-white",
          if(@resolved && @dirty,
            do: "bg-gf-maroon hover:bg-gf-maroon/90",
            else: "bg-gray-300 cursor-not-allowed"
          )
        ]}
      >
        {@commit_label}
      </button>
    </div>
    """
  end

  # --- Save / commit / skip helpers ---

  defp save_current_workspace(socket, action) do
    workspace = socket.assigns.workspace
    entry = Ingestions.get_source_ingestion_species!(workspace.id)
    attrs = collect_workspace_attrs(workspace, action)
    reviewer_id = socket.assigns.current_user_db_id

    with {:ok, _updated} <-
           Ingestions.update_source_ingestion_species_review(entry, attrs, reviewer_id),
         :ok <- save_sibling_entries(workspace.sibling_ids, attrs, reviewer_id) do
      {:ok, socket |> reload_species_entries() |> assign(:dirty, false)}
    else
      {:error, _reason} -> {:error, socket}
    end
  end

  defp save_sibling_entries([], _attrs, _reviewer_id), do: :ok

  defp save_sibling_entries(sibling_ids, _attrs, reviewer_id) do
    Enum.reduce_while(sibling_ids, :ok, fn id, :ok ->
      entry = Ingestions.get_source_ingestion_species!(id)

      case Ingestions.transition_source_ingestion_species_status(entry, "complete", %{
             reviewed_by_id: reviewer_id
           }) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp collect_workspace_attrs(workspace, action) do
    accepted_aliases =
      workspace.extracted_aliases
      |> Enum.filter(& &1.accepted)
      |> Enum.map(& &1.name)

    host_reviews =
      workspace.host_reviews
      |> Enum.with_index()
      |> Enum.into(%{}, fn {review, index} ->
        {to_string(index),
         %{
           decision: review.decision,
           species_id: review.species_id,
           extracted_name: review.extracted_name,
           extracted_authority: review.extracted_authority
         }}
      end)

    trait_reviews =
      Enum.into(workspace.trait_reviews, %{}, fn review ->
        {review.name, %{selected_values: review.selected_values}}
      end)

    %{
      action: action,
      species_review: %{
        decision: workspace.species_review.decision,
        species_id: workspace.species_review.species_id,
        accepted_aliases: accepted_aliases
      },
      host_reviews: host_reviews,
      trait_reviews: trait_reviews,
      description_prose: workspace.description_prose
    }
  end

  defp reload_species_entries(socket) do
    review_view = Presenter.source_ingestion_review_view!(socket.assigns.review_view.id)
    species_entries = Enum.sort_by(review_view.species_entries, & &1.extracted_name)

    socket
    |> assign(:review_view, review_view)
    |> assign(:species_entries, species_entries)
  end

  defp advance_to_next_unreviewed(socket) do
    entries = socket.assigns.species_entries
    current_id = socket.assigns.current_id
    current_index = Enum.find_index(entries, &(&1.id == current_id)) || 0

    next =
      entries
      |> Enum.drop(current_index + 1)
      |> Enum.find(&(&1.status == "pending"))

    next = next || Enum.find(entries, &(&1.status == "pending"))

    if next do
      load_workspace_for_entry(socket, next)
    else
      socket
    end
  end

  defp navigate_species(socket, direction) do
    entries = socket.assigns.species_entries
    current_id = socket.assigns.current_id

    current_index = Enum.find_index(entries, &(&1.id == current_id)) || 0

    target_index =
      case direction do
        :next -> min(current_index + 1, length(entries) - 1)
        :prev -> max(current_index - 1, 0)
      end

    entry = Enum.at(entries, target_index)
    load_workspace_for_entry(socket, entry)
  end
end
