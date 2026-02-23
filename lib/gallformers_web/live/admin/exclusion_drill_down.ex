defmodule GallformersWeb.Admin.ExclusionDrillDown do
  @moduledoc """
  LiveComponent for the exclusion drill-down panel in the gall-host admin page.

  When a curator clicks a country on the gall range map, this panel slides in
  showing checkboxes for each subdivision. Checked = in range, unchecked = excluded.
  """
  use GallformersWeb, :live_component

  alias Gallformers.Places

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       open: false,
       country: nil,
       subdivisions: []
     )}
  end

  @impl true
  def update(%{action: {:open, country}}, socket) do
    host_places = socket.assigns.host_places

    # Only show subdivisions that are in the host range
    subdivisions =
      Places.get_children(country.id)
      |> Enum.filter(&(&1.code in host_places))
      |> Enum.sort_by(& &1.name)

    {:ok,
     assign(socket,
       open: true,
       country: country,
       subdivisions: subdivisions
     )}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(:id, assigns.id)
      |> assign(:host_places, assigns.host_places)
      |> assign(:excluded_place_ids, assigns.excluded_place_ids)
      |> assign(:all_places, assigns.all_places)

    # Precompute excluded codes MapSet for O(1) lookups in template
    excluded_codes =
      assigns.all_places
      |> Enum.filter(&(&1.id in assigns.excluded_place_ids))
      |> MapSet.new(& &1.code)

    {:ok, assign(socket, :excluded_codes, excluded_codes)}
  end

  @impl true
  def handle_event("close", _params, socket) do
    notify_parent(:zoom_out)
    {:noreply, assign(socket, open: false, country: nil)}
  end

  @impl true
  def handle_event("toggle_exclusion", %{"code" => code}, socket) do
    notify_parent({:toggle_exclusion, code})
    {:noreply, socket}
  end

  @impl true
  def handle_event("include_all", _params, socket) do
    codes = Enum.map(socket.assigns.subdivisions, & &1.code)
    notify_parent({:include_all, codes})
    {:noreply, socket}
  end

  @impl true
  def handle_event("exclude_all", _params, socket) do
    codes = Enum.map(socket.assigns.subdivisions, & &1.code)
    notify_parent({:exclude_all, codes})
    {:noreply, socket}
  end

  defp notify_parent(message) do
    send(self(), {__MODULE__, message})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.drill_down_panel
        open={@open}
        country_name={@country && @country.name}
        on_close="close"
        target={@myself}
      >
        <:header_extra>
          <p class="text-xs text-gray-500 mb-2">
            Uncheck states to exclude them from this gall's range.
          </p>
          <div class="flex gap-2 mb-3">
            <button
              type="button"
              phx-click="include_all"
              phx-target={@myself}
              class="text-xs text-green-700 hover:text-green-900 underline"
            >
              Select All
            </button>
            <span class="text-xs text-gray-300">|</span>
            <button
              type="button"
              phx-click="exclude_all"
              phx-target={@myself}
              class="text-xs text-red-700 hover:text-red-900 underline"
            >
              Deselect All
            </button>
          </div>
        </:header_extra>

        <%!-- Subdivision list --%>
        <ul class="space-y-1">
          <li :for={subdiv <- @subdivisions} class="flex items-center">
            <label class={[
              "flex items-center gap-2 w-full px-2 py-1.5 rounded text-sm cursor-pointer hover:bg-gray-50",
              MapSet.member?(@excluded_codes, subdiv.code) && "bg-red-50",
              !MapSet.member?(@excluded_codes, subdiv.code) && "bg-green-50"
            ]}>
              <input
                type="checkbox"
                checked={!MapSet.member?(@excluded_codes, subdiv.code)}
                phx-click="toggle_exclusion"
                phx-target={@myself}
                phx-value-code={subdiv.code}
                class="rounded border-gray-300 text-green-600 focus:ring-green-500"
              />
              <span>{subdiv.name}</span>
              <span class="ml-auto text-xs text-gray-400">{subdiv.code}</span>
            </label>
          </li>
        </ul>
      </.drill_down_panel>
    </div>
    """
  end
end
