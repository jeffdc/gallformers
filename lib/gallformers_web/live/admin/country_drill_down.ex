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
       exact_dist_type: "native",
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
       exact_dist_type: country_dist_type,
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
    if socket.assigns.country_level_on do
      code = socket.assigns.country.code
      notify_parent({:set_country_level, code, type})
    end

    {:noreply, assign(socket, country_dist_type: type)}
  end

  @impl true
  def handle_event("set_exact_click_type", %{"type" => type}, socket)
      when type in ["native", "introduced"] do
    {:noreply, assign(socket, exact_dist_type: type)}
  end

  @impl true
  def handle_event("apply_country_baseline", _params, socket) do
    code = socket.assigns.country.code
    type = socket.assigns.country_dist_type
    notify_parent({:replace_with_country_baseline, code, type})
    {:noreply, assign(socket, country_level_on: true)}
  end

  @impl true
  def handle_event("toggle_subdivision", %{"code" => code}, socket) do
    notify_parent({:set_exact_type, code, socket.assigns.exact_dist_type})
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_all_exact_native", _params, socket) do
    codes = Enum.map(socket.assigns.subdivisions, & &1.code)
    notify_parent({:set_all_exact_type, codes, "native"})
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_all_exact_introduced", _params, socket) do
    codes = Enum.map(socket.assigns.subdivisions, & &1.code)
    notify_parent({:set_all_exact_type, codes, "introduced"})
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_all_exact", _params, socket) do
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
          <div class="mb-4 flex flex-col gap-2 rounded-panel bg-surface-2 p-3">
            <div class="flex items-center justify-between gap-2">
              <label
                for={"country-level-#{@country.code}"}
                class="cursor-pointer text-ui font-semibold text-ink-2"
              >
                Country-level range
              </label>
              <.toggle
                id={"country-level-#{@country.code}"}
                name="country_level"
                checked={@country_level_on}
                form="detached"
                phx-click="toggle_country_level"
                phx-target={@myself}
              />
            </div>
            <div :if={@country_level_on} class="flex items-center gap-2">
              <span class="text-caption text-muted">Type:</span>
              <.segmented_switch
                label="Country-level type"
                value={@country_dist_type}
                event="set_country_type"
                param="type"
                target={@myself}
                size="sm"
              >
                <:option value="native" id={"country-type-native-#{@country.code}"}>Native</:option>
                <:option value="introduced" id={"country-type-introduced-#{@country.code}"}>
                  Introduced
                </:option>
              </.segmented_switch>
            </div>
            <p :if={@country_level_on} class="text-caption text-muted">
              All states shown as probable — check individual states to mark as documented.
            </p>
            <.button
              :if={@country_level_on}
              size="sm"
              phx-click="apply_country_baseline"
              phx-target={@myself}
              class="mt-1 self-start"
            >
              Replace subdivisions with {String.capitalize(@country_dist_type)} baseline
            </.button>
          </div>

          <%!-- Exact subdivision editing --%>
          <div class="mb-3 flex flex-col gap-2 rounded-panel bg-surface-2 p-3">
            <div class="text-caption text-muted">Click counties as:</div>
            <.segmented_switch
              label="Click counties as"
              value={@exact_dist_type}
              event="set_exact_click_type"
              param="type"
              target={@myself}
              size="sm"
            >
              <:option value="native" id={"exact-type-native-#{@country.code}"}>Native</:option>
              <:option value="introduced" id={"exact-type-introduced-#{@country.code}"}>
                Introduced
              </:option>
            </.segmented_switch>
          </div>

          <%!-- Bulk buttons --%>
          <div class="mb-3 flex flex-wrap gap-2">
            <.button size="sm" phx-click="set_all_exact_native" phx-target={@myself}>
              All native
            </.button>
            <.button size="sm" phx-click="set_all_exact_introduced" phx-target={@myself}>
              All introduced
            </.button>
            <.button size="sm" phx-click="clear_all_exact" phx-target={@myself}>
              Clear all
            </.button>
          </div>
        </:header_extra>

        <%!-- Subdivision list: each row's swatch is the map legend's fill
             (documented, hatched when introduced, country-level, none). --%>
        <ul class="flex flex-col gap-1">
          <li :for={subdiv <- @subdivisions} class="flex items-center">
            <button
              type="button"
              phx-click="toggle_subdivision"
              phx-target={@myself}
              phx-value-code={subdiv.code}
              data-state={subdivision_state(subdiv.code, assigns)}
              class={[
                "flex w-full cursor-pointer items-center gap-2 rounded-ctl px-2 py-1.5 text-left text-ui text-ink",
                row_class(subdivision_state(subdiv.code, assigns))
              ]}
            >
              <span class={[
                "inline-flex size-4 shrink-0 items-center justify-center rounded-ctl",
                swatch_class(subdivision_state(subdiv.code, assigns))
              ]}>
                <.icon
                  :if={subdiv.code in @exact_places}
                  name="ph-check"
                  class="size-3 text-on-fill"
                />
              </span>
              <span>{subdiv.name}</span>
              <span
                :if={subdiv.code in @introduced_places}
                class="ml-1 text-caption font-semibold text-ink-2"
              >
                (introduced)
              </span>
              <span class="ml-auto text-caption text-muted">{subdiv.code}</span>
            </button>
          </li>
        </ul>
      </.drill_down_panel>
    </div>
    """
  end

  # A segment of the Native / Introduced choice.

  # How a subdivision stands in the range, as the map shows it.
  defp subdivision_state(code, assigns) do
    cond do
      code in assigns.introduced_places -> "introduced"
      code in assigns.exact_places -> "native"
      assigns.country_level_on -> "inherited"
      true -> "none"
    end
  end

  defp row_class("none"), do: "hover:bg-sky-soft"
  defp row_class("inherited"), do: "bg-map-country/15 hover:bg-map-country/30"
  defp row_class(_in_range), do: "bg-map-documented/15 hover:bg-map-documented/25"

  defp swatch_class("introduced"), do: "bg-map-documented gf-hatch"
  defp swatch_class("native"), do: "bg-map-documented"
  defp swatch_class("inherited"), do: "border border-line-strong bg-map-country"
  defp swatch_class("none"), do: "border border-line-strong bg-map-none"
end
