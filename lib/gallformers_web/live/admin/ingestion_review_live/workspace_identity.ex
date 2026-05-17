defmodule GallformersWeb.Admin.IngestionReviewLive.WorkspaceIdentity do
  use GallformersWeb, :live_component

  alias Gallformers.Species

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:search_query, fn -> "" end)
     |> assign_new(:search_results, fn -> [] end)}
  end

  @impl true
  def handle_event("search_species", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Species.search_species_by_name(query, "gall", 10)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, results)}
  end

  @impl true
  def handle_event("select_species", %{"id" => id}, socket) do
    species = Species.get_species!(String.to_integer(id))

    send(
      self(),
      {:identity_resolved, :existing,
       %{id: species.id, name: species.name, taxoncode: species.taxoncode}}
    )

    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:search_results, [])}
  end

  @impl true
  def handle_event("clear_species", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:search_results, [])}
  end

  @impl true
  def handle_event("treat_as_new", _params, socket) do
    send(self(), {:identity_resolved, :new, nil})
    {:noreply, socket}
  end

  @impl true
  def handle_event("change_identity", _params, socket) do
    send(self(), {:identity_reset})

    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:search_results, [])}
  end

  @impl true
  def render(assigns) do
    decision = assigns.workspace.species_review.decision

    assigns =
      assigns
      |> assign(:decision, decision)
      |> assign(:resolved, decision in ["mapped", "new"])

    ~H"""
    <section id="workspace-section-identity" class="rounded-lg border border-gray-200 p-4 space-y-4">
      <h3 class="text-base font-semibold text-gray-900">Identity</h3>

      <div class="rounded-lg border border-gray-200 bg-gray-50 p-4 space-y-3">
        <div class="flex items-start justify-between gap-3">
          <div>
            <div class="text-sm font-medium italic text-gray-900">
              {@workspace.extracted_name || "Unnamed gall"}
            </div>
            <div :if={@workspace.extracted_authority} class="text-xs text-gray-500">
              {@workspace.extracted_authority}
            </div>
          </div>
        </div>
      </div>

      <%= if @resolved do %>
        <.resolved_state
          decision={@decision}
          workspace={@workspace}
          myself={@myself}
        />
      <% else %>
        <.search_state
          search_query={@search_query}
          search_results={@search_results}
          myself={@myself}
        />
      <% end %>
    </section>
    """
  end

  # --- Render substates ---

  attr :search_query, :string, required: true
  attr :search_results, :list, required: true
  attr :myself, :any, required: true

  defp search_state(assigns) do
    ~H"""
    <div class="space-y-3">
      <.typeahead
        id="identity-species-picker"
        label="Search gall species"
        placeholder="Type to search..."
        query={@search_query}
        results={@search_results}
        selected={nil}
        search_event="search_species"
        select_event="select_species"
        clear_event="clear_species"
        display_fn={& &1.name}
        target={@myself}
      >
        <:result :let={species}>
          <div class="font-medium italic text-gray-900">{species.name}</div>
          <div class="text-xs text-gray-500">{species.taxoncode}</div>
        </:result>
      </.typeahead>

      <div class="text-center">
        <span class="text-xs text-gray-400">or</span>
      </div>

      <button
        type="button"
        phx-click="treat_as_new"
        phx-target={@myself}
        class="w-full rounded-lg border-2 border-dashed border-gray-300 p-4 text-center hover:border-gray-400 transition"
      >
        <div class="text-sm font-medium text-gray-700">Treat as new species</div>
        <div class="text-xs text-gray-500 mt-1">
          This gall will be created when the review is committed.
        </div>
      </button>
    </div>
    """
  end

  attr :decision, :string, required: true
  attr :workspace, :map, required: true
  attr :myself, :any, required: true

  defp resolved_state(assigns) do
    selected = assigns.workspace.species_review.selected_species
    extracted_name = assigns.workspace.extracted_name
    mapped_name = selected && selected.name

    name_differs =
      selected != nil &&
        extracted_name != nil &&
        String.downcase(extracted_name) != String.downcase(mapped_name || "")

    assigns =
      assigns
      |> assign(:selected, selected)
      |> assign(:name_differs, name_differs)

    ~H"""
    <div class="rounded-lg border border-gray-200 bg-white p-4 space-y-2">
      <div class="flex items-center gap-2">
        <.badge :if={@decision == "mapped"} variant="success">Mapped · existing</.badge>
        <.badge :if={@decision == "new"} variant="info">Treated as new</.badge>
      </div>

      <div :if={@selected} class="text-sm">
        <span class="font-medium italic text-gray-900">{@selected.name}</span>
      </div>

      <div :if={@name_differs} class="flex items-center gap-1.5 text-xs">
        <.badge variant="warning">+alias</.badge>
        <span class="text-gray-500">Extracted as "{@workspace.extracted_name}"</span>
      </div>

      <button
        type="button"
        phx-click="change_identity"
        phx-target={@myself}
        class="text-sm text-gf-maroon hover:underline"
      >
        Change...
      </button>
    </div>
    """
  end
end
