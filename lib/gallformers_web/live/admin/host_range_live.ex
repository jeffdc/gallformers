defmodule GallformersWeb.Admin.HostRangeLive do
  @moduledoc """
  Admin triage page for host range confirmation and WCVP sync.

  Shows hosts that need range review and allows bulk confirmation
  and bulk WCVP sync operations.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Plants
  alias Gallformers.Wcvp

  @page_size 50

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:current_user, session["current_user"])
      |> assign(:page_title, "Host Range Review")
      |> assign(:selected_ids, MapSet.new())
      |> assign(:syncing, nil)
      |> assign(:confirm_action, nil)
      |> assign(:sync_results, nil)
      |> assign(:page_size, @page_size)
      |> assign(:total_count, 0)
      |> assign(:hosts, [])
      |> assign(:wcvp_built_at, Wcvp.Lookup.built_at())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(
        :filter,
        parse_atom_param(params["filter"], ~w(all confirmed unconfirmed), :unconfirmed)
      )
      |> assign(:wcvp_filter, parse_atom_param(params["wcvp"], ~w(yes no all), :all))
      |> assign(:range_filter, parse_atom_param(params["range"], ~w(yes no all), :all))
      |> assign(
        :sync_status,
        parse_atom_param(params["sync_status"], ~w(never stale current all), :all)
      )
      |> assign(:search, params["search"] || "")
      |> assign(:current_page, parse_int_param(params["page"], 1))
      |> assign(:selected_ids, MapSet.new())
      |> load_hosts()

    {:noreply, socket}
  end

  # ============================================
  # Filter events
  # ============================================

  @impl true
  def handle_event("filter", %{"value" => value}, socket) do
    {:noreply, push_filter_patch(socket, filter: value, page: nil)}
  end

  @impl true
  def handle_event("wcvp_filter", %{"value" => value}, socket) do
    {:noreply, push_filter_patch(socket, wcvp: value, page: nil)}
  end

  @impl true
  def handle_event("range_filter", %{"value" => value}, socket) do
    {:noreply, push_filter_patch(socket, range: value, page: nil)}
  end

  @impl true
  def handle_event("sync_status_filter", %{"value" => value}, socket) do
    {:noreply, push_filter_patch(socket, sync_status: value, page: nil)}
  end

  @impl true
  def handle_event("search", %{"value" => value}, socket) do
    {:noreply, push_filter_patch(socket, search: value, page: nil)}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_filter_patch(socket, page: page)}
  end

  # ============================================
  # Selection events
  # ============================================

  @impl true
  def handle_event("toggle_select", %{"id" => id_str}, socket) do
    case Integer.parse(id_str) do
      {id, ""} ->
        selected = socket.assigns.selected_ids

        new_selected =
          if MapSet.member?(selected, id),
            do: MapSet.delete(selected, id),
            else: MapSet.put(selected, id)

        {:noreply, assign(socket, :selected_ids, new_selected)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    all_ids = MapSet.new(socket.assigns.hosts, & &1.id)
    {:noreply, assign(socket, :selected_ids, all_ids)}
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  # ============================================
  # Bulk actions
  # ============================================

  # Show confirmation modals
  @impl true
  def handle_event("confirm_selected", _params, socket) do
    {:noreply, assign(socket, :confirm_action, :confirm)}
  end

  @impl true
  def handle_event("sync_selected", _params, socket) do
    {:noreply, assign(socket, :confirm_action, :sync)}
  end

  @impl true
  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, assign(socket, :confirm_action, nil)}
  end

  # Execute confirmed actions
  @impl true
  def handle_event("do_confirm_selected", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)

    {count, _} = Plants.bulk_confirm_host_ranges(ids)

    socket =
      socket
      |> assign(:confirm_action, nil)
      |> assign(:selected_ids, MapSet.new())
      |> load_hosts()
      |> put_flash(:info, "Confirmed range for #{count} host(s)")

    {:noreply, socket}
  end

  @impl true
  def handle_event("do_sync_selected", _params, socket) do
    hosts = socket.assigns.hosts
    selected_ids = socket.assigns.selected_ids

    hosts_to_sync =
      Enum.filter(hosts, fn host ->
        MapSet.member?(selected_ids, host.id)
      end)

    ref_data = Plants.load_sync_ref_data()

    summary = %{synced: 0, no_match: [], failed: []}
    send(self(), {:sync_next, hosts_to_sync, summary, ref_data})

    {:noreply,
     socket
     |> assign(:confirm_action, nil)
     |> assign(:syncing, %{total: length(hosts_to_sync), done: 0})}
  end

  # Dismiss sync results modal
  @impl true
  def handle_event("dismiss_sync_results", _params, socket) do
    {:noreply, assign(socket, :sync_results, nil)}
  end

  # ============================================
  # Sync progress (handle_info)
  # ============================================

  @impl true
  def handle_info({:sync_next, [], summary, _ref_data}, socket) do
    results = %{
      synced: summary.synced,
      no_match: Enum.reverse(summary.no_match),
      failed: Enum.reverse(summary.failed)
    }

    socket =
      socket
      |> assign(:syncing, nil)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:sync_results, results)
      |> load_hosts()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:sync_next, [host | rest], summary, ref_data}, socket) do
    updated_summary =
      case Plants.sync_host_from_wcvp(host.id, ref_data) do
        {:ok, _} ->
          %{summary | synced: summary.synced + 1}

        {:error, "No WCVP match found" <> _} ->
          %{summary | no_match: [host.name | summary.no_match]}

        {:error, _reason} ->
          %{summary | failed: [host.name | summary.failed]}
      end

    send(self(), {:sync_next, rest, updated_summary, ref_data})

    {:noreply,
     assign(socket, :syncing, %{
       socket.assigns.syncing
       | done: socket.assigns.syncing.done + 1
     })}
  end

  # ============================================
  # Helpers
  # ============================================

  defp load_hosts(socket) do
    %{current_page: page, page_size: page_size} = socket.assigns

    opts = [
      filter: socket.assigns.filter,
      wcvp_match: socket.assigns.wcvp_filter,
      has_range: socket.assigns.range_filter,
      sync_status: socket.assigns.sync_status,
      search: socket.assigns.search,
      limit: page_size,
      offset: (page - 1) * page_size,
      wcvp_built_at: socket.assigns.wcvp_built_at
    ]

    hosts = Plants.list_hosts_for_range_review(opts)
    total_count = Plants.count_hosts_for_range_review(opts)

    socket
    |> assign(:hosts, hosts)
    |> assign(:total_count, total_count)
  end

  defp format_synced_at(nil), do: "Never"
  defp format_synced_at(datetime), do: format_date(datetime, :short)

  @filter_defaults %{
    filter: "unconfirmed",
    wcvp: "all",
    range: "all",
    sync_status: "all",
    search: "",
    page: "1"
  }

  defp push_filter_patch(socket, overrides) do
    current = %{
      filter: to_string(socket.assigns.filter),
      wcvp: to_string(socket.assigns.wcvp_filter),
      range: to_string(socket.assigns.range_filter),
      sync_status: to_string(socket.assigns.sync_status),
      search: socket.assigns.search,
      page: to_string(socket.assigns.current_page)
    }

    merged = Map.merge(current, Map.new(overrides, fn {k, v} -> {k, to_string(v || "")} end))

    # Only include non-default params in URL
    params =
      Enum.reduce(merged, %{}, fn {key, val}, acc ->
        if val != "" and val != Map.get(@filter_defaults, key) do
          Map.put(acc, key, val)
        else
          acc
        end
      end)

    push_patch(socket, to: ~p"/admin/host-range?#{params}")
  end

  defp parse_atom_param(nil, _valid, default), do: default
  defp parse_atom_param("", _valid, default), do: default

  defp parse_atom_param(value, valid_strings, default) do
    if value in valid_strings, do: String.to_existing_atom(value), else: default
  end

  defp parse_int_param(nil, default), do: default

  defp parse_int_param(value, default) do
    case Integer.parse(value) do
      {n, ""} when n >= 1 -> n
      _ -> default
    end
  end

  # ============================================
  # Template
  # ============================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <div class="max-w-7xl mx-auto">
        <div class="mb-4">
          <.link navigate={~p"/admin"} class="hover:underline text-sm">
            <.icon name="ph-arrow-left" class="h-4 w-4 inline" /> Back to Admin
          </.link>
        </div>

        <div class="bg-white border border-gray-200 rounded shadow-sm">
          <div class="px-4 py-3 border-b border-gray-200 bg-gray-50 flex items-center justify-between">
            <h4 class="text-lg font-semibold text-gf-maroon">Host Range Review</h4>
            <span class="text-sm text-gray-500">
              {@total_count} host(s)
              <span :if={@wcvp_built_at} class="text-xs text-gray-400 ml-2">
                WCVP data: {format_date(@wcvp_built_at, :short)}
              </span>
            </span>
          </div>

          <div class="p-4">
            <p class="text-sm text-gray-600 mb-4">
              Hosts needing range attention are listed below. Click a host name to
              edit its range, or select multiple hosts for bulk actions.
            </p>

            <%!-- Filter bar --%>
            <div class="mb-4 flex flex-wrap items-center gap-4">
              <div class="flex items-center gap-2">
                <label class="text-sm font-medium text-gray-700">Status:</label>
                <form phx-change="filter" id="filter" class="w-40">
                  <.input
                    type="select"
                    name="value"
                    options={[
                      {"Unconfirmed", "unconfirmed"},
                      {"Confirmed", "confirmed"},
                      {"All", "all"}
                    ]}
                    value={@filter}
                  />
                </form>
              </div>

              <div class="flex items-center gap-2">
                <label class="text-sm font-medium text-gray-700">WCVP:</label>
                <form phx-change="wcvp_filter" id="wcvp_filter" class="w-30">
                  <.input
                    type="select"
                    name="value"
                    options={[{"All", "all"}, {"Has match", "yes"}, {"No match", "no"}]}
                    value={@wcvp_filter}
                  />
                </form>
              </div>

              <div class="flex items-center gap-2">
                <label class="text-sm font-medium text-gray-700">Range:</label>
                <form phx-change="range_filter" id="range_filter" class="w-35">
                  <.input
                    type="select"
                    name="value"
                    options={[{"All", "all"}, {"Has range", "yes"}, {"No range", "no"}]}
                    value={@range_filter}
                  />
                </form>
              </div>

              <div class="flex items-center gap-2">
                <label class="text-sm font-medium text-gray-700">Sync:</label>
                <form phx-change="sync_status_filter" id="sync_status_filter" class="w-35">
                  <.input
                    type="select"
                    name="value"
                    options={[
                      {"All", "all"},
                      {"Never synched", "never"},
                      {"Stale", "stale"},
                      {"Current", "current"}
                    ]}
                    value={@sync_status}
                  />
                </form>
              </div>

              <.search_input
                id="host-range-search"
                name="value"
                value={@search}
                placeholder="Search by host name, genus, or family..."
                size={:sm}
                phx-keyup="search"
                phx-debounce="300"
              />
            </div>

            <%!-- Sync progress bar --%>
            <div :if={@syncing} class="mb-4 p-3 bg-blue-50 border border-blue-200 rounded">
              <div class="flex items-center gap-2 text-sm text-blue-800">
                <.icon name="ph-arrows-clockwise" class="h-4 w-4 animate-spin" />
                Syncing from WCVP: {@syncing.done} / {@syncing.total}
              </div>
              <div class="mt-2 w-full bg-blue-200 rounded-full h-2">
                <div
                  class="bg-blue-600 h-2 rounded-full transition-all"
                  style={"width: #{if @syncing.total > 0, do: @syncing.done / @syncing.total * 100, else: 0}%"}
                >
                </div>
              </div>
            </div>

            <%!-- Bulk actions --%>
            <div
              :if={MapSet.size(@selected_ids) > 0 and is_nil(@syncing)}
              class="mb-4 flex items-center gap-3"
            >
              <button
                type="button"
                phx-click="confirm_selected"
                class="gf-btn gf-btn-primary text-sm"
              >
                <.icon name="ph-check" class="h-4 w-4 inline" />
                Confirm Selected ({MapSet.size(@selected_ids)})
              </button>
              <button
                type="button"
                phx-click="sync_selected"
                class="gf-btn gf-btn-secondary text-sm"
              >
                <.icon name="ph-arrows-clockwise" class="h-4 w-4 inline" /> Sync Selected from WCVP
              </button>
              <button
                type="button"
                phx-click="deselect_all"
                class="text-sm text-gray-600 hover:underline"
              >
                Clear selection
              </button>
            </div>

            <%!-- Table --%>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-gray-200 text-left">
                    <th class="pb-2 pr-4 w-8">
                      <input
                        type="checkbox"
                        checked={MapSet.size(@selected_ids) == length(@hosts) and length(@hosts) > 0}
                        phx-click={
                          if MapSet.size(@selected_ids) == length(@hosts),
                            do: "deselect_all",
                            else: "select_all"
                        }
                        class="rounded border-gray-300"
                        disabled={@syncing != nil}
                      />
                    </th>
                    <th class="pb-2 pr-4">Host</th>
                    <th class="pb-2 pr-4">Family</th>
                    <th class="pb-2 pr-4">Genus</th>
                    <th class="pb-2 pr-4 text-center">Range</th>
                    <th class="pb-2 pr-4 text-center">WCVP</th>
                    <th class="pb-2 pr-4">Last Synced</th>
                    <th class="pb-2 pr-4 text-center">Status</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={host <- @hosts} class="border-b border-gray-100 hover:bg-gray-50">
                    <td class="py-2 pr-4">
                      <input
                        type="checkbox"
                        checked={MapSet.member?(@selected_ids, host.id)}
                        phx-click="toggle_select"
                        phx-value-id={host.id}
                        class="rounded border-gray-300"
                        disabled={@syncing != nil}
                      />
                    </td>
                    <td class="py-2 pr-4">
                      <.link navigate={~p"/admin/hosts/#{host.id}"} class="hover:underline">
                        <.taxon_name name={host.name} />
                      </.link>
                    </td>
                    <td class="py-2 pr-4 text-gray-600">{host.family_name || "—"}</td>
                    <td class="py-2 pr-4 text-gray-600">{host.genus_name || "—"}</td>
                    <td class="py-2 pr-4 text-center text-gray-600">{host.range_count}</td>
                    <td class="py-2 pr-4 text-center">
                      <.badge :if={host.wcvp_id not in [nil, ""]} variant="info">linked</.badge>
                      <span :if={host.wcvp_id in [nil, ""]} class="text-gray-400">—</span>
                    </td>
                    <td class="py-2 pr-4 text-gray-600">{format_synced_at(host.wcvp_synced_at)}</td>
                    <td class="py-2 pr-4 text-center">
                      <.badge :if={host.range_confirmed} variant="success">Confirmed</.badge>
                      <.badge :if={!host.range_confirmed} variant="warning">Needs Review</.badge>
                    </td>
                  </tr>
                  <tr :if={@hosts == []}>
                    <td colspan="8" class="py-8 text-center text-gray-500">
                      {cond do
                        @search != "" -> "No hosts match your search"
                        @filter == :unconfirmed -> "All host ranges confirmed!"
                        true -> "No hosts found"
                      end}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <%= if ceil(@total_count / @page_size) > 1 do %>
              <.pagination
                page={@current_page}
                total_pages={ceil(@total_count / @page_size)}
                total_items={@total_count}
                page_size={@page_size}
                on_page_change={fn page -> JS.push("page", value: %{page: page}) end}
              />
            <% else %>
              <p class="text-sm text-gray-500 mt-2">
                Showing {@total_count} host(s)
              </p>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Confirmation modal --%>
      <.modal
        :if={@confirm_action == :confirm}
        id="confirm-modal"
        show
        on_cancel={JS.push("cancel_confirm")}
      >
        <:header>Confirm Host Ranges</:header>
        <:body>
          <p class="text-gray-600">
            Mark range as confirmed for <strong>{MapSet.size(@selected_ids)}</strong> host(s)?
          </p>
        </:body>
        <:footer>
          <.button type="button" variant="secondary" phx-click="cancel_confirm">Cancel</.button>
          <.button type="button" variant="primary" phx-click="do_confirm_selected">
            Confirm
          </.button>
        </:footer>
      </.modal>

      <.modal
        :if={@confirm_action == :sync}
        id="sync-confirm-modal"
        show
        on_cancel={JS.push("cancel_confirm")}
      >
        <:header>Sync from WCVP</:header>
        <:body>
          <p class="text-gray-600">
            Sync range data from WCVP for <strong>{MapSet.size(@selected_ids)}</strong> host(s)?
          </p>
          <p class="text-sm text-gray-500 mt-2">
            Hosts without a WCVP match will be skipped.
          </p>
        </:body>
        <:footer>
          <.button type="button" variant="secondary" phx-click="cancel_confirm">Cancel</.button>
          <.button type="button" variant="primary" phx-click="do_sync_selected">
            Sync
          </.button>
        </:footer>
      </.modal>

      <%!-- Sync results modal --%>
      <.modal
        :if={@sync_results}
        id="sync-results-modal"
        show
        on_cancel={JS.push("dismiss_sync_results")}
      >
        <:header>WCVP Sync Complete</:header>
        <:body>
          <div class="space-y-3">
            <div class="flex items-center gap-2 text-green-700">
              <.icon name="ph-check-circle" class="h-5 w-5" />
              <span><strong>{@sync_results.synced}</strong> host(s) synced</span>
            </div>
            <div :if={@sync_results.no_match != []} class="text-amber-700">
              <div class="flex items-center gap-2">
                <.icon name="ph-warning" class="h-5 w-5" />
                <span><strong>{length(@sync_results.no_match)}</strong> not matched:</span>
              </div>
              <ul class="ml-7 mt-1 text-sm list-disc">
                <li :for={name <- @sync_results.no_match}>
                  <.taxon_name name={name} />
                </li>
              </ul>
            </div>
            <div :if={@sync_results.failed != []} class="text-red-700">
              <div class="flex items-center gap-2">
                <.icon name="ph-x-circle" class="h-5 w-5" />
                <span><strong>{length(@sync_results.failed)}</strong> failed:</span>
              </div>
              <ul class="ml-7 mt-1 text-sm list-disc">
                <li :for={name <- @sync_results.failed}>
                  <.taxon_name name={name} />
                </li>
              </ul>
            </div>
          </div>
        </:body>
        <:footer>
          <.button type="button" variant="primary" phx-click="dismiss_sync_results">
            Close
          </.button>
        </:footer>
      </.modal>
    </Layouts.admin>
    """
  end
end
