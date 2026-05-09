defmodule GallformersWeb.Admin.IngestionReviewLive.WorkspaceHosts do
  use GallformersWeb, :live_component

  alias Gallformers.Species

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("host_accept", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    send(self(), {:host_decision, index, "mapped"})
    {:noreply, socket}
  end

  @impl true
  def handle_event("host_decline", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    send(self(), {:host_decision, index, "skip"})
    {:noreply, socket}
  end

  @impl true
  def handle_event("host_search_" <> index_str, %{"value" => query}, socket) do
    index = String.to_integer(index_str)
    query = String.trim(query)

    results =
      if String.length(query) >= 2 do
        Species.search_species_by_name(query, "plant", 10)
      else
        []
      end

    send(self(), {:host_search_results, index, query, results})
    {:noreply, socket}
  end

  @impl true
  def handle_event("host_select_" <> index_str, %{"id" => species_id_str}, socket) do
    index = String.to_integer(index_str)
    species = Species.get_species!(String.to_integer(species_id_str))
    send(self(), {:host_mapped, index, species})
    {:noreply, socket}
  end

  @impl true
  def handle_event("host_clear_" <> index_str, _params, socket) do
    index = String.to_integer(index_str)
    send(self(), {:host_search_results, index, "", []})
    {:noreply, socket}
  end

  @impl true
  def handle_event("host_create_" <> index_str, %{"name" => name}, socket) do
    index = String.to_integer(index_str)
    send(self(), {:request_create_host, index, name})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    locked = is_nil(assigns.workspace.species_review.decision)
    decision = assigns.workspace.species_review.decision
    host_reviews = assigns.workspace.host_reviews
    existing_hosts = if assigns.existing_gall, do: assigns.existing_gall.hosts, else: []

    accepted_count =
      Enum.count(host_reviews, &(&1.decision == "mapped" and not is_nil(&1.species_id)))

    total_count = length(host_reviews)

    existing_host_ids = MapSet.new(existing_hosts, & &1.host_species_id)

    assigns =
      assigns
      |> assign(:locked, locked)
      |> assign(:decision, decision)
      |> assign(:host_reviews, host_reviews)
      |> assign(:existing_hosts, existing_hosts)
      |> assign(:accepted_count, accepted_count)
      |> assign(:total_count, total_count)
      |> assign(:existing_host_ids, existing_host_ids)

    ~H"""
    <section id="workspace-section-hosts" class="rounded-lg border border-gray-200 p-4 space-y-4">
      <div class="flex items-center justify-between">
        <h3 class="text-base font-semibold text-gray-900">Hosts</h3>
        <.badge :if={@locked} variant="warning">Locked · resolve identity first</.badge>
      </div>

      <div :if={!@locked} class="space-y-4">
        <.existing_hosts_group
          :if={@decision == "mapped" && @existing_hosts != []}
          existing_hosts={@existing_hosts}
        />

        <.source_hosts_group
          host_reviews={@host_reviews}
          existing_host_ids={@existing_host_ids}
          accepted_count={@accepted_count}
          total_count={@total_count}
          myself={@myself}
        />
      </div>
    </section>
    """
  end

  attr :existing_hosts, :list, required: true

  defp existing_hosts_group(assigns) do
    ~H"""
    <div class="space-y-2">
      <div class="text-xs font-medium uppercase tracking-wide text-gray-500">Currently linked</div>
      <div class="space-y-1">
        <div
          :for={host <- @existing_hosts}
          class="flex items-center gap-2 rounded px-3 py-2 bg-gray-50"
        >
          <span class="size-2 rounded-full bg-green-500 shrink-0" />
          <span class="font-medium italic text-gray-900 text-sm">{host.host_name}</span>
          <span class="text-xs text-gray-400 ml-auto">linked</span>
        </div>
      </div>
    </div>
    """
  end

  attr :host_reviews, :list, required: true
  attr :existing_host_ids, :any, required: true
  attr :accepted_count, :integer, required: true
  attr :total_count, :integer, required: true
  attr :myself, :any, required: true

  defp source_hosts_group(assigns) do
    ~H"""
    <div class="space-y-2">
      <div class="flex items-center justify-between">
        <div class="text-xs font-medium uppercase tracking-wide text-gray-500">From source</div>
        <span class="text-xs text-gray-500">{@accepted_count} of {@total_count} accepted</span>
      </div>
      <div class="space-y-1">
        <.host_review_row
          :for={review <- @host_reviews}
          review={review}
          already_linked={
            review.species_id != nil && MapSet.member?(@existing_host_ids, review.species_id)
          }
          myself={@myself}
        />
      </div>
    </div>
    """
  end

  attr :review, :map, required: true
  attr :already_linked, :boolean, required: true
  attr :myself, :any, required: true

  defp host_review_row(assigns) do
    decision = assigns.review.decision
    matched = not is_nil(assigns.review.species_id)

    assigns =
      assigns
      |> assign(:matched, matched)
      |> assign(:accepted, decision == "mapped" and matched)
      |> assign(:declined, decision == "skip")

    ~H"""
    <div class="rounded border border-gray-200 bg-white px-3 py-2 space-y-2">
      <div class="flex items-center gap-2">
        <div class="min-w-0 flex-1">
          <div class="font-medium italic text-gray-900 text-sm">{@review.extracted_name}</div>
          <div :if={@review.extracted_authority} class="text-xs text-gray-500">
            {@review.extracted_authority}
          </div>
          <div :if={@matched && @review.selected_species} class="text-xs text-green-700">
            &rarr; {@review.selected_species.name}
          </div>
        </div>

        <div :if={@already_linked} class="shrink-0">
          <.badge variant="info">already linked</.badge>
        </div>

        <div :if={!@already_linked} class="flex items-center gap-1 shrink-0">
          <button
            type="button"
            phx-click="host_accept"
            phx-value-index={@review.index}
            phx-target={@myself}
            disabled={!@matched}
            class={[
              "rounded px-2.5 py-1 text-xs font-medium transition",
              cond do
                @accepted -> "bg-green-600 text-white"
                !@matched -> "bg-gray-100 text-gray-300 cursor-not-allowed"
                true -> "bg-gray-100 text-gray-500 hover:bg-green-50 hover:text-green-700"
              end
            ]}
          >
            Accept
          </button>
          <button
            type="button"
            phx-click="host_decline"
            phx-value-index={@review.index}
            phx-target={@myself}
            class={[
              "rounded px-2.5 py-1 text-xs font-medium transition",
              if(@declined,
                do: "bg-red-600 text-white",
                else: "bg-gray-100 text-gray-500 hover:bg-red-50 hover:text-red-700"
              )
            ]}
          >
            Decline
          </button>
        </div>
      </div>

      <div :if={!@already_linked && !@matched && !@declined} class="pt-1">
        <.typeahead
          id={"host-picker-#{@review.index}"}
          label="Search host species"
          placeholder="Type to search, or enter a new name to create..."
          query={Map.get(@review, :search_query, "")}
          results={Map.get(@review, :search_results, [])}
          selected={nil}
          search_event={"host_search_#{@review.index}"}
          select_event={"host_select_#{@review.index}"}
          clear_event={"host_clear_#{@review.index}"}
          create_event={"host_create_#{@review.index}"}
          allow_new={true}
          display_fn={& &1.name}
          target={@myself}
        >
          <:result :let={species}>
            <span class="font-medium italic">{species.name}</span>
          </:result>
        </.typeahead>
      </div>
    </div>
    """
  end
end
