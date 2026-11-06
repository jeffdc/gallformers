defmodule GallformersWeb.Admin.PlaceDrillDown do
  @moduledoc """
  LiveComponent for place drill-down in admin range editing.

  Currently used in gall mode to drill from a country into its subdivisions
  while preserving the existing continent-navigation workflow.
  """
  use GallformersWeb, :live_component

  alias Gallformers.Places

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       mode: :gall,
       open: false,
       panel_mode: :country,
       country: nil,
       continent: nil,
       subdivisions: [],
       continent_countries: []
     )}
  end

  @impl true
  def update(%{action: {:open, country}} = assigns, socket) do
    host_places = socket.assigns.host_places

    subdivisions =
      country.id
      |> Places.get_children()
      |> filter_by_host_places(host_places)
      |> Enum.sort_by(& &1.name)

    continent =
      Places.get_ancestors(country.id)
      |> Enum.find(&(&1.type == "continent"))

    {:ok,
     socket
     |> assign_component_state(assigns)
     |> assign(
       open: true,
       panel_mode: :country,
       country: country,
       continent: continent,
       subdivisions: subdivisions
     )}
  end

  def update(assigns, socket) do
    {:ok, assign_component_state(socket, assigns)}
  end

  @impl true
  def handle_event("close", _params, socket) do
    notify_parent(:zoom_out)
    {:noreply, assign(socket, open: false, country: nil)}
  end

  @impl true
  def handle_event("toggle_place", %{"code" => code}, socket) do
    notify_parent({:toggle_place, code})
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

  @impl true
  def handle_event("include_all_continent", _params, socket) do
    notify_parent({:include_all, continent_leaf_codes(socket)})
    {:noreply, socket}
  end

  @impl true
  def handle_event("exclude_all_continent", _params, socket) do
    notify_parent({:exclude_all, continent_leaf_codes(socket)})
    {:noreply, socket}
  end

  @impl true
  def handle_event("drill_into_country", %{"code" => code}, socket) do
    host_places = socket.assigns.host_places

    case Enum.find(socket.assigns.continent_countries, &(&1.code == code)) do
      nil ->
        {:noreply, socket}

      country ->
        leaf_ids = Places.leaf_descendant_ids(country.id)

        if leaf_ids == [country.id] do
          notify_parent({:toggle_place, code})
          {:noreply, socket}
        else
          subdivisions =
            country.id
            |> Places.get_children()
            |> filter_by_host_places(host_places)
            |> Enum.sort_by(& &1.name)

          {:noreply,
           assign(socket,
             panel_mode: :country,
             country: country,
             subdivisions: subdivisions
           )}
        end
    end
  end

  @impl true
  def handle_event("navigate_to_continent", _params, socket) do
    continent = socket.assigns.continent
    host_places_set = MapSet.new(socket.assigns.host_places)

    countries =
      continent.id
      |> Places.get_children()
      |> filter_countries_by_host_places(host_places_set)
      |> Enum.sort_by(& &1.name)

    {:noreply, assign(socket, panel_mode: :continent, continent_countries: countries)}
  end

  defp assign_component_state(socket, assigns) do
    omitted_place_ids =
      Map.get(assigns, :omitted_place_ids, socket.assigns[:omitted_place_ids] || [])

    all_places = Map.get(assigns, :all_places, socket.assigns[:all_places] || [])

    omitted_codes =
      all_places
      |> Enum.filter(&(&1.id in omitted_place_ids))
      |> MapSet.new(& &1.code)

    socket
    |> assign(:id, assigns.id)
    |> assign(:mode, Map.get(assigns, :mode, socket.assigns[:mode] || :gall))
    |> assign(:host_places, Map.get(assigns, :host_places, socket.assigns[:host_places] || []))
    |> assign(:omitted_place_ids, omitted_place_ids)
    |> assign(:all_places, all_places)
    |> assign(
      :introduced_codes,
      MapSet.new(Map.get(assigns, :introduced_range, socket.assigns[:introduced_range] || []))
    )
    |> assign(:omitted_codes, omitted_codes)
  end

  defp panel_title(%{panel_mode: :continent, continent: continent}) when not is_nil(continent),
    do: continent.name

  defp panel_title(%{country: country}) when not is_nil(country), do: country.name
  defp panel_title(_), do: nil

  defp continent_leaf_codes(socket) do
    countries = socket.assigns.continent_countries
    host_places = socket.assigns.host_places

    Enum.filter(host_places, fn code ->
      Enum.any?(countries, fn country ->
        code == country.code or String.starts_with?(code, "#{country.code}-")
      end)
    end)
  end

  defp filter_by_host_places(children, []), do: children

  defp filter_by_host_places(children, host_places),
    do: Enum.filter(children, &(&1.code in host_places))

  defp filter_countries_by_host_places(countries, host_places_set) do
    if MapSet.size(host_places_set) == 0 do
      countries
    else
      Enum.filter(countries, fn country ->
        country.code in host_places_set or
          Enum.any?(host_places_set, &String.starts_with?(&1, "#{country.code}-"))
      end)
    end
  end

  defp notify_parent(message), do: send(self(), {__MODULE__, message})

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.drill_down_panel
        open={@open}
        country_name={panel_title(assigns)}
        on_close="close"
        target={@myself}
      >
        <:header_extra>
          <.button
            :if={@panel_mode == :country && @continent}
            variant="ghost"
            size="sm"
            icon="ph-arrow-up"
            phx-click="navigate_to_continent"
            phx-target={@myself}
            class="mb-2"
          >
            {@continent.name}
          </.button>

          <%= if @panel_mode == :country do %>
            <p class="mb-2 text-caption text-muted">
              Check states to include them in this gall's range.
            </p>
            <div class="mb-3 flex flex-wrap gap-2">
              <.button size="sm" phx-click="include_all" phx-target={@myself}>
                Select All
              </.button>
              <.button size="sm" phx-click="exclude_all" phx-target={@myself}>
                Deselect All
              </.button>
            </div>
          <% else %>
            <p class="mb-2 text-caption text-muted">
              Select countries to include in this gall's range.
            </p>
            <div class="mb-3 flex flex-wrap gap-2">
              <.button size="sm" phx-click="include_all_continent" phx-target={@myself}>
                Select All
              </.button>
              <.button size="sm" phx-click="exclude_all_continent" phx-target={@myself}>
                Deselect All
              </.button>
            </div>
          <% end %>
        </:header_extra>

        <%= if @panel_mode == :country do %>
          <%!-- Each row's tint is the map legend's: in the Gall's range, or
               a Host's place left out of it. --%>
          <ul class="flex flex-col gap-1">
            <li :for={subdiv <- @subdivisions} class="flex items-center">
              <label
                data-state={if subdiv.code in @omitted_codes, do: "excluded", else: "included"}
                class={[
                  "flex w-full cursor-pointer items-center gap-2 rounded-ctl px-2 py-1.5 text-ui text-ink",
                  if(subdiv.code in @omitted_codes,
                    do: "bg-map-excluded/30 hover:bg-map-excluded/50",
                    else: "bg-map-documented/15 hover:bg-map-documented/25"
                  )
                ]}
              >
                <input
                  type="checkbox"
                  checked={subdiv.code not in @omitted_codes}
                  phx-click="toggle_place"
                  phx-target={@myself}
                  phx-value-code={subdiv.code}
                  class="gf-checkbox"
                />
                <span>{subdiv.name}</span>
                <span
                  :if={subdiv.code in @introduced_codes}
                  class="ml-1 text-caption font-semibold text-ink-2"
                >
                  (introduced host range)
                </span>
              </label>
            </li>
          </ul>
        <% else %>
          <ul class="flex flex-col gap-1">
            <li :for={country <- @continent_countries} class="flex items-center">
              <button
                type="button"
                phx-click="drill_into_country"
                phx-target={@myself}
                phx-value-code={country.code}
                class="flex w-full items-center gap-2 rounded-ctl px-2 py-1.5 text-left text-ui text-ink hover:bg-sky-soft"
              >
                <span>{country.name}</span>
                <span class="ml-auto text-caption text-muted">{country.code}</span>
              </button>
            </li>
          </ul>
        <% end %>
      </.drill_down_panel>
    </div>
    """
  end
end
