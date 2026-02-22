defmodule GallformersWeb.Admin.ExclusionDrillDown do
  @moduledoc """
  LiveComponent for the exclusion drill-down panel in the gall-host admin page.

  When a curator clicks a country on the gall range map, this panel slides in
  showing checkboxes for each subdivision. Checked = excluded from range.
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
    subdivisions =
      Places.get_children(country.id)
      |> Enum.sort_by(& &1.name)

    {:ok,
     assign(socket,
       open: true,
       country: country,
       subdivisions: subdivisions
     )}
  end

  def update(assigns, socket) do
    {:ok,
     assign(
       socket,
       Map.take(assigns, [:excluded_place_ids, :host_places, :all_places, :id])
     )}
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
  def handle_event("exclude_all", _params, socket) do
    codes = Enum.map(socket.assigns.subdivisions, & &1.code)
    notify_parent({:exclude_all, codes})
    {:noreply, socket}
  end

  @impl true
  def handle_event("include_all", _params, socket) do
    codes = Enum.map(socket.assigns.subdivisions, & &1.code)
    notify_parent({:include_all, codes})
    {:noreply, socket}
  end

  defp notify_parent(message) do
    send(self(), {__MODULE__, message})
  end

  defp excluded?(code, excluded_place_ids, all_places) do
    case Enum.find(all_places, &(&1.code == code)) do
      %{id: id} -> id in excluded_place_ids
      nil -> false
    end
  end

  defp in_host_range?(code, host_places) do
    code in host_places
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={[
      "transition-all duration-300 overflow-hidden",
      if(@open, do: "w-80 border-l border-gray-200", else: "w-0")
    ]}>
      <div :if={@open} class="p-4 h-full overflow-y-auto">
        <%!-- Header --%>
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold text-gray-900">{@country.name}</h3>
          <button
            type="button"
            phx-click="close"
            phx-target={@myself}
            class="text-gray-400 hover:text-gray-600"
            aria-label="Close panel"
          >
            <.icon name="ph-x" class="size-5" />
          </button>
        </div>

        <p class="text-xs text-gray-500 mb-3">
          Check states to exclude them from this gall's range.
        </p>

        <%!-- Bulk buttons --%>
        <div class="flex gap-2 mb-3">
          <button
            type="button"
            phx-click="exclude_all"
            phx-target={@myself}
            class="text-xs px-2 py-1 rounded border border-gray-300 hover:bg-gray-50"
          >
            Exclude all
          </button>
          <button
            type="button"
            phx-click="include_all"
            phx-target={@myself}
            class="text-xs px-2 py-1 rounded border border-gray-300 hover:bg-gray-50"
          >
            Include all
          </button>
        </div>

        <%!-- Subdivision list --%>
        <ul class="space-y-1">
          <li :for={subdiv <- @subdivisions} class="flex items-center">
            <label class={[
              "flex items-center gap-2 w-full px-2 py-1.5 rounded text-sm cursor-pointer hover:bg-gray-50",
              excluded?(subdiv.code, @excluded_place_ids, @all_places) && "bg-red-50",
              !excluded?(subdiv.code, @excluded_place_ids, @all_places) &&
                in_host_range?(subdiv.code, @host_places) && "bg-green-50"
            ]}>
              <input
                type="checkbox"
                checked={excluded?(subdiv.code, @excluded_place_ids, @all_places)}
                phx-click="toggle_exclusion"
                phx-target={@myself}
                phx-value-code={subdiv.code}
                class="rounded border-gray-300 text-red-600 focus:ring-red-500"
              />
              <span>{subdiv.name}</span>
              <span class="ml-auto text-xs text-gray-400">{subdiv.code}</span>
            </label>
          </li>
        </ul>
      </div>
    </div>
    """
  end
end
