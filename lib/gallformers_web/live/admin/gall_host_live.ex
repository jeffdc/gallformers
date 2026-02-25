defmodule GallformersWeb.Admin.GallHostLive do
  @moduledoc """
  Admin tool for managing gall-host mappings and gall range exclusions.

  This is a dedicated page for the complex workflow of:
  1. Selecting a gall
  2. Managing which hosts it's associated with
  3. Managing which places are excluded from its range

  The gall's effective range = (union of all host places) - (excluded places)

  Changes are deferred until Save is clicked, following the same pattern as other
  admin edit pages. Uses DeferredChanges for host tracking and manual tracking
  for exclusion place IDs.
  """
  use GallformersWeb, :live_view
  use GallformersWeb.Admin.FormHelpers

  alias Gallformers.GallHosts
  alias Gallformers.Places
  alias Gallformers.Ranges
  alias Gallformers.Species
  alias GallformersWeb.Admin.DeferredChanges
  alias GallformersWeb.Admin.ExclusionDrillDown

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]
    all_places = Places.list_all_places()
    place_by_code = Map.new(all_places, &{&1.code, &1})
    place_by_id = Map.new(all_places, &{&1.id, &1})

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Gall-Host Mappings")
      |> assign(:all_places, all_places)
      |> assign(:place_by_code, place_by_code)
      |> assign(:place_by_id, place_by_id)
      # Gall selection state
      |> assign(:gall_search_query, "")
      |> assign(:gall_search_results, [])
      |> assign(:selected_gall, nil)
      # Host management state (deferred changes)
      |> assign(DeferredChanges.init(:hosts, []))
      |> assign(:host_search_query, "")
      |> assign(:host_search_results, [])
      |> assign(:host_dropdown_open, false)
      # Range/exclusion state (manual tracking)
      |> assign(:host_places, [])
      |> assign(:host_ranges, [])
      |> assign(:original_excluded_place_ids, [])
      |> assign(:excluded_place_ids, [])
      |> assign(:excluded_places, [])
      |> assign(:in_range, [])
      |> assign(:inherited_range, [])
      |> assign(:range_bounds, nil)
      # Form state
      |> init_form_state()

    {:ok, socket}
  end

  def close_form(socket) do
    push_navigate(socket, to: ~p"/admin")
  end

  @impl true
  def handle_params(params, _url, socket) do
    # Support ?id=123 to pre-select a gall
    case Map.get(params, "id") do
      nil ->
        {:noreply, socket}

      id_str ->
        case Integer.parse(id_str) do
          {id, ""} -> {:noreply, load_gall(socket, id)}
          _ -> {:noreply, put_flash(socket, :error, "Invalid gall ID in URL")}
        end
    end
  end

  # ============================================
  # Gall Selection Events
  # ============================================

  @impl true
  def handle_event("search_galls", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Species.search_species_by_name(query, "gall", 10)
      else
        []
      end

    {:noreply, assign(socket, gall_search_query: query, gall_search_results: results)}
  end

  @impl true
  def handle_event("select_gall", %{"id" => gall_id_str}, socket) do
    case Integer.parse(gall_id_str) do
      {gall_id, ""} ->
        socket =
          socket
          |> assign(:gall_search_query, "")
          |> assign(:gall_search_results, [])
          |> load_gall(gall_id)

        {:noreply, socket}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid gall ID")}
    end
  end

  @impl true
  def handle_event("clear_gall", _params, socket) do
    socket =
      socket
      |> assign(:selected_gall, nil)
      |> assign(DeferredChanges.init(:hosts, []))
      |> assign(:original_excluded_place_ids, [])
      |> assign(:excluded_place_ids, [])
      |> assign(:host_ranges, [])
      |> assign(:host_places, [])
      |> assign(:excluded_places, [])
      |> assign(:in_range, [])
      |> assign(:inherited_range, [])
      |> assign(:range_bounds, nil)
      |> assign(:page_title, "Gall-Host Mappings")
      |> reset_dirty()

    {:noreply, socket}
  end

  # ============================================
  # Host Management Events
  # ============================================

  @impl true
  def handle_event("search_hosts", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Species.search_species_by_name(query, "plant", 10)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:host_search_query, query)
     |> assign(:host_search_results, results)
     |> assign(:host_dropdown_open, results != [])}
  end

  @impl true
  def handle_event("open_host_dropdown", _params, socket) do
    {:noreply, assign(socket, :host_dropdown_open, true)}
  end

  @impl true
  def handle_event("close_host_dropdown", _params, socket) do
    {:noreply, assign(socket, :host_dropdown_open, false)}
  end

  @impl true
  def handle_event("add_host", %{"id" => host_id_str}, socket) do
    gall = socket.assigns.selected_gall

    with %{id: _gall_id} <- gall,
         {host_id, ""} <- Integer.parse(host_id_str) do
      # Check if host already exists in pending list
      if DeferredChanges.exists?(socket, :hosts, :host_species_id, host_id) do
        {:noreply, put_flash(socket, :error, "Host already associated")}
      else
        # Find the host in search results to get its name
        host_result = Enum.find(socket.assigns.host_search_results, &(&1.id == host_id))

        if host_result do
          socket =
            socket
            |> DeferredChanges.add_pending(
              :hosts,
              %{host_species_id: host_id, host_name: host_result.name},
              id_field: :host_relation_id
            )
            |> assign(:host_search_query, "")
            |> assign(:host_search_results, [])
            |> assign(:host_dropdown_open, false)
            |> recompute_range()
            |> push_range_update()
            |> mark_dirty()

          {:noreply, socket}
        else
          {:noreply, put_flash(socket, :error, "Host not found in search results")}
        end
      end
    else
      nil -> {:noreply, put_flash(socket, :error, "Select a gall first")}
      _ -> {:noreply, put_flash(socket, :error, "Invalid host ID")}
    end
  end

  @impl true
  def handle_event("remove_host", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {relation_id, ""} ->
        socket =
          socket
          |> DeferredChanges.remove_pending(:hosts, relation_id, id_field: :host_relation_id)
          |> recompute_range()
          |> push_range_update()
          |> mark_dirty()

        {:noreply, socket}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid relation ID")}
    end
  end

  # ============================================
  # Range/Exclusion Events
  # ============================================

  @impl true
  def handle_event("toggle_region", %{"code" => code}, socket) do
    with %{id: _gall_id} <- socket.assigns.selected_gall,
         %{id: place_id} <- Map.get(socket.assigns.place_by_code, code),
         true <- code in socket.assigns.host_places do
      {:noreply, toggle_exclusion(socket, place_id)}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_country", %{"code" => code}, socket) do
    with %{id: _gall_id} <- socket.assigns.selected_gall,
         %{id: place_id} = place <- Places.get_place_by_code(code) do
      leaf_ids = Places.leaf_descendant_ids(place_id)

      if leaf_ids == [place_id] do
        # Leaf country (no subdivisions): toggle exclusion directly
        {:noreply, toggle_exclusion(socket, place_id)}
      else
        # Country with subdivisions: open drill-down panel
        send_update(ExclusionDrillDown,
          id: "exclusion-drill-down",
          action: {:open, place}
        )

        {:noreply, push_event(socket, "range-zoom-to-country", %{code: code})}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  # ============================================
  # Save/Cancel Events
  # ============================================

  @impl true
  def handle_event("save", _params, socket) do
    gall = socket.assigns.selected_gall

    if gall do
      {hosts_to_add, hosts_to_remove} =
        DeferredChanges.compute_changes(socket, :hosts, id_field: :host_relation_id)

      case GallHosts.save_gall_host_changes(
             gall.id,
             hosts_to_add,
             hosts_to_remove,
             socket.assigns.excluded_place_ids
           ) do
        {:ok, :ok} ->
          {:noreply, socket |> load_gall(gall.id) |> put_flash(:info, "Changes saved")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to save changes")}
      end
    else
      {:noreply, put_flash(socket, :error, "No gall selected")}
    end
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(request_cancel cancel_discard confirm_discard) do
    handle_form_event(event, params, socket)
  end

  # =================================================================
  # ExclusionDrillDown callbacks
  # =================================================================

  @impl true
  def handle_info({ExclusionDrillDown, {:toggle_exclusion, code}}, socket) do
    case Map.get(socket.assigns.place_by_code, code) do
      %{id: place_id} ->
        {:noreply, toggle_exclusion(socket, place_id)}

      nil ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({ExclusionDrillDown, {:include_all, codes}}, socket) do
    place_by_code = socket.assigns.place_by_code

    place_ids_to_remove =
      codes
      |> Enum.map(&Map.get(place_by_code, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.id)

    new_excluded = Enum.reject(socket.assigns.excluded_place_ids, &(&1 in place_ids_to_remove))

    {:noreply,
     socket
     |> assign(:excluded_place_ids, new_excluded)
     |> recompute_range_from_assigns()
     |> push_range_update()
     |> mark_dirty()}
  end

  @impl true
  def handle_info({ExclusionDrillDown, {:exclude_all, codes}}, socket) do
    place_by_code = socket.assigns.place_by_code

    place_ids_to_add =
      codes
      |> Enum.map(&Map.get(place_by_code, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.id)

    new_excluded = Enum.uniq(socket.assigns.excluded_place_ids ++ place_ids_to_add)

    {:noreply,
     socket
     |> assign(:excluded_place_ids, new_excluded)
     |> recompute_range_from_assigns()
     |> push_range_update()
     |> mark_dirty()}
  end

  @impl true
  def handle_info({ExclusionDrillDown, :zoom_out}, socket) do
    {:noreply, push_event(socket, "range-zoom-out", %{})}
  end

  # ============================================
  # Helper Functions
  # ============================================

  defp load_gall(socket, gall_id) do
    case Species.get_species(gall_id) do
      nil ->
        put_flash(socket, :error, "Gall not found")

      gall ->
        if gall.taxoncode != "gall" do
          put_flash(socket, :error, "Selected species is not a gall")
        else
          hosts = GallHosts.get_hosts_for_gall(gall_id)
          excluded_place_ids = Ranges.get_excluded_place_ids_for_gall(gall_id)

          socket
          |> assign(:selected_gall, gall)
          |> assign(DeferredChanges.init(:hosts, hosts))
          |> assign(:original_excluded_place_ids, excluded_place_ids)
          |> assign(:excluded_place_ids, excluded_place_ids)
          |> recompute_range()
          |> assign(:page_title, "Gall-Host Mappings - #{gall.name}")
          |> reset_dirty()
        end
    end
  end

  # Recompute range from current hosts and exclusions (hits DB for host ranges).
  # Called when hosts change or when loading a gall from DB.
  defp recompute_range(socket) do
    host_species_ids = Enum.map(socket.assigns.hosts, & &1.host_species_id)
    host_ranges = Ranges.get_host_ranges_with_precision_for_species_ids(host_species_ids)

    excluded_codes = ids_to_codes(socket.assigns.place_by_id, socket.assigns.excluded_place_ids)

    # Clean up excluded_place_ids that no longer apply (host was removed).
    # Compute the full set of leaf codes from host_ranges to check validity.
    display = Ranges.compute_display_range(host_ranges, excluded_codes)

    all_host_codes =
      Enum.uniq(display.in_range ++ display.inherited_range ++ display.excluded_range)

    valid_excluded_codes = Enum.filter(excluded_codes, &(&1 in all_host_codes))

    valid_excluded_place_ids =
      codes_to_ids(socket.assigns.place_by_code, valid_excluded_codes)

    # Recompute with cleaned exclusions if any were removed
    display =
      if length(valid_excluded_codes) != length(excluded_codes),
        do: Ranges.compute_display_range(host_ranges, valid_excluded_codes),
        else: display

    range_bounds = Places.get_bounds_for_codes(display.in_range ++ display.inherited_range)

    socket
    |> assign(:host_ranges, host_ranges)
    |> assign(:host_places, all_host_codes)
    |> assign(:excluded_place_ids, valid_excluded_place_ids)
    |> assign(:excluded_places, valid_excluded_codes)
    |> assign(:in_range, display.in_range)
    |> assign(:inherited_range, display.inherited_range)
    |> assign(:range_bounds, range_bounds)
  end

  # Toggle a place's exclusion status (no DB query, uses cached host_ranges)
  defp toggle_exclusion(socket, place_id) do
    excluded_place_ids = socket.assigns.excluded_place_ids

    new_excluded =
      if place_id in excluded_place_ids,
        do: List.delete(excluded_place_ids, place_id),
        else: [place_id | excluded_place_ids]

    socket
    |> assign(:excluded_place_ids, new_excluded)
    |> recompute_range_from_assigns()
    |> push_range_update()
    |> mark_dirty()
  end

  # Recompute range from cached host_ranges (no DB query)
  defp recompute_range_from_assigns(socket) do
    excluded_codes = ids_to_codes(socket.assigns.place_by_id, socket.assigns.excluded_place_ids)
    display = Ranges.compute_display_range(socket.assigns.host_ranges, excluded_codes)

    all_host_codes =
      Enum.uniq(display.in_range ++ display.inherited_range ++ display.excluded_range)

    range_bounds = Places.get_bounds_for_codes(display.in_range ++ display.inherited_range)

    socket
    |> assign(:host_places, all_host_codes)
    |> assign(:excluded_places, excluded_codes)
    |> assign(:in_range, display.in_range)
    |> assign(:inherited_range, display.inherited_range)
    |> assign(:range_bounds, range_bounds)
  end

  # Push range data update to the RangeMap hook
  defp push_range_update(socket) do
    push_event(socket, "range-update", %{
      in_range: socket.assigns.in_range,
      excluded_range: socket.assigns.excluded_places,
      inherited_range: socket.assigns.inherited_range
    })
  end

  defp ids_to_codes(place_by_id, place_ids) do
    place_ids
    |> Enum.map(&Map.get(place_by_id, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.code)
  end

  defp codes_to_ids(place_by_code, codes) do
    codes
    |> Enum.map(&Map.get(place_by_code, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.id)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      current_user={@current_user}
      page_title={@page_title}
      public_url={if @selected_gall, do: ~p"/gall/#{@selected_gall.id}"}
    >
      <div class="max-w-7xl mx-auto">
        <div class="mb-4">
          <.link navigate={~p"/admin"} class="hover:underline text-sm">
            &larr; Back to Admin
          </.link>
        </div>

        <div class="bg-white border border-gray-200 rounded shadow-sm">
          <div class="px-4 py-3 border-b border-gray-200 bg-gray-50">
            <h4 class="text-lg font-semibold text-gf-maroon">Gall - Host Mappings</h4>
          </div>

          <div class="p-4">
            <%!-- Instructions --%>
            <p class="text-sm text-gray-600 mb-4">
              First select a gall. If any mappings to hosts already exist they will show up in the Host field.
              Then you can edit these mappings (add or delete).
            </p>
            <p class="text-sm text-gray-600 mb-4">
              At least one host species must exist before mapping.
              <.link navigate={~p"/admin/hosts"} class="hover:underline">
                Go add one
              </.link>
              now if you need to.
            </p>

            <%!-- Gall Selector --%>
            <div class="mb-4">
              <.typeahead
                id="gall-picker"
                label="Gall:"
                placeholder="Search for a gall..."
                query={@gall_search_query}
                results={@gall_search_results}
                selected={@selected_gall}
                search_event="search_galls"
                select_event="select_gall"
                clear_event="clear_gall"
                display_fn={& &1.name}
              >
                <:result :let={gall}>
                  <.taxon_name name={gall.name} />
                </:result>
              </.typeahead>
            </div>

            <%!-- Bidirectional Arrow --%>
            <div class="flex justify-center my-2">
              <span class="text-2xl text-gray-400">⇅</span>
            </div>

            <%!-- Hosts Multi-select --%>
            <div class="mb-4">
              <%= if @selected_gall do %>
                <.multi_select_dropdown
                  id="host-picker"
                  label="Hosts:"
                  type={:hosts}
                  search_results={@host_search_results}
                  selected={@hosts}
                  search_query={@host_search_query}
                  dropdown_open={@host_dropdown_open}
                  item_id={:host_relation_id}
                  result_id={:id}
                  selected_match_id={:host_species_id}
                  item_label={:host_name}
                  result_label={:name}
                  placeholder={if @hosts == [], do: "Search hosts...", else: "Add more..."}
                  on_search="search_hosts"
                  on_add="add_host"
                  on_remove="remove_host"
                  on_open="open_host_dropdown"
                  on_close="close_host_dropdown"
                  size="md"
                  required={true}
                />
                <p :if={@hosts == []} class="text-red-600 text-xs mt-1">
                  You must map this gall to at least one host.
                </p>
              <% else %>
                <label class="gf-label">Hosts:</label>
                <div class="flex flex-wrap gap-1 p-2 border border-gray-200 bg-gray-50 rounded min-h-[42px]">
                  <span class="text-gray-400 text-sm">Select a gall first</span>
                </div>
              <% end %>
            </div>

            <%!-- Range Section --%>
            <div class="mb-4">
              <div class="flex items-center gap-2 mb-1">
                <label class="gf-label mb-0">Range:</label>
                <span
                  class="text-gray-400 cursor-help"
                  title="By default the range for a gall is the union of all places that the selected Hosts occur in. Click on places to exclude them from the gall's range. Do not exclude places based solely on a lack of observations."
                >
                  <.icon name="ph-question" class="h-4 w-4" />
                </span>
              </div>

              <div class="border border-gray-300 rounded">
                <div class="grid grid-cols-6 gap-2 p-3">
                  <%!-- Legend and Actions --%>
                  <div class="col-span-1">
                    <div class="text-sm font-medium text-gray-700 mb-2">Legend:</div>
                    <div class="mb-4">
                      <.range_map_legend mode={:gall_admin} />
                    </div>
                  </div>

                  <%!-- Map + Drill-down panel --%>
                  <div class="col-span-5">
                    <%= if @selected_gall do %>
                      <div class="flex">
                        <div class="flex-1">
                          <.range_map
                            id="gallhost-range-map"
                            in_range={@in_range}
                            excluded_range={@excluded_places}
                            inherited_range={@inherited_range}
                            bounds={@range_bounds}
                            editable
                            class="border border-gray-300 rounded bg-gray-50 min-h-[350px]"
                          />
                        </div>
                        <.live_component
                          module={ExclusionDrillDown}
                          id="exclusion-drill-down"
                          excluded_place_ids={@excluded_place_ids}
                          host_places={@host_places}
                          all_places={@all_places}
                        />
                      </div>
                    <% else %>
                      <div class="border border-gray-300 rounded bg-gray-100 min-h-[350px] flex items-center justify-center">
                        <p class="text-gray-500 text-sm">Select a gall to see its range</p>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Range Info --%>
            <div :if={@selected_gall} class="text-sm text-gray-600 mb-4">
              <span class="font-medium">Range summary:</span>
              {length(@in_range)} confirmed, {length(@inherited_range)} country-level, {length(
                @excluded_places
              )} excluded, {length(@host_places)} total from hosts
            </div>

            <%!-- Actions --%>
            <div class="flex justify-between items-center pt-3 border-t border-gray-200">
              <div :if={@selected_gall}>
                <.link
                  navigate={~p"/gall/#{@selected_gall.id}"}
                  class="text-sm hover:underline"
                >
                  View public page
                </.link>
                <span class="mx-2 text-gray-300">|</span>
                <.link
                  navigate={~p"/admin/galls/#{@selected_gall.id}"}
                  class="text-sm hover:underline"
                >
                  Edit gall details
                </.link>
              </div>
              <div class="flex gap-2">
                <button type="button" phx-click="request_cancel" class="gf-btn gf-btn-soft">
                  Cancel
                </button>
                <button
                  type="button"
                  phx-click="save"
                  disabled={not @form_dirty or @selected_gall == nil}
                  class={[
                    "gf-btn",
                    if(@form_dirty and @selected_gall, do: "gf-btn-primary", else: "gf-btn-disabled")
                  ]}
                >
                  Save
                </button>
              </div>
            </div>
          </div>
        </div>

        <%!-- Discard confirmation modal --%>
        <.discard_confirm_modal show={@show_discard_confirm} />
      </div>
    </Layouts.admin>
    """
  end
end
