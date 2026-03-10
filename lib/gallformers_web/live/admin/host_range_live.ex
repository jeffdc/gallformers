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
    current_user = session["current_user"]

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Host Range Review")
      |> assign(:filter, :unconfirmed)
      |> assign(:wcvp_filter, :all)
      |> assign(:range_filter, :all)
      |> assign(:search, "")
      |> assign(:selected_ids, MapSet.new())
      |> assign(:syncing, nil)
      |> assign(:current_page, 1)
      |> assign(:page_size, @page_size)
      |> assign(:total_count, 0)
      |> assign(:wcvp_built_at, Wcvp.Lookup.built_at())
      |> load_hosts()

    {:ok, socket}
  end

  # ============================================
  # Filter events
  # ============================================

  @impl true
  def handle_event("filter", %{"value" => value}, socket) do
    filter =
      case value do
        "all" -> :all
        "confirmed" -> :confirmed
        _ -> :unconfirmed
      end

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> assign(:current_page, 1)
     |> assign(:selected_ids, MapSet.new())
     |> load_hosts()}
  end

  @impl true
  def handle_event("wcvp_filter", %{"value" => value}, socket) do
    wcvp_filter =
      case value do
        "yes" -> :yes
        "no" -> :no
        _ -> :all
      end

    {:noreply,
     socket
     |> assign(:wcvp_filter, wcvp_filter)
     |> assign(:current_page, 1)
     |> assign(:selected_ids, MapSet.new())
     |> load_hosts()}
  end

  @impl true
  def handle_event("range_filter", %{"value" => value}, socket) do
    range_filter =
      case value do
        "yes" -> :yes
        "no" -> :no
        _ -> :all
      end

    {:noreply,
     socket
     |> assign(:range_filter, range_filter)
     |> assign(:current_page, 1)
     |> assign(:selected_ids, MapSet.new())
     |> load_hosts()}
  end

  @impl true
  def handle_event("search", %{"value" => value}, socket) do
    {:noreply,
     socket
     |> assign(:search, value)
     |> assign(:current_page, 1)
     |> assign(:selected_ids, MapSet.new())
     |> load_hosts()}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    page = max(1, min(page, total_pages(socket)))

    {:noreply,
     socket
     |> assign(:current_page, page)
     |> assign(:selected_ids, MapSet.new())
     |> load_hosts()}
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

  @impl true
  def handle_event("confirm_selected", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)

    if ids != [] do
      {count, _} = Plants.bulk_confirm_host_ranges(ids)

      socket =
        socket
        |> assign(:selected_ids, MapSet.new())
        |> load_hosts()
        |> put_flash(:info, "Confirmed range for #{count} host(s)")

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "No hosts selected")}
    end
  end

  @impl true
  def handle_event("sync_selected", _params, socket) do
    hosts = socket.assigns.hosts
    selected_ids = socket.assigns.selected_ids

    hosts_to_sync =
      Enum.filter(hosts, fn host ->
        MapSet.member?(selected_ids, host.id)
      end)

    if hosts_to_sync == [] do
      {:noreply, put_flash(socket, :error, "No hosts selected")}
    else
      ref_data = Plants.load_sync_ref_data()
      send(self(), {:sync_next, hosts_to_sync, %{synced: 0, no_match: 0, failed: 0}, ref_data})

      {:noreply, assign(socket, :syncing, %{total: length(hosts_to_sync), done: 0})}
    end
  end

  # ============================================
  # Sync progress (handle_info)
  # ============================================

  @impl true
  def handle_info({:sync_next, [], summary, _ref_data}, socket) do
    socket =
      socket
      |> assign(:syncing, nil)
      |> assign(:selected_ids, MapSet.new())
      |> load_hosts()
      |> put_flash(
        :info,
        "WCVP sync complete: #{summary.synced} synced, #{summary.no_match} not matched, #{summary.failed} failed"
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:sync_next, [host | rest], summary, ref_data}, socket) do
    updated_summary =
      case Plants.sync_host_from_wcvp(host.id, ref_data) do
        {:ok, _} ->
          %{summary | synced: summary.synced + 1}

        {:error, "No WCVP match found" <> _} ->
          %{summary | no_match: summary.no_match + 1}

        {:error, _} ->
          %{summary | failed: summary.failed + 1}
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

  defp total_pages(socket) do
    max(1, ceil(socket.assigns.total_count / socket.assigns.page_size))
  end

  defp format_synced_at(nil), do: "Never"
  defp format_synced_at(datetime), do: format_date(datetime, :short)

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
                <select
                  phx-change="filter"
                  name="value"
                  class="text-sm border-gray-300 rounded"
                >
                  <option value="unconfirmed" selected={@filter == :unconfirmed}>Unconfirmed</option>
                  <option value="confirmed" selected={@filter == :confirmed}>Confirmed</option>
                  <option value="all" selected={@filter == :all}>All</option>
                </select>
              </div>

              <div class="flex items-center gap-2">
                <label class="text-sm font-medium text-gray-700">WCVP:</label>
                <select
                  phx-change="wcvp_filter"
                  name="value"
                  class="text-sm border-gray-300 rounded"
                >
                  <option value="all" selected={@wcvp_filter == :all}>All</option>
                  <option value="yes" selected={@wcvp_filter == :yes}>Has match</option>
                  <option value="no" selected={@wcvp_filter == :no}>No match</option>
                </select>
              </div>

              <div class="flex items-center gap-2">
                <label class="text-sm font-medium text-gray-700">Range:</label>
                <select
                  phx-change="range_filter"
                  name="value"
                  class="text-sm border-gray-300 rounded"
                >
                  <option value="all" selected={@range_filter == :all}>All</option>
                  <option value="yes" selected={@range_filter == :yes}>Has range</option>
                  <option value="no" selected={@range_filter == :no}>No range</option>
                </select>
              </div>

              <div class="flex items-center gap-2">
                <.icon name="ph-magnifying-glass" class="h-4 w-4 text-gray-400" />
                <input
                  type="text"
                  name="value"
                  value={@search}
                  phx-keyup="search"
                  phx-debounce="300"
                  placeholder="Search by name..."
                  class="text-sm border-gray-300 rounded w-48"
                />
              </div>
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
    </Layouts.admin>
    """
  end
end
