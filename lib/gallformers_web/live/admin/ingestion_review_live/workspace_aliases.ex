defmodule GallformersWeb.Admin.IngestionReviewLive.WorkspaceAliases do
  use GallformersWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("toggle_alias", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    aliases = socket.assigns.workspace.extracted_aliases
    current = Enum.at(aliases, index)
    send(self(), {:alias_toggled, index, !current.accepted})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    locked = is_nil(assigns.workspace.species_review.decision)
    decision = assigns.workspace.species_review.decision
    extracted_aliases = assigns.workspace.extracted_aliases
    existing_aliases = if assigns.existing_gall, do: assigns.existing_gall.aliases, else: []

    accepted_count = Enum.count(extracted_aliases, & &1.accepted)
    total_count = length(extracted_aliases)

    existing_alias_names =
      MapSet.new(existing_aliases, &String.downcase(&1.name))

    assigns =
      assigns
      |> assign(:locked, locked)
      |> assign(:decision, decision)
      |> assign(:extracted_aliases, extracted_aliases)
      |> assign(:existing_aliases, existing_aliases)
      |> assign(:accepted_count, accepted_count)
      |> assign(:total_count, total_count)
      |> assign(:existing_alias_names, existing_alias_names)

    ~H"""
    <section id="workspace-section-aliases" class="rounded-lg border border-gray-200 p-4 space-y-4">
      <div class="flex items-center justify-between">
        <h3 class="text-base font-semibold text-gray-900">Aliases</h3>
        <.badge :if={@locked} variant="warning">Locked · resolve identity first</.badge>
        <span :if={!@locked && @total_count > 0} class="text-xs text-gray-500">
          {@accepted_count} of {@total_count} accepted
        </span>
      </div>

      <div :if={!@locked} class="space-y-4">
        <div :if={@decision == "mapped" && @existing_aliases != []} class="space-y-2">
          <div class="text-xs font-medium uppercase tracking-wide text-gray-500">
            Currently on gall
          </div>
          <div class="flex flex-wrap gap-2">
            <.badge :for={a <- @existing_aliases} variant="info">{a.name}</.badge>
          </div>
        </div>

        <div :if={@total_count > 0} class="space-y-2">
          <div class="text-xs font-medium uppercase tracking-wide text-gray-500">From source</div>
          <div class="space-y-1">
            <.alias_row
              :for={{alias_entry, index} <- Enum.with_index(@extracted_aliases)}
              alias_entry={alias_entry}
              index={index}
              already_on_gall={
                MapSet.member?(@existing_alias_names, String.downcase(alias_entry.name))
              }
              myself={@myself}
            />
          </div>
        </div>

        <p :if={@total_count == 0} class="text-sm text-gray-500">
          No aliases extracted from source.
        </p>
      </div>
    </section>
    """
  end

  attr :alias_entry, :map, required: true
  attr :index, :integer, required: true
  attr :already_on_gall, :boolean, required: true
  attr :myself, :any, required: true

  defp alias_row(assigns) do
    ~H"""
    <div class="flex items-center gap-2 rounded border border-gray-200 px-3 py-2 bg-white">
      <%= if @already_on_gall do %>
        <span class="text-sm text-gray-400 line-through">{@alias_entry.name}</span>
        <.badge variant="info">already on gall</.badge>
      <% else %>
        <button
          type="button"
          phx-click="toggle_alias"
          phx-value-index={@index}
          phx-target={@myself}
          class="flex items-center gap-2 text-sm text-gray-900 hover:text-gf-maroon"
        >
          <span class={[
            "size-4 rounded border flex items-center justify-center text-xs",
            if(@alias_entry.accepted,
              do: "bg-gf-maroon border-gf-maroon text-white",
              else: "border-gray-300"
            )
          ]}>
            <span :if={@alias_entry.accepted}>✓</span>
          </span>
          {@alias_entry.name}
        </button>
      <% end %>
    </div>
    """
  end
end
