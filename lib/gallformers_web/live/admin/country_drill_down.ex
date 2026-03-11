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
       country_level_on: false,
       country_dist_type: "native",
       exact_places: MapSet.new(),
       introduced_places: MapSet.new()
     )}
  end

  @impl true
  def update(%{action: {:open, country}}, socket) do
    subdivisions =
      Places.get_children(country.id)
      |> Enum.sort_by(& &1.name)

    range_entries = socket.assigns[:range_entries] || %{}
    country_entry = Map.get(range_entries, country.code)
    country_level_on = country_entry != nil and country_entry.precision == "country"

    country_dist_type =
      if country_entry, do: Map.get(country_entry, :distribution_type, "native"), else: "native"

    exact_codes = for({code, %{precision: "exact"}} <- range_entries, do: code) |> MapSet.new()

    introduced_codes =
      for({code, %{distribution_type: "introduced"}} <- range_entries, do: code) |> MapSet.new()

    {:ok,
     assign(socket,
       open: true,
       country: country,
       subdivisions: subdivisions,
       country_level_on: country_level_on,
       country_dist_type: country_dist_type,
       exact_places: exact_codes,
       introduced_places: introduced_codes
     )}
  end

  def update(assigns, socket) do
    range_entries = Map.get(assigns, :range_entries, socket.assigns[:range_entries] || %{})
    exact_codes = for({code, %{precision: "exact"}} <- range_entries, do: code) |> MapSet.new()

    introduced_codes =
      for({code, %{distribution_type: "introduced"}} <- range_entries, do: code) |> MapSet.new()

    {:ok,
     socket
     |> assign(Map.take(assigns, [:range_entries, :all_places, :id]))
     |> assign(:exact_places, exact_codes)
     |> assign(:introduced_places, introduced_codes)}
  end

  @impl true
  def handle_event("close", _params, socket) do
    notify_parent(:zoom_out)
    {:noreply, assign(socket, open: false, country: nil)}
  end

  @impl true
  def handle_event("toggle_country_level", _params, socket) do
    code = socket.assigns.country.code

    if socket.assigns.country_level_on do
      notify_parent({:set_country_level, code, false})
      {:noreply, assign(socket, country_level_on: false)}
    else
      type = socket.assigns.country_dist_type
      notify_parent({:set_country_level, code, type})
      {:noreply, assign(socket, country_level_on: true)}
    end
  end

  @impl true
  def handle_event("set_country_type", %{"type" => type}, socket)
      when type in ["native", "introduced"] do
    code = socket.assigns.country.code
    notify_parent({:set_country_level, code, type})
    {:noreply, assign(socket, country_dist_type: type)}
  end

  @impl true
  def handle_event("toggle_subdivision", %{"code" => code}, socket) do
    notify_parent({:cycle_entry, code})
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    codes = Enum.map(socket.assigns.subdivisions, & &1.code)
    notify_parent({:select_all_exact, codes})
    {:noreply, socket}
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    codes = Enum.map(socket.assigns.subdivisions, & &1.code)
    notify_parent({:deselect_all_exact, codes})
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
          <%!-- Country-level toggle --%>
          <div class="mb-4 p-3 bg-gray-50 rounded-lg">
            <label class="flex items-center justify-between cursor-pointer">
              <span class="text-sm font-medium text-gray-700">Country-level range</span>
              <.toggle
                id={"country-level-#{@country.code}"}
                name="country_level"
                checked={@country_level_on}
                form="detached"
                phx-click="toggle_country_level"
                phx-target={@myself}
              />
            </label>
            <div :if={@country_level_on} class="mt-2 flex items-center gap-2">
              <span class="text-xs text-gray-500">Type:</span>
              <button
                type="button"
                phx-click="set_country_type"
                phx-value-type="native"
                phx-target={@myself}
                class={[
                  "text-xs px-2 py-0.5 rounded-full border",
                  if(@country_dist_type == "native",
                    do: "bg-green-100 border-green-400 text-green-800 font-medium",
                    else: "border-gray-300 text-gray-500 hover:bg-gray-50"
                  )
                ]}
              >
                Native
              </button>
              <button
                type="button"
                phx-click="set_country_type"
                phx-value-type="introduced"
                phx-target={@myself}
                class={[
                  "text-xs px-2 py-0.5 rounded-full border",
                  if(@country_dist_type == "introduced",
                    do: "bg-amber-100 border-amber-400 text-amber-800 font-medium",
                    else: "border-gray-300 text-gray-500 hover:bg-gray-50"
                  )
                ]}
              >
                Introduced
              </button>
            </div>
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
        </:header_extra>

        <%!-- Subdivision list --%>
        <ul class="space-y-1">
          <li :for={subdiv <- @subdivisions} class="flex items-center">
            <button
              type="button"
              phx-click="toggle_subdivision"
              phx-target={@myself}
              phx-value-code={subdiv.code}
              class={[
                "flex items-center gap-2 w-full px-2 py-1.5 rounded text-sm cursor-pointer text-left",
                subdiv.code in @introduced_places && "bg-amber-50 hover:bg-amber-100",
                subdiv.code not in @introduced_places && subdiv.code in @exact_places &&
                  "bg-green-50 hover:bg-green-100",
                subdiv.code not in @exact_places && @country_level_on &&
                  "bg-emerald-50/50 hover:bg-emerald-100/50",
                subdiv.code not in @exact_places && !@country_level_on && "hover:bg-gray-50"
              ]}
            >
              <span class={[
                "w-4 h-4 rounded-sm shrink-0 inline-flex items-center justify-center",
                subdiv.code in @introduced_places && "bg-amber-500",
                subdiv.code not in @introduced_places && subdiv.code in @exact_places &&
                  "bg-green-500",
                subdiv.code not in @exact_places && "border-2 border-gray-300"
              ]}>
                <.icon
                  :if={subdiv.code in @exact_places}
                  name="ph-check"
                  class="size-3 text-white"
                />
              </span>
              <span>{subdiv.name}</span>
              <span
                :if={subdiv.code in @introduced_places}
                class="ml-1 text-xs text-amber-700 font-medium"
              >
                (introduced)
              </span>
              <span class="ml-auto text-xs text-gray-400">{subdiv.code}</span>
            </button>
          </li>
        </ul>
      </.drill_down_panel>
    </div>
    """
  end
end
