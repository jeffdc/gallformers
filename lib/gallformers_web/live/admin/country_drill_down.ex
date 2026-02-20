defmodule GallformersWeb.Admin.CountryDrillDown do
  @moduledoc """
  LiveComponent for the country drill-down panel in admin range editing.

  When a curator clicks a country on the range map, this panel slides in
  showing:
  - A toggle for country-level range (imprecise)
  - A checkbox list of subdivisions (exact precision)
  - Select all / Deselect all bulk buttons
  """
  use GallformersWeb, :live_component

  alias Gallformers.Places

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       open: false,
       country: nil,
       subdivisions: [],
       country_level_on: false
     )}
  end

  @impl true
  def update(%{action: {:open, country}}, socket) do
    subdivisions =
      Places.get_children(country.id)
      |> Enum.sort_by(& &1.name)

    country_level_on = country.code in socket.assigns.country_places

    {:ok,
     assign(socket,
       open: true,
       country: country,
       subdivisions: subdivisions,
       country_level_on: country_level_on
     )}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, Map.take(assigns, [:exact_places, :country_places, :all_places, :id]))}
  end

  @impl true
  def handle_event("close", _params, socket) do
    notify_parent(socket, :zoom_out)
    {:noreply, assign(socket, open: false, country: nil)}
  end

  @impl true
  def handle_event("toggle_country_level", _params, socket) do
    new_val = !socket.assigns.country_level_on
    code = socket.assigns.country.code

    notify_parent(socket, {:set_country_level, code, new_val})
    {:noreply, assign(socket, country_level_on: new_val)}
  end

  @impl true
  def handle_event("toggle_subdivision", %{"code" => code}, socket) do
    notify_parent(socket, {:toggle_exact, code})
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    codes = Enum.map(socket.assigns.subdivisions, & &1.code)
    notify_parent(socket, {:select_all_exact, codes})
    {:noreply, socket}
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    codes = Enum.map(socket.assigns.subdivisions, & &1.code)
    notify_parent(socket, {:deselect_all_exact, codes})
    {:noreply, socket}
  end

  defp notify_parent(_socket, message) do
    send(self(), {__MODULE__, message})
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

        <%!-- Country-level toggle --%>
        <div class="mb-4 p-3 bg-gray-50 rounded-lg">
          <label class="flex items-center justify-between cursor-pointer">
            <span class="text-sm font-medium text-gray-700">Country-level range</span>
            <.toggle
              id={"country-level-#{@country.code}"}
              name="country_level"
              checked={@country_level_on}
              phx-click="toggle_country_level"
              phx-target={@myself}
            />
          </label>
          <p :if={@country_level_on} class="mt-2 text-xs text-gray-500">
            All states shown as probable — check individual states to mark as documented.
          </p>
        </div>

        <%!-- Bulk buttons --%>
        <div class="flex gap-2 mb-3">
          <button
            type="button"
            phx-click="select_all"
            phx-target={@myself}
            class="text-xs px-2 py-1 rounded border border-gray-300 hover:bg-gray-50"
          >
            Select all
          </button>
          <button
            type="button"
            phx-click="deselect_all"
            phx-target={@myself}
            class="text-xs px-2 py-1 rounded border border-gray-300 hover:bg-gray-50"
          >
            Deselect all
          </button>
        </div>

        <%!-- Subdivision list --%>
        <ul class="space-y-1">
          <li :for={subdiv <- @subdivisions} class="flex items-center">
            <label class={[
              "flex items-center gap-2 w-full px-2 py-1.5 rounded text-sm cursor-pointer hover:bg-gray-50",
              subdiv.code in @exact_places && "bg-green-50",
              subdiv.code not in @exact_places && @country_level_on && "bg-emerald-50/50"
            ]}>
              <input
                type="checkbox"
                checked={subdiv.code in @exact_places}
                phx-click="toggle_subdivision"
                phx-target={@myself}
                phx-value-code={subdiv.code}
                class="rounded border-gray-300 text-green-600 focus:ring-green-500"
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
