defmodule GallformersWeb.Admin.TaxonomyLive.RangeEditor do
  @moduledoc """
  The Host range editor (matter a856, decision 4), carried over unchanged
  from the old Host admin (`HostLive.Form`) onto the taxonomy admin: a plant
  taxon's range on the map, tri-state per place (native → introduced →
  removed), countries with subdivisions edited in the drill-down panel
  (`GallformersWeb.Admin.CountryDrillDown`), and "Refresh from POWO-WCVP",
  whose differences are reviewed (`GallformersWeb.Admin.PowoDiffReview`) and
  staged into the map. Nothing is written here: the LiveView saves the
  staged range (`entries_for_save/1`) and WCVP link (`pending_wcvp_link`)
  when the curator presses Save.

  A LiveView using it calls `init/2` on mount and `load/2` with the taxon's
  rows, and delegates to it:

    * the events in `events/0` (`handle_event/3`),
    * the drill-down's and diff review's messages (`handles_info?/1`,
      `handle_info/2`),
    * the WCVP lookups' results (`async_names/0`, `handle_async/3`),

  and renders `editor/1`. A change marks the form dirty (`:form_dirty`, as
  `GallformersWeb.Admin.FormHelpers` keeps it).
  """
  use GallformersWeb, :html

  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3, send_update: 2, start_async: 3]

  alias Gallformers.Places
  alias Gallformers.Ranges
  alias Gallformers.Wcvp
  alias GallformersWeb.Admin.CountryDrillDown
  alias GallformersWeb.Admin.PowoDiffReview
  alias Phoenix.LiveView.Socket

  @events ~w(toggle_region toggle_country refresh_from_wcvp cancel_wcvp_refresh
             wcvp_nomatch_search select_wcvp_nomatch cancel_wcvp_search continue_wcvp_search)

  @async_names [:wcvp_refresh, :wcvp_nomatch_search, :wcvp_continue]

  @doc "The events the editor handles."
  @spec events() :: [String.t()]
  def events, do: @events

  @doc "The names of the editor's async WCVP lookups."
  @spec async_names() :: [atom()]
  def async_names, do: @async_names

  defp wcvp_lookup, do: Application.get_env(:gallformers, :wcvp_lookup, Wcvp.Lookup)

  # -- state -------------------------------------------------------------------

  @doc """
  The editor's assigns, with an empty range. `opts`: `:taxon_name` (the
  name a WCVP refresh looks up) and `:wcvp_id` (the WCVP record it is
  linked to, looked up instead of the name).
  """
  @spec init(Socket.t(), keyword()) :: Socket.t()
  def init(socket, opts \\ []) do
    all_places = Places.list_all_places()

    socket
    |> assign(:all_places, all_places)
    |> assign(:place_by_code, Map.new(all_places, &{&1.code, &1}))
    |> assign(:range_taxon_name, opts[:taxon_name])
    |> assign(:range_wcvp_id, opts[:wcvp_id])
    |> assign(:powo_diff, nil)
    |> assign(:pending_wcvp_link, nil)
    |> assign(:wcvp_nomatch_search, nil)
    |> assign(:wcvp_searching, false)
    |> assign(:wcvp_loading, false)
    |> assign(:wcvp_refreshing, false)
    |> assign(:wcvp_available, wcvp_lookup().available?())
    |> assign(:wcvp_built_at, wcvp_lookup().built_at())
    |> load([])
  end

  @doc """
  Loads a range (`Gallformers.Ranges.get_places_for_taxon_with_precision/1`'s
  rows) as both the edited and the original range, dropping anything staged.
  """
  @spec load(Socket.t(), [map()]) :: Socket.t()
  def load(socket, place_entries) do
    range_entries = place_entries_to_range_entries(place_entries)

    socket
    |> assign(:range_entries, range_entries)
    |> assign(:original_range_entries, range_entries)
    |> assign(:pending_wcvp_link, nil)
    |> compute_map_range()
  end

  @doc "Sets what a WCVP refresh looks up: the taxon's name and WCVP ID."
  @spec set_lookup(Socket.t(), String.t() | nil, String.t() | nil) :: Socket.t()
  def set_lookup(socket, taxon_name, wcvp_id),
    do: assign(socket, range_taxon_name: taxon_name, range_wcvp_id: wcvp_id)

  @doc "Whether the edited range is empty."
  @spec empty?(Socket.t()) :: boolean()
  def empty?(socket), do: socket.assigns.range_entries == %{}

  @doc """
  The edited range as `Gallformers.Ranges.update_taxon_places/3` takes it:
  `{place_id, precision, distribution_type}`.
  """
  @spec entries_for_save(Socket.t()) :: [{integer(), String.t(), String.t()}]
  def entries_for_save(socket) do
    place_by_code = socket.assigns.place_by_code

    for {code, %{precision: precision, distribution_type: dt}} <- socket.assigns.range_entries,
        %{id: id} <- [Map.get(place_by_code, code)],
        do: {id, precision, dt}
  end

  defp place_entries_to_range_entries(place_entries) do
    Map.new(place_entries, fn entry ->
      {entry.code,
       %{precision: entry.precision, distribution_type: entry[:distribution_type] || "native"}}
    end)
  end

  # -- events ------------------------------------------------------------------

  @doc "Handles one of `events/0`."
  @spec handle_event(String.t(), map(), Socket.t()) :: Socket.t()
  def handle_event("toggle_region", %{"code" => code}, socket) do
    if Map.has_key?(socket.assigns.place_by_code, code) do
      socket
      |> assign(:range_entries, cycle_range_entry(socket.assigns.range_entries, code))
      |> changed()
    else
      socket
    end
  end

  def handle_event("toggle_country", %{"code" => code}, socket) do
    case Map.get(socket.assigns.place_by_code, code) do
      nil ->
        socket

      place ->
        leaf_ids = Places.leaf_descendant_ids(place.id)

        if leaf_ids == [place.id] do
          # Leaf country (no subdivisions): toggle directly as exact
          socket
          |> assign(:range_entries, cycle_range_entry(socket.assigns.range_entries, code))
          |> changed()
        else
          # Country with subdivisions: open drill-down panel
          send_update(CountryDrillDown, id: "country-drill-down", action: {:open, place})
          push_event(socket, "range-zoom-to-country", %{code: code})
        end
    end
  end

  def handle_event("refresh_from_wcvp", _params, socket) do
    wcvp_id = socket.assigns.range_wcvp_id
    name = socket.assigns.range_taxon_name

    socket
    |> assign(:wcvp_refreshing, true)
    |> start_async(:wcvp_refresh, fn ->
      case wcvp_record(wcvp_id, name) do
        nil -> {:nomatch, name, wcvp_lookup().search_contains(name, limit: 20)}
        data -> {:match, data}
      end
    end)
  end

  def handle_event("cancel_wcvp_refresh", _params, socket), do: assign(socket, :powo_diff, nil)

  def handle_event("wcvp_nomatch_search", %{"value" => query}, socket) do
    search = %{socket.assigns.wcvp_nomatch_search | query: query}
    socket = assign(socket, :wcvp_nomatch_search, search)

    if String.length(query) >= 2 do
      socket
      |> assign(:wcvp_searching, true)
      |> start_async(:wcvp_nomatch_search, fn ->
        wcvp_lookup().search_contains(query, limit: 20)
      end)
    else
      assign(socket, :wcvp_nomatch_search, %{search | results: []})
    end
  end

  def handle_event("select_wcvp_nomatch", %{"id" => plant_name_id}, socket) do
    search = %{socket.assigns.wcvp_nomatch_search | selected: plant_name_id}
    assign(socket, :wcvp_nomatch_search, search)
  end

  def handle_event("cancel_wcvp_search", _params, socket),
    do: assign(socket, :wcvp_nomatch_search, nil)

  def handle_event("continue_wcvp_search", _params, socket) do
    selected = socket.assigns.wcvp_nomatch_search.selected

    socket
    |> assign(:wcvp_loading, true)
    |> start_async(:wcvp_continue, fn -> wcvp_lookup().get(selected) end)
  end

  # The WCVP record the plant is linked to, else the one its name matches
  # (synonyms resolved), else nil.
  defp wcvp_record(wcvp_id, _name) when wcvp_id not in [nil, ""], do: wcvp_lookup().get(wcvp_id)

  defp wcvp_record(_wcvp_id, name) do
    case wcvp_lookup().match_by_name(name, resolve_synonyms: true) do
      %{plant_name_id: id} -> wcvp_lookup().get(id)
      nil -> nil
    end
  end

  # Tri-state cycle for a code in range_entries:
  # absent → native, native → introduced, introduced → removed
  defp cycle_range_entry(range_entries, code) do
    case Map.get(range_entries, code) do
      nil ->
        Map.put(range_entries, code, %{precision: "exact", distribution_type: "native"})

      %{distribution_type: "native"} ->
        Map.put(range_entries, code, %{precision: "exact", distribution_type: "introduced"})

      %{distribution_type: "introduced"} ->
        Map.delete(range_entries, code)

      # Defensive: treat unknown distribution_type as removal
      %{} ->
        Map.delete(range_entries, code)
    end
  end

  defp set_exact_entry_type(range_entries, code, distribution_type) do
    case Map.get(range_entries, code) do
      %{precision: "exact", distribution_type: ^distribution_type} ->
        Map.delete(range_entries, code)

      _ ->
        Map.put(range_entries, code, %{precision: "exact", distribution_type: distribution_type})
    end
  end

  defp replace_country_with_baseline(range_entries, country_code, distribution_type) do
    range_entries
    |> Enum.reject(fn {code, %{precision: precision}} ->
      precision == "exact" and String.starts_with?(code, "#{country_code}-")
    end)
    |> Enum.into(%{})
    |> Map.put(country_code, %{precision: "country", distribution_type: distribution_type})
  end

  # -- the drill-down's and the diff review's messages -------------------------

  @doc "Whether `message` is the drill-down's or the diff review's."
  @spec handles_info?(term()) :: boolean()
  def handles_info?({CountryDrillDown, _message}), do: true
  def handles_info?({PowoDiffReview, _message}), do: true
  def handles_info?(_message), do: false

  @doc "Handles a message `handles_info?/1` accepts."
  @spec handle_info(term(), Socket.t()) :: Socket.t()
  def handle_info({CountryDrillDown, {:set_country_level, code, type}}, socket)
      when type in ["native", "introduced"] do
    socket
    |> update(
      :range_entries,
      &Map.put(&1, code, %{precision: "country", distribution_type: type})
    )
    |> changed()
  end

  def handle_info({CountryDrillDown, {:set_country_level, code, false}}, socket) do
    socket
    |> update(:range_entries, &Map.delete(&1, code))
    |> changed()
  end

  def handle_info({CountryDrillDown, {:set_exact_type, code, type}}, socket)
      when type in ["native", "introduced"] do
    socket
    |> update(:range_entries, &set_exact_entry_type(&1, code, type))
    |> changed()
  end

  def handle_info({CountryDrillDown, {:select_all_exact, codes}}, socket) do
    new_entries =
      Enum.reduce(codes, socket.assigns.range_entries, fn code, acc ->
        Map.put_new(acc, code, %{precision: "exact", distribution_type: "native"})
      end)

    socket |> assign(:range_entries, new_entries) |> changed()
  end

  def handle_info({CountryDrillDown, {:set_all_exact_type, codes, type}}, socket)
      when type in ["native", "introduced"] do
    new_entries =
      Enum.reduce(codes, socket.assigns.range_entries, fn code, acc ->
        Map.put(acc, code, %{precision: "exact", distribution_type: type})
      end)

    socket |> assign(:range_entries, new_entries) |> changed()
  end

  def handle_info({CountryDrillDown, {:deselect_all_exact, codes}}, socket) do
    socket
    |> update(:range_entries, &Map.drop(&1, codes))
    |> changed()
  end

  def handle_info({CountryDrillDown, {:replace_with_country_baseline, code, type}}, socket)
      when type in ["native", "introduced"] do
    socket
    |> update(:range_entries, &replace_country_with_baseline(&1, code, type))
    |> changed()
  end

  def handle_info({CountryDrillDown, :zoom_out}, socket),
    do: push_event(socket, "range-zoom-out", %{})

  def handle_info({PowoDiffReview, {:apply, selections}}, socket) do
    diff = socket.assigns.powo_diff
    range_entries = apply_powo_selections(socket.assigns.range_entries, diff, selections)

    socket
    |> assign(:range_entries, range_entries)
    |> assign(:pending_wcvp_link, %{
      wcvp_id: diff.wcvp_data.plant_name_id,
      powo_id: diff.wcvp_data.powo_id,
      wcvp_synced_at: DateTime.utc_now(:second)
    })
    |> assign(:powo_diff, nil)
    |> changed()
    |> put_flash(:info, "WCVP range data staged. Press Save to apply.")
  end

  def handle_info({PowoDiffReview, :cancel}, socket), do: assign(socket, :powo_diff, nil)

  # -- the WCVP lookups --------------------------------------------------------

  @doc "Handles the result of one of `async_names/0`."
  @spec handle_async(atom(), term(), Socket.t()) :: Socket.t()
  def handle_async(:wcvp_refresh, {:ok, {:match, data}}, socket) do
    socket
    |> assign(:wcvp_refreshing, false)
    |> assign(:powo_diff, build_powo_diff(data, socket.assigns.range_entries))
  end

  def handle_async(:wcvp_refresh, {:ok, {:nomatch, name, results}}, socket) do
    socket
    |> assign(:wcvp_refreshing, false)
    |> assign(:wcvp_nomatch_search, %{query: name, results: results, selected: nil})
  end

  def handle_async(:wcvp_refresh, {:exit, _reason}, socket) do
    socket
    |> assign(:wcvp_refreshing, false)
    |> put_flash(:error, "WCVP refresh failed. Please try again.")
  end

  def handle_async(:wcvp_nomatch_search, {:ok, results}, socket) do
    socket
    |> assign(:wcvp_searching, false)
    |> update(:wcvp_nomatch_search, &%{&1 | results: results})
  end

  def handle_async(:wcvp_nomatch_search, {:exit, _reason}, socket),
    do: assign(socket, :wcvp_searching, false)

  def handle_async(:wcvp_continue, {:ok, nil}, socket) do
    socket
    |> assign(:wcvp_loading, false)
    |> put_flash(:error, "WCVP species not found")
  end

  def handle_async(:wcvp_continue, {:ok, data}, socket) do
    socket
    |> assign(:wcvp_loading, false)
    |> assign(:wcvp_nomatch_search, nil)
    |> assign(:powo_diff, build_powo_diff(data, socket.assigns.range_entries))
  end

  def handle_async(:wcvp_continue, {:exit, _reason}, socket) do
    socket
    |> assign(:wcvp_loading, false)
    |> put_flash(:error, "WCVP lookup failed. Please try again.")
  end

  # -- the WCVP diff -----------------------------------------------------------

  # Converts WCVP data to a POWO diff map with :wcvp_data attached.
  defp build_powo_diff(wcvp_data, range_entries) do
    tdwg_lookup = Wcvp.Tdwg.load()
    native_places = Wcvp.Tdwg.convert_tdwg_codes(wcvp_data.native_distribution, tdwg_lookup)
    native_codes = Ranges.expand_place_entries_to_leaf_codes(native_places)

    introduced_places =
      Wcvp.Tdwg.convert_tdwg_codes(wcvp_data.introduced_distribution, tdwg_lookup)

    introduced_codes = Ranges.expand_place_entries_to_leaf_codes(introduced_places)

    powo_precision_by_code =
      native_places
      |> Kernel.++(introduced_places)
      |> Map.new(fn %{code: code, precision: precision} -> {code, precision} end)

    current_leaf_sources_by_code = Ranges.expand_range_entries_to_leaf_status(range_entries)

    current_leaf_range_entries =
      Map.new(current_leaf_sources_by_code, fn {code, %{distribution_type: distribution_type}} ->
        {code, %{precision: "exact", distribution_type: distribution_type}}
      end)

    current_leaf_range_entries
    |> Ranges.Wcvp.compute_powo_diff(native_codes, introduced_codes)
    |> Map.put(:powo_precision_by_code, powo_precision_by_code)
    |> Map.put(:current_leaf_sources_by_code, current_leaf_sources_by_code)
    |> Map.put(:wcvp_data, wcvp_data)
  end

  # Applies user selections from PowoDiffReview to range_entries.
  # For add_native/add_introduced: selected codes get added.
  # For remove: selected codes are KEPT (unselected get removed).
  # For reclassify: selected codes change distribution_type.
  defp apply_powo_selections(range_entries, diff, selections) do
    remove_as_introduced = Map.get(selections, :remove_as_introduced, MapSet.new())
    powo_precision_by_code = Map.get(diff, :powo_precision_by_code, %{})

    range_entries
    |> materialize_country_level_entries(diff, selections, remove_as_introduced)
    |> add_codes(selections.add_native, "native", powo_precision_by_code)
    |> add_codes(selections.add_introduced, "introduced", powo_precision_by_code)
    |> remove_unselected(diff.remove, selections.remove)
    |> reclassify_codes(selections.reclassify_to_introduced, "introduced")
    |> reclassify_codes(selections.reclassify_to_native, "native")
    |> reclassify_codes(remove_as_introduced, "introduced")
  end

  defp add_codes(entries, codes, dist_type, precision_by_code) do
    Enum.reduce(codes, entries, fn code, acc ->
      Map.put(acc, code, %{
        precision: Map.get(precision_by_code, code, "exact"),
        distribution_type: dist_type
      })
    end)
  end

  defp materialize_country_level_entries(entries, diff, selections, remove_as_introduced) do
    current_leaf_sources = Map.get(diff, :current_leaf_sources_by_code, %{})

    removed_codes =
      diff.remove
      |> MapSet.new()
      |> MapSet.difference(selections.remove)

    changed_leaf_codes =
      Enum.reduce(
        [
          removed_codes,
          selections.reclassify_to_introduced,
          selections.reclassify_to_native,
          remove_as_introduced
        ],
        MapSet.new(),
        &MapSet.union/2
      )

    countries_to_materialize =
      Enum.reduce(changed_leaf_codes, MapSet.new(), fn code, acc ->
        case Map.get(current_leaf_sources, code) do
          %{source_precision: "country", source_code: source_code} ->
            MapSet.put(acc, source_code)

          _ ->
            acc
        end
      end)

    Enum.reduce(countries_to_materialize, entries, fn country_code, acc ->
      inherited_leaf_entries =
        Enum.filter(current_leaf_sources, fn
          {_leaf_code, %{source_precision: "country", source_code: ^country_code}} -> true
          _ -> false
        end)

      Enum.reduce(inherited_leaf_entries, Map.delete(acc, country_code), fn
        {leaf_code, %{distribution_type: distribution_type}}, materialized ->
          Map.put_new(materialized, leaf_code, %{
            precision: "exact",
            distribution_type: distribution_type
          })
      end)
    end)
  end

  defp remove_unselected(entries, all_removable, kept) do
    actually_remove = MapSet.difference(MapSet.new(all_removable), kept)
    Enum.reduce(actually_remove, entries, fn code, acc -> Map.delete(acc, code) end)
  end

  defp reclassify_codes(entries, codes, new_dist_type) do
    Enum.reduce(codes, entries, fn code, acc ->
      case Map.get(acc, code) do
        nil -> acc
        entry -> Map.put(acc, code, %{entry | distribution_type: new_dist_type})
      end
    end)
  end

  # -- the map -----------------------------------------------------------------

  defp changed(socket) do
    socket
    |> compute_map_range()
    |> assign(:form_dirty, true)
  end

  # Computes @in_range (exact codes) and @inherited_range (expanded country codes)
  # for the map display. Called after every change to the range entries.
  defp compute_map_range(socket) do
    place_by_code = socket.assigns.place_by_code

    host_ranges =
      for {code, %{precision: precision, distribution_type: dt}} <- socket.assigns.range_entries,
          %{id: id} <- [Map.get(place_by_code, code)],
          do: %{code: code, precision: precision, place_id: id, distribution_type: dt}

    display = Ranges.compute_display_range(host_ranges, with_introduced: true)
    range_bounds = Places.get_bounds_for_codes(display.in_range ++ display.inherited_range)

    socket
    |> assign(:in_range, display.in_range)
    |> assign(:inherited_range, display.inherited_range)
    |> assign(:introduced_range, display.introduced_range)
    |> assign(:range_bounds, range_bounds)
  end

  # -- rendering ---------------------------------------------------------------

  @doc """
  The editor: "Refresh from POWO-WCVP" (with `refreshable`), the staged
  diff's review, the legend, the editable map with the drill-down panel,
  and the no-match search. Its attributes are `init/2`'s assigns of the
  same names.
  """
  attr :refreshable, :boolean, default: true, doc: "whether WCVP refresh is offered"
  attr :range_taxon_name, :string, default: nil
  attr :range_entries, :map, required: true
  attr :all_places, :list, required: true
  attr :place_by_code, :map, required: true
  attr :in_range, :list, required: true
  attr :inherited_range, :list, required: true
  attr :introduced_range, :list, required: true
  attr :range_bounds, :any, required: true
  attr :powo_diff, :map, default: nil
  attr :wcvp_nomatch_search, :map, default: nil
  attr :wcvp_available, :boolean, default: false
  attr :wcvp_refreshing, :boolean, default: false
  attr :wcvp_searching, :boolean, default: false
  attr :wcvp_loading, :boolean, default: false

  def editor(assigns) do
    ~H"""
    <div id="host-range-editor">
      <%!-- WCVP Refresh --%>
      <div :if={@refreshable && @wcvp_available} class="mb-4">
        <%= if @wcvp_refreshing do %>
          <div id="wcvp-refresh-loading" class="flex items-center gap-2 text-sm text-gray-500">
            <.loading_spinner size="sm" label="Refreshing from WCVP..." />
            <span>Refreshing from WCVP...</span>
          </div>
        <% else %>
          <.button
            :if={is_nil(@powo_diff)}
            id="refresh-from-wcvp"
            phx-click="refresh_from_wcvp"
            type="button"
            variant="secondary"
            size="sm"
          >
            Refresh from POWO-WCVP
          </.button>
        <% end %>
      </div>

      <%!-- PowoDiffReview: wrapped to stop change events from bubbling
           to an enclosing form's phx-change, which triggers form recovery
           and resets checkbox state. --%>
      <div :if={@powo_diff} onchange="event.stopPropagation()" oninput="event.stopPropagation()">
        <.live_component
          module={PowoDiffReview}
          id="powo-diff"
          diff={@powo_diff}
          place_by_code={@place_by_code}
        />
      </div>

      <%!-- Range Map Section --%>
      <div class="mb-3 border border-gray-300 rounded">
        <div class="grid grid-cols-6 gap-2 p-3">
          <%!-- Legend --%>
          <div class="col-span-1">
            <div class="text-sm font-medium text-gray-700 mb-2">Legend:</div>
            <.range_map_legend mode={:host_admin} />
          </div>
          <%!-- Map + Drill-down panel --%>
          <div class="col-span-5">
            <label class="gf-label">Range:</label>
            <div class="flex">
              <div class="flex-1">
                <.range_map
                  id="host-range-map"
                  in_range={@in_range}
                  inherited_range={@inherited_range}
                  introduced_range={@introduced_range}
                  bounds={@range_bounds}
                  editable
                  class="border border-gray-300 rounded bg-gray-50 min-h-[500px]"
                />
              </div>
              <.live_component
                module={CountryDrillDown}
                id="country-drill-down"
                range_entries={@range_entries}
                all_places={@all_places}
              />
            </div>
          </div>
        </div>
      </div>

      <.modal
        :if={@wcvp_nomatch_search}
        id="wcvp-nomatch-modal"
        show
        on_cancel={JS.push("cancel_wcvp_search")}
        class="gf-modal-md"
      >
        <:header>No exact match found</:header>
        <:body>
          <p class="text-gray-600 mb-4">
            No exact match found in WCVP for <span class="italic font-medium">{@range_taxon_name}</span>. Search below to find the correct entry.
          </p>
          <div id="wcvp-nomatch-search">
            <input
              type="text"
              value={@wcvp_nomatch_search.query}
              phx-keyup="wcvp_nomatch_search"
              phx-debounce="300"
              placeholder="Search WCVP..."
              class="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
              autofocus
            />
            <div
              :if={@wcvp_searching}
              id="wcvp-nomatch-loading"
              class="flex items-center gap-2 mt-2 text-sm text-gray-500"
            >
              <.loading_spinner size="sm" label="Searching..." />
              <span>Searching...</span>
            </div>
            <ul
              :if={!@wcvp_searching && @wcvp_nomatch_search.results != []}
              class="mt-2 max-h-60 overflow-y-auto border border-gray-200 rounded-md divide-y divide-gray-100"
            >
              <li
                :for={result <- @wcvp_nomatch_search.results}
                phx-click="select_wcvp_nomatch"
                phx-value-id={result.plant_name_id}
                class={[
                  "px-3 py-2 cursor-pointer text-sm hover:bg-blue-50",
                  @wcvp_nomatch_search.selected == result.plant_name_id &&
                    "bg-blue-100 font-medium"
                ]}
              >
                <span class="italic">{result.taxon_name}</span>
              </li>
            </ul>
            <p
              :if={
                !@wcvp_searching && @wcvp_nomatch_search.results == [] &&
                  String.length(@wcvp_nomatch_search.query) >= 2
              }
              class="mt-2 text-sm text-gray-500"
            >
              No results found.
            </p>
          </div>
        </:body>
        <:footer>
          <button
            type="button"
            phx-click="cancel_wcvp_search"
            class="px-4 py-2 text-gray-700 border border-gray-300 rounded-md hover:bg-gray-50"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click="continue_wcvp_search"
            disabled={is_nil(@wcvp_nomatch_search.selected) || @wcvp_loading}
            class={[
              "px-4 py-2 rounded-md",
              if(@wcvp_nomatch_search.selected && !@wcvp_loading,
                do: "bg-blue-600 text-white hover:bg-blue-700",
                else: "bg-gray-300 text-gray-500 cursor-not-allowed"
              )
            ]}
          >
            <%= if @wcvp_loading do %>
              <span class="flex items-center gap-2">
                <.loading_spinner size="sm" label="Loading..." /> Loading...
              </span>
            <% else %>
              Continue
            <% end %>
          </button>
        </:footer>
      </.modal>
    </div>
    """
  end
end
