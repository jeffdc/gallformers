defmodule GallformersWeb.Admin.HostRangeLive do
  @moduledoc """
  Admin triage page for host range confirmation and WCVP sync (matter
  a856, decision 4: carried over from the old Host admin onto plant taxa).

  Shows plants (`Gallformers.Ranges.Wcvp.list_for_range_review/1`) that
  need range review and allows bulk confirmation plus bulk WCVP
  match/sync/ignore, each through `Gallformers.Import.record_wcvp_edit/2`
  as the signed-in admin, so it is audited and in the replay log. Matching
  all filtered plants is for superadmins only, as before.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Accounts
  alias Gallformers.Import
  alias Gallformers.Ranges.Wcvp

  @page_size 50

  defp wcvp_lookup, do: Application.get_env(:gallformers, :wcvp_lookup, Gallformers.Wcvp.Lookup)

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:superadmin?, Accounts.superadmin?(socket.assigns.current_user))
      |> assign(:page_title, "Host Range Review")
      |> assign(:selected_ids, MapSet.new())
      |> assign(:processing, nil)
      |> assign(:confirm_action, nil)
      |> assign(:sync_results, nil)
      |> assign(:match_results, nil)
      |> assign(:page_size, @page_size)
      |> assign(:total_count, 0)
      |> assign(:hosts, [])
      |> assign(:wcvp_built_at, wcvp_lookup().built_at())

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
      |> assign(
        :wcvp_filter,
        parse_atom_param(
          params["wcvp"],
          ~w(active all linked unmatched no_match ignored),
          :active
        )
      )
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
  def handle_event("match_selected", _params, socket) do
    {:noreply, assign(socket, :confirm_action, :match)}
  end

  @impl true
  def handle_event("match_all_filtered", _params, socket) do
    if socket.assigns.superadmin? do
      {:noreply, assign(socket, :confirm_action, :match_filtered)}
    else
      {:noreply, put_flash(socket, :error, "Only superadmins can match all filtered hosts")}
    end
  end

  @impl true
  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, assign(socket, :confirm_action, nil)}
  end

  # Execute confirmed actions
  @impl true
  def handle_event("do_confirm_selected", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)

    socket =
      case Import.record_wcvp_edit(socket.assigns.actor, {:confirm_ranges, ids}) do
        {:ok, count} -> put_flash(socket, :info, "Confirmed range for #{count} host(s)")
        {:error, _reason} -> put_flash(socket, :error, "Could not confirm the ranges")
      end

    {:noreply,
     socket
     |> assign(:confirm_action, nil)
     |> assign(:selected_ids, MapSet.new())
     |> load_hosts()}
  end

  @impl true
  def handle_event("do_sync_selected", _params, socket) do
    hosts = socket.assigns.hosts
    selected_ids = socket.assigns.selected_ids

    hosts_to_sync =
      Enum.filter(hosts, fn host ->
        MapSet.member?(selected_ids, host.id)
      end)

    ref_data = Wcvp.load_sync_ref_data()

    summary = %{synced: 0, no_match: [], failed: []}
    send(self(), {:sync_next, hosts_to_sync, summary, ref_data})

    {:noreply,
     socket
     |> assign(:confirm_action, nil)
     |> assign(:processing, %{kind: :sync, total: length(hosts_to_sync), done: 0})}
  end

  @impl true
  def handle_event("do_match_selected", _params, socket) do
    {:noreply, begin_match(socket, selected_hosts(socket))}
  end

  @impl true
  def handle_event("do_match_all_filtered", _params, socket) do
    if socket.assigns.superadmin? do
      {:noreply, begin_match(socket, filtered_hosts(socket))}
    else
      {:noreply, put_flash(socket, :error, "Only superadmins can match all filtered hosts")}
    end
  end

  @impl true
  def handle_event("ignore_selected", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)
    {:noreply, bulk(socket, {:ignore, ids}, "Ignored %{count} host(s) for default WCVP flows")}
  end

  @impl true
  def handle_event("unignore_selected", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)

    {:noreply,
     bulk(socket, {:clear_match_status, ids}, "Cleared WCVP match status for %{count} host(s)")}
  end

  # Dismiss sync results modal
  @impl true
  def handle_event("dismiss_sync_results", _params, socket) do
    {:noreply, assign(socket, :sync_results, nil)}
  end

  @impl true
  def handle_event("dismiss_match_results", _params, socket) do
    {:noreply, assign(socket, :match_results, nil)}
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
      |> assign(:processing, nil)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:sync_results, results)
      |> load_hosts()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:sync_next, [host | rest], summary, ref_data}, socket) do
    updated_summary =
      case Import.record_wcvp_edit(socket.assigns.actor, {:sync, host.id, ref_data}) do
        {:ok, _} ->
          %{summary | synced: summary.synced + 1}

        {:error, "No WCVP match found" <> _} ->
          %{summary | no_match: [host.name | summary.no_match]}

        {:error, _reason} ->
          %{summary | failed: [host.name | summary.failed]}
      end

    send(self(), {:sync_next, rest, updated_summary, ref_data})

    {:noreply,
     assign(socket, :processing, %{
       socket.assigns.processing
       | done: socket.assigns.processing.done + 1
     })}
  end

  @impl true
  def handle_info({:match_next, [], summary}, socket) do
    results = %{
      linked: summary.linked,
      already_linked: summary.already_linked,
      no_match: Enum.reverse(summary.no_match),
      failed: Enum.reverse(summary.failed)
    }

    socket =
      socket
      |> assign(:processing, nil)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:match_results, results)
      |> load_hosts()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:match_next, [host | rest], summary}, socket) do
    updated_summary =
      case Import.record_wcvp_edit(socket.assigns.actor, {:match, host.id}) do
        {:ok, :linked} ->
          %{summary | linked: summary.linked + 1}

        {:ok, :already_linked} ->
          %{summary | already_linked: summary.already_linked + 1}

        {:error, "No WCVP match found" <> _} ->
          %{summary | no_match: [host.name | summary.no_match]}

        {:error, _reason} ->
          %{summary | failed: [host.name | summary.failed]}
      end

    send(self(), {:match_next, rest, updated_summary})

    {:noreply,
     assign(socket, :processing, %{
       socket.assigns.processing
       | done: socket.assigns.processing.done + 1
     })}
  end

  # ============================================
  # Helpers
  # ============================================

  defp load_hosts(socket) do
    %{current_page: page, page_size: page_size} = socket.assigns

    filter_opts = range_review_filter_opts(socket)

    opts =
      filter_opts ++
        [
          limit: page_size,
          offset: (page - 1) * page_size
        ]

    hosts = Wcvp.list_for_range_review(opts)
    total_count = Wcvp.count_for_range_review(filter_opts)

    socket
    |> assign(:hosts, hosts)
    |> assign(:total_count, total_count)
  end

  defp range_review_filter_opts(socket) do
    [
      filter: socket.assigns.filter,
      wcvp_match: socket.assigns.wcvp_filter,
      has_range: socket.assigns.range_filter,
      sync_status: socket.assigns.sync_status,
      search: socket.assigns.search,
      wcvp_built_at: socket.assigns.wcvp_built_at
    ]
  end

  defp selected_hosts(socket) do
    selected_ids = socket.assigns.selected_ids
    Enum.filter(socket.assigns.hosts, &MapSet.member?(selected_ids, &1.id))
  end

  defp filtered_hosts(socket) do
    socket
    |> range_review_filter_opts()
    |> Wcvp.list_refs_for_range_review()
  end

  # A bulk WCVP action on the selected plants; `message` takes the count.
  defp bulk(socket, edit, message) do
    socket =
      case Import.record_wcvp_edit(socket.assigns.actor, edit) do
        {:ok, count} -> put_flash(socket, :info, String.replace(message, "%{count}", "#{count}"))
        {:error, _reason} -> put_flash(socket, :error, "The WCVP action failed")
      end

    socket
    |> assign(:selected_ids, MapSet.new())
    |> load_hosts()
  end

  defp begin_match(socket, hosts) do
    summary = %{linked: 0, already_linked: 0, no_match: [], failed: []}
    send(self(), {:match_next, hosts, summary})

    socket
    |> assign(:confirm_action, nil)
    |> assign(:processing, %{kind: :match, total: length(hosts), done: 0})
  end

  defp format_synced_at(nil), do: "Never"
  defp format_synced_at(datetime), do: format_date(datetime, :short)
  defp processing_label(%{kind: :sync}), do: "Syncing from WCVP"
  defp processing_label(%{kind: :match}), do: "Matching against WCVP"

  defp wcvp_badges(host) do
    cond do
      host.wcvp_id not in [nil, ""] and host.wcvp_match_status == "ignored" ->
        [{"linked", "info"}, {"ignored", "warning"}]

      host.wcvp_id not in [nil, ""] ->
        [{"linked", "info"}]

      host.wcvp_match_status == "no_match" ->
        [{"no match", "warning"}]

      host.wcvp_match_status == "ignored" ->
        [{"ignored", "warning"}]

      true ->
        []
    end
  end

  @filter_defaults %{
    filter: "unconfirmed",
    wcvp: "active",
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
        <div class="mb-4 p-3 bg-gray-50 border border-gray-200 rounded flex items-center gap-4">
          <span class="text-sm font-medium text-gray-700">Quick Links:</span>
          <.link navigate={~p"/admin"} class="text-sm hover:underline">← Back to Admin</.link>
          <.link navigate={~p"/admin/taxonomy"} class="text-sm hover:underline">Taxonomy</.link>
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
                <label class="text-sm font-medium text-gray-700">Match:</label>
                <form phx-change="wcvp_filter" id="wcvp_filter" class="w-36">
                  <.input
                    type="select"
                    name="value"
                    options={[
                      {"Default", "active"},
                      {"Linked", "linked"},
                      {"Unmatched", "unmatched"},
                      {"No match", "no_match"},
                      {"Ignored", "ignored"},
                      {"All", "all"}
                    ]}
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

            <div
              :if={@superadmin? and is_nil(@processing)}
              class="mb-4 flex items-center gap-3"
            >
              <button
                type="button"
                phx-click="match_all_filtered"
                class="gf-btn gf-btn-secondary text-sm"
              >
                <.icon name="ph-link" class="h-4 w-4 inline" /> Match All Filtered to WCVP
              </button>
              <span class="text-xs text-gray-500">
                Super Admin only. Uses the current filters across all pages.
              </span>
            </div>

            <%!-- Sync progress bar --%>
            <div :if={@processing} class="mb-4 p-3 bg-blue-50 border border-blue-200 rounded">
              <div class="flex items-center gap-2 text-sm text-blue-800">
                <.icon name="ph-arrows-clockwise" class="h-4 w-4 animate-spin" />
                {processing_label(@processing)}: {@processing.done} / {@processing.total}
              </div>
              <div class="mt-2 w-full bg-blue-200 rounded-full h-2">
                <div
                  class="bg-blue-600 h-2 rounded-full transition-all"
                  style={"width: #{if @processing.total > 0, do: @processing.done / @processing.total * 100, else: 0}%"}
                >
                </div>
              </div>
            </div>

            <%!-- Bulk actions --%>
            <div
              :if={MapSet.size(@selected_ids) > 0 and is_nil(@processing)}
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
                phx-click="match_selected"
                class="gf-btn gf-btn-secondary text-sm"
              >
                <.icon name="ph-link" class="h-4 w-4 inline" /> Match Selected to WCVP
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
                phx-click="ignore_selected"
                class="text-sm text-gray-600 hover:underline"
              >
                Ignore Selected
              </button>
              <button
                type="button"
                phx-click="unignore_selected"
                class="text-sm text-gray-600 hover:underline"
              >
                Clear Match Status
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
                        disabled={@processing != nil}
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
                        disabled={@processing != nil}
                      />
                    </td>
                    <td class="py-2 pr-4">
                      <.link navigate={~p"/admin/taxonomy/#{host.id}"} class="hover:underline">
                        <.taxon_name name={host.name} />
                      </.link>
                    </td>
                    <td class="py-2 pr-4 text-gray-600">{host.family_name || "—"}</td>
                    <td class="py-2 pr-4 text-gray-600">{host.genus_name || "—"}</td>
                    <td class="py-2 pr-4 text-center text-gray-600">{host.range_count}</td>
                    <td class="py-2 pr-4 text-center">
                      <div class="flex items-center justify-center gap-1">
                        <.badge :for={{label, variant} <- wcvp_badges(host)} variant={variant}>
                          {label}
                        </.badge>
                        <span :if={wcvp_badges(host) == []} class="text-gray-400">—</span>
                      </div>
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
                        @wcvp_filter == :ignored -> "No ignored hosts found"
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

      <.modal
        :if={@confirm_action in [:match, :match_filtered]}
        id="match-confirm-modal"
        show
        on_cancel={JS.push("cancel_confirm")}
      >
        <:header>Match to WCVP</:header>
        <:body>
          <p class="text-gray-600">
            Match {if @confirm_action == :match_filtered,
              do: "all currently filtered",
              else: "selected"} host(s) to WCVP for
            <strong>
              {if @confirm_action == :match_filtered,
                do: @total_count,
                else: MapSet.size(@selected_ids)}
            </strong>
            host(s)?
          </p>
          <p class="text-sm text-gray-500 mt-2">
            This only stores WCVP and POWO IDs. It does not sync range data.
          </p>
          <p :if={@confirm_action == :match_filtered} class="text-sm text-gray-500 mt-2">
            The current filters apply across all pages, not just the visible rows.
          </p>
        </:body>
        <:footer>
          <.button type="button" variant="secondary" phx-click="cancel_confirm">Cancel</.button>
          <.button
            type="button"
            variant="primary"
            phx-click={
              if @confirm_action == :match_filtered,
                do: "do_match_all_filtered",
                else: "do_match_selected"
            }
          >
            Match
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

      <.modal
        :if={@match_results}
        id="match-results-modal"
        show
        on_cancel={JS.push("dismiss_match_results")}
      >
        <:header>WCVP Match Complete</:header>
        <:body>
          <div class="space-y-3">
            <div :if={@match_results.linked > 0} class="flex items-center gap-2 text-green-700">
              <.icon name="ph-check-circle" class="h-5 w-5" />
              <span><strong>{@match_results.linked}</strong> host(s) linked</span>
            </div>
            <div :if={@match_results.already_linked > 0} class="flex items-center gap-2 text-blue-700">
              <.icon name="ph-info" class="h-5 w-5" />
              <span><strong>{@match_results.already_linked}</strong> already linked</span>
            </div>
            <div :if={@match_results.no_match != []} class="text-amber-700">
              <div class="flex items-center gap-2">
                <.icon name="ph-warning" class="h-5 w-5" />
                <span><strong>{length(@match_results.no_match)}</strong> not matched:</span>
              </div>
              <ul class="ml-7 mt-1 text-sm list-disc">
                <li :for={name <- @match_results.no_match}>
                  <.taxon_name name={name} />
                </li>
              </ul>
            </div>
            <div :if={@match_results.failed != []} class="text-red-700">
              <div class="flex items-center gap-2">
                <.icon name="ph-x-circle" class="h-5 w-5" />
                <span><strong>{length(@match_results.failed)}</strong> failed:</span>
              </div>
              <ul class="ml-7 mt-1 text-sm list-disc">
                <li :for={name <- @match_results.failed}>
                  <.taxon_name name={name} />
                </li>
              </ul>
            </div>
          </div>
        </:body>
        <:footer>
          <.button type="button" variant="primary" phx-click="dismiss_match_results">
            Close
          </.button>
        </:footer>
      </.modal>
    </Layouts.admin>
    """
  end
end
