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
  alias Gallformers.Repo
  alias Gallformers.Species
  alias GallformersWeb.Admin.DeferredChanges
  alias GallformersWeb.Admin.ExclusionDrillDown

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]
    all_places = Places.list_places()

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Gall-Host Mappings")
      |> assign(:all_places, all_places)
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
      |> assign(:host_places_raw, [])
      |> assign(:original_excluded_place_ids, [])
      |> assign(:excluded_place_ids, [])
      |> assign(:excluded_places, [])
      |> assign(:in_range, [])
      |> assign(:inherited_range, [])
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
      |> assign(:host_places_raw, [])
      |> assign(:inherited_range, [])
      |> assign_range_data([], [])
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
            |> recompute_host_places_and_range()
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
          |> recompute_host_places_and_range()
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
         %{id: place_id} <- Enum.find(socket.assigns.all_places, &(&1.code == code)),
         true <- code in socket.assigns.host_places do
      # Toggle in local excluded_place_ids list
      excluded_place_ids = socket.assigns.excluded_place_ids

      new_excluded_place_ids =
        if place_id in excluded_place_ids do
          List.delete(excluded_place_ids, place_id)
        else
          [place_id | excluded_place_ids]
        end

      excluded_places = place_ids_to_codes(socket.assigns.all_places, new_excluded_place_ids)

      socket =
        socket
        |> assign(:excluded_place_ids, new_excluded_place_ids)
        |> assign_range_data(socket.assigns.host_places, excluded_places)
        |> push_range_update()
        |> mark_dirty()

      {:noreply, socket}
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
        excluded_place_ids = socket.assigns.excluded_place_ids

        new_excluded_place_ids =
          if place_id in excluded_place_ids do
            List.delete(excluded_place_ids, place_id)
          else
            [place_id | excluded_place_ids]
          end

        excluded_places = place_ids_to_codes(socket.assigns.all_places, new_excluded_place_ids)

        socket =
          socket
          |> assign(:excluded_place_ids, new_excluded_place_ids)
          |> assign_range_data(socket.assigns.host_places_raw, excluded_places)
          |> push_range_update()
          |> mark_dirty()

        {:noreply, socket}
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

  @impl true
  def handle_event("select_all_places", _params, socket) do
    gall = socket.assigns.selected_gall

    if gall do
      # Select all = remove all exclusions (all host places are in range)
      socket =
        socket
        |> assign(:excluded_place_ids, [])
        |> assign_range_data(socket.assigns.host_places, [])
        |> push_range_update()
        |> mark_dirty()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("deselect_all_places", _params, socket) do
    gall = socket.assigns.selected_gall

    if gall do
      # Deselect all = exclude all host places
      all_host_place_ids =
        place_codes_to_ids(socket.assigns.all_places, socket.assigns.host_places)

      excluded_places = socket.assigns.host_places

      socket =
        socket
        |> assign(:excluded_place_ids, all_host_place_ids)
        |> assign_range_data(socket.assigns.host_places, excluded_places)
        |> push_range_update()
        |> mark_dirty()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # ============================================
  # Save/Cancel Events
  # ============================================

  @impl true
  def handle_event("save", _params, socket) do
    gall = socket.assigns.selected_gall

    if gall do
      # Compute host changes
      {hosts_to_add, hosts_to_remove} =
        DeferredChanges.compute_changes(socket, :hosts, id_field: :host_relation_id)

      # Wrap in transaction
      result =
        Repo.transaction(fn ->
          # Remove hosts
          for relation_id <- hosts_to_remove do
            GallHosts.remove_host_from_gall(relation_id)
          end

          # Add hosts
          for host <- hosts_to_add do
            GallHosts.add_host_to_gall(gall.id, host.host_species_id)
          end

          # Set exclusions (replaces existing)
          Ranges.set_range_exclusions_for_gall(gall.id, socket.assigns.excluded_place_ids)

          :ok
        end)

      case result do
        {:ok, :ok} ->
          # Refresh state from DB
          socket =
            socket
            |> load_gall(gall.id)
            |> put_flash(:info, "Changes saved")

          {:noreply, socket}

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
    case Enum.find(socket.assigns.all_places, &(&1.code == code)) do
      %{id: place_id} ->
        excluded_place_ids = socket.assigns.excluded_place_ids

        new_excluded_place_ids =
          if place_id in excluded_place_ids do
            List.delete(excluded_place_ids, place_id)
          else
            [place_id | excluded_place_ids]
          end

        excluded_places = place_ids_to_codes(socket.assigns.all_places, new_excluded_place_ids)

        socket =
          socket
          |> assign(:excluded_place_ids, new_excluded_place_ids)
          |> assign_range_data(socket.assigns.host_places_raw, excluded_places)
          |> push_range_update()
          |> mark_dirty()

        {:noreply, socket}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_info({ExclusionDrillDown, {:exclude_all, codes}}, socket) do
    place_ids =
      codes
      |> Enum.map(fn code -> Enum.find(socket.assigns.all_places, &(&1.code == code)) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.id)

    new_excluded_place_ids = Enum.uniq(socket.assigns.excluded_place_ids ++ place_ids)
    excluded_places = place_ids_to_codes(socket.assigns.all_places, new_excluded_place_ids)

    socket =
      socket
      |> assign(:excluded_place_ids, new_excluded_place_ids)
      |> assign_range_data(socket.assigns.host_places_raw, excluded_places)
      |> push_range_update()
      |> mark_dirty()

    {:noreply, socket}
  end

  def handle_info({ExclusionDrillDown, {:include_all, codes}}, socket) do
    place_ids =
      codes
      |> Enum.map(fn code -> Enum.find(socket.assigns.all_places, &(&1.code == code)) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.id)

    new_excluded_place_ids = Enum.reject(socket.assigns.excluded_place_ids, &(&1 in place_ids))
    excluded_places = place_ids_to_codes(socket.assigns.all_places, new_excluded_place_ids)

    socket =
      socket
      |> assign(:excluded_place_ids, new_excluded_place_ids)
      |> assign_range_data(socket.assigns.host_places_raw, excluded_places)
      |> push_range_update()
      |> mark_dirty()

    {:noreply, socket}
  end

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
          host_places = Ranges.get_places_for_gall(gall_id)
          excluded_place_ids = Ranges.get_excluded_place_ids_for_gall(gall_id)
          excluded_places = place_ids_to_codes(socket.assigns.all_places, excluded_place_ids)

          socket
          |> assign(:selected_gall, gall)
          |> assign(DeferredChanges.init(:hosts, hosts))
          |> assign(:original_excluded_place_ids, excluded_place_ids)
          |> assign(:excluded_place_ids, excluded_place_ids)
          |> assign_range_data(host_places, excluded_places)
          |> assign(:page_title, "Gall-Host Mappings - #{gall.name}")
          |> reset_dirty()
        end
    end
  end

  # Convert list of place IDs to list of place codes
  defp place_ids_to_codes(all_places, place_ids) do
    place_id_set = MapSet.new(place_ids)

    all_places
    |> Enum.filter(&MapSet.member?(place_id_set, &1.id))
    |> Enum.map(& &1.code)
  end

  # Convert list of place codes to list of place IDs
  defp place_codes_to_ids(all_places, codes) do
    code_set = MapSet.new(codes)

    all_places
    |> Enum.filter(&MapSet.member?(code_set, &1.code))
    |> Enum.map(& &1.id)
  end

  # Compute host places from local hosts list and update range data
  defp recompute_host_places_and_range(socket) do
    hosts = socket.assigns.hosts
    host_species_ids = Enum.map(hosts, & &1.host_species_id)
    host_places = Ranges.get_places_for_host_species_ids(host_species_ids)

    # Clean up excluded_place_ids that no longer apply (host was removed)
    excluded_place_ids = socket.assigns.excluded_place_ids
    excluded_places = place_ids_to_codes(socket.assigns.all_places, excluded_place_ids)
    valid_exclusions = Enum.filter(excluded_places, &(&1 in host_places))

    # Update excluded_place_ids to only include valid ones
    valid_excluded_place_ids = place_codes_to_ids(socket.assigns.all_places, valid_exclusions)

    socket
    |> assign(:excluded_place_ids, valid_excluded_place_ids)
    |> assign_range_data(host_places, valid_exclusions)
    |> push_range_update()
  end

  # Push range data update to the RangeMap hook
  defp push_range_update(socket) do
    push_event(socket, "range-update", %{
      in_range: socket.assigns.in_range,
      excluded_range: socket.assigns.excluded_places,
      inherited_range: socket.assigns.inherited_range
    })
  end

  # Assigns host_places, excluded_places, and computed in_range together.
  # Also computes inherited_range (leaf codes expanded from country-level host ranges).
  defp assign_range_data(socket, host_places, excluded_places) do
    # Separate exact leaf codes from country/higher-level codes
    all_places = socket.assigns.all_places
    place_by_code = Map.new(all_places, &{&1.code, &1})

    {leaf_codes, higher_codes} =
      Enum.split_with(host_places, fn code ->
        case Map.get(place_by_code, code) do
          %{type: type} when type in ["state", "province"] -> true
          # Leaf countries (no subdivisions) are also leaf codes
          %{type: "country", id: id} -> Places.leaf_descendant_ids(id) == [id]
          _ -> false
        end
      end)

    # Expand higher-level codes to their leaf descendant codes
    place_by_id = Map.new(all_places, &{&1.id, &1})

    inherited_leaf_codes =
      higher_codes
      |> Enum.flat_map(&expand_to_leaf_codes(&1, place_by_code, place_by_id))
      |> Enum.uniq()
      |> Enum.reject(&(&1 in leaf_codes))

    # All leaf codes (exact + inherited) — used for host_places and toggle logic
    all_leaf_codes = Enum.uniq(leaf_codes ++ inherited_leaf_codes)

    # Inherited codes that are in range (not excluded)
    inherited_in_range = Enum.reject(inherited_leaf_codes, &(&1 in excluded_places))

    # Exact codes that are in range (not excluded)
    exact_in_range = Enum.reject(leaf_codes, &(&1 in excluded_places))

    socket
    |> assign(:host_places, all_leaf_codes)
    |> assign(:host_places_raw, host_places)
    |> assign(:excluded_places, excluded_places)
    |> assign(:in_range, exact_in_range)
    |> assign(:inherited_range, inherited_in_range)
  end

  # Expands a higher-level place code to its leaf descendant codes
  defp expand_to_leaf_codes(code, place_by_code, place_by_id) do
    case Map.get(place_by_code, code) do
      %{id: id} ->
        id
        |> Places.leaf_descendant_ids()
        |> Enum.map(&Map.get(place_by_id, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(& &1.code)

      nil ->
        []
    end
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
                    <div class="space-y-1 mb-4">
                      <div class="flex items-center gap-2">
                        <div class="w-4 h-4 rounded border border-gray-400 bg-green-700"></div>
                        <span class="text-xs text-gray-600">Gall & Host</span>
                      </div>
                      <div class="flex items-center gap-2">
                        <div
                          class="w-4 h-4 rounded border border-gray-400"
                          style="background-color: #90EE90;"
                        >
                        </div>
                        <span class="text-xs text-gray-600">Country-level</span>
                      </div>
                      <div class="flex items-center gap-2">
                        <div class="w-4 h-4 rounded border border-gray-400 bg-red-300"></div>
                        <span class="text-xs text-gray-600">Host Only</span>
                      </div>
                      <div class="flex items-center gap-2">
                        <div class="w-4 h-4 rounded border border-gray-300 bg-white"></div>
                        <span class="text-xs text-gray-600">Neither</span>
                      </div>
                    </div>

                    <div class="text-sm font-medium text-gray-700 mb-2">Map Actions:</div>
                    <div class="space-y-2">
                      <button
                        type="button"
                        phx-click="select_all_places"
                        disabled={@selected_gall == nil}
                        class={[
                          "block w-full px-2 py-1 text-xs border border-gray-300 rounded",
                          if(@selected_gall,
                            do: "bg-gray-100 hover:bg-gray-200",
                            else: "bg-gray-50 text-gray-400 cursor-not-allowed"
                          )
                        ]}
                      >
                        Select All
                      </button>
                      <button
                        type="button"
                        phx-click="deselect_all_places"
                        disabled={@selected_gall == nil}
                        class={[
                          "block w-full px-2 py-1 text-xs border border-gray-300 rounded",
                          if(@selected_gall,
                            do: "bg-gray-100 hover:bg-gray-200",
                            else: "bg-gray-50 text-gray-400 cursor-not-allowed"
                          )
                        ]}
                      >
                        De-select All
                      </button>
                    </div>
                  </div>

                  <%!-- Map + Drill-down panel --%>
                  <div class="col-span-5">
                    <%= if @selected_gall do %>
                      <div class="flex">
                        <div class="flex-1">
                          <div
                            id="gallhost-range-map"
                            phx-hook="RangeMap"
                            phx-update="ignore"
                            data-in-range={Jason.encode!(@in_range)}
                            data-excluded-range={Jason.encode!(@excluded_places)}
                            data-inherited-range={Jason.encode!(@inherited_range)}
                            data-editable="true"
                            class="border border-gray-300 rounded bg-gray-50 min-h-[350px]"
                          >
                            <div class="flex items-center justify-center h-64 text-gray-400">
                              Loading map...
                            </div>
                          </div>
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
