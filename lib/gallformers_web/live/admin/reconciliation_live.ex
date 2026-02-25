defmodule GallformersWeb.Admin.ReconciliationLive do
  @moduledoc """
  Admin page for viewing WCVP reconciliation reports.
  """

  use GallformersWeb, :live_view

  alias Gallformers.Wcvp.Reports

  @page_size 50

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]
    runs = Reports.list_runs()

    selected_run = List.first(runs)
    summary = if selected_run, do: Reports.summary(selected_run)

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "WCVP Reconciliation")
      |> assign(:runs, runs)
      |> assign(:selected_run, selected_run)
      |> assign(:summary, summary)
      |> assign(:expanded_report, nil)
      |> assign(:report_data, [])
      |> assign(:search_query, "")
      |> assign(:current_page, 1)
      |> assign(:page_size, @page_size)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_run", %{"run" => run}, socket) do
    summary = Reports.summary(run)

    {:noreply,
     socket
     |> assign(:selected_run, run)
     |> assign(:summary, summary)
     |> assign(:expanded_report, nil)
     |> assign(:report_data, [])
     |> assign(:search_query, "")
     |> assign(:current_page, 1)}
  end

  @impl true
  def handle_event("expand_report", %{"report" => report_name}, socket) do
    if socket.assigns.expanded_report == report_name do
      {:noreply,
       socket
       |> assign(:expanded_report, nil)
       |> assign(:report_data, [])
       |> assign(:search_query, "")
       |> assign(:current_page, 1)}
    else
      {:ok, data} = Reports.load_report(socket.assigns.selected_run, report_name)
      data = sort_report_data(data, report_name)

      {:noreply,
       socket
       |> assign(:expanded_report, report_name)
       |> assign(:report_data, data)
       |> assign(:search_query, "")
       |> assign(:current_page, 1)}
    end
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:current_page, 1)}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, assign(socket, :current_page, String.to_integer(page))}
  end

  # -- Helpers --

  defp filtered_data(data, ""), do: data

  defp filtered_data(data, query) do
    q = String.downcase(query)

    Enum.filter(data, fn item ->
      item
      |> Map.values()
      |> Enum.any?(fn
        v when is_binary(v) -> v |> String.downcase() |> String.contains?(q)
        _ -> false
      end)
    end)
  end

  defp paginate(items, page, page_size) do
    items
    |> Enum.drop((page - 1) * page_size)
    |> Enum.take(page_size)
  end

  defp total_pages(total, page_size), do: max(1, ceil(total / page_size))

  defp sort_report_data(data, "taxonomy-mismatches"),
    do: Enum.sort_by(data, & &1["gf_name"])

  defp sort_report_data(data, "in-gf-not-wcvp"),
    do: Enum.sort_by(data, & &1["gf_name"])

  defp sort_report_data(data, "range-updates"),
    do: Enum.sort_by(data, & &1["gf_name"])

  defp report_label("taxonomy-mismatches"), do: "Taxonomy Mismatches"
  defp report_label("in-gf-not-wcvp"), do: "Not Found in WCVP"
  defp report_label("range-updates"), do: "Range Updates"

  defp report_description("taxonomy-mismatches"),
    do: "Species where gallformers and WCVP disagree on taxonomy"

  defp report_description("in-gf-not-wcvp"),
    do: "Gallformers species with no WCVP match (exact, fuzzy, or synonym)"

  defp report_description("range-updates"),
    do: "Matched species where WCVP has additional place data"

  defp report_count(summary, "taxonomy-mismatches"), do: summary.taxonomy_mismatches
  defp report_count(summary, "in-gf-not-wcvp"), do: summary.gf_not_in_wcvp
  defp report_count(summary, "range-updates"), do: summary.range_updates

  defp report_icon("taxonomy-mismatches"), do: "ph-arrows-left-right"
  defp report_icon("in-gf-not-wcvp"), do: "ph-magnifying-glass"
  defp report_icon("range-updates"), do: "ph-map-pin"

  defp mismatch_badge_variant("synonym"), do: "warning"
  defp mismatch_badge_variant("fuzzy_name"), do: "warning"
  defp mismatch_badge_variant(_), do: "info"

  @report_order ~w(
    taxonomy-mismatches
    in-gf-not-wcvp
    range-updates
  )

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :report_order, @report_order)

    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="WCVP Reconciliation">
      <div class="space-y-6">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h1 class="text-xl font-semibold text-gray-900">WCVP Reconciliation Reports</h1>
            <p class="text-sm text-gray-500 mt-1">
              Comparison of gallformers plant data against the World Checklist of Vascular Plants.
            </p>
          </div>
          <div :if={length(@runs) > 1}>
            <form phx-change="select_run">
              <select name="run" class="gf-input text-sm">
                <option :for={run <- @runs} value={run} selected={run == @selected_run}>
                  {run}
                </option>
              </select>
            </form>
          </div>
        </div>

        <%= if @summary do %>
          <div class="space-y-3">
            <div :for={report_name <- @report_order}>
              <% count = report_count(@summary, report_name) %>
              <% expanded = @expanded_report == report_name %>

              <button
                phx-click="expand_report"
                phx-value-report={report_name}
                class={[
                  "w-full flex items-center justify-between rounded-lg border bg-white p-4",
                  "hover:shadow-sm transition-all text-left",
                  if(expanded, do: "border-blue-300 shadow-sm", else: "border-gray-200")
                ]}
              >
                <div class="flex items-center gap-3">
                  <div class={[
                    "rounded-lg p-2",
                    if(expanded, do: "bg-blue-100", else: "bg-gray-100")
                  ]}>
                    <.icon
                      name={report_icon(report_name)}
                      class={[
                        "h-5 w-5",
                        if(expanded, do: "text-blue-600", else: "text-gray-500")
                      ]}
                    />
                  </div>
                  <div>
                    <div class="font-medium text-gray-900">{report_label(report_name)}</div>
                    <div class="text-sm text-gray-500">{report_description(report_name)}</div>
                  </div>
                </div>
                <div class="flex items-center gap-3">
                  <span class="text-lg font-semibold text-gray-800">
                    {format_number(count)}
                  </span>
                  <.icon
                    name="ph-caret-down"
                    class={[
                      "h-4 w-4 text-gray-400 transition-transform",
                      if(expanded, do: "rotate-180")
                    ]}
                  />
                </div>
              </button>

              <div
                :if={expanded}
                class="border border-t-0 border-gray-200 rounded-b-lg bg-white p-4"
              >
                <div class="mb-4 max-w-md">
                  <form phx-change="search" phx-submit="search">
                    <.search_input
                      id={"search-#{report_name}"}
                      name="query"
                      value={@search_query}
                      placeholder="Filter results..."
                      phx-debounce="300"
                    />
                  </form>
                </div>

                <% filtered = filtered_data(@report_data, @search_query) %>
                <% page_items = paginate(filtered, @current_page, @page_size) %>
                <% total = length(filtered) %>
                <% pages = total_pages(total, @page_size) %>

                {render_report_table(assigns, report_name, page_items)}

                <div class="mt-4 flex items-center justify-between text-sm text-gray-500">
                  <span>
                    Showing {min((@current_page - 1) * @page_size + 1, total)}-{min(
                      @current_page * @page_size,
                      total
                    )} of {format_number(total)}
                  </span>
                  <div :if={pages > 1} class="flex gap-1">
                    <button
                      :if={@current_page > 1}
                      phx-click="page"
                      phx-value-page={@current_page - 1}
                      class="px-2 py-1 rounded border border-gray-300 hover:bg-gray-50"
                    >
                      Prev
                    </button>
                    <button
                      :if={@current_page < pages}
                      phx-click="page"
                      phx-value-page={@current_page + 1}
                      class="px-2 py-1 rounded border border-gray-300 hover:bg-gray-50"
                    >
                      Next
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% else %>
          <div class="text-center py-12 text-gray-500">
            <.icon name="ph-file-text" class="h-12 w-12 mx-auto mb-4 text-gray-300" />
            <p class="text-lg font-medium">No reconciliation reports found</p>
            <p class="text-sm mt-1">
              Run <code class="bg-gray-100 px-1 rounded">mix gallformers.wcvp.reconcile</code>
              to generate reports.
            </p>
          </div>
        <% end %>
      </div>
    </Layouts.admin>
    """
  end

  defp render_report_table(assigns, "taxonomy-mismatches", items) do
    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="overflow-x-auto">
      <table class="gf-table gf-table-dark gf-table-compact">
        <thead>
          <tr>
            <th>GF Name</th>
            <th>Type</th>
            <th>WCVP Accepted Name</th>
            <th>Detail</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={item <- @items}>
            <td>
              <.link
                navigate={~p"/admin/hosts/#{item["gf_species_id"]}"}
                class="text-gf-maroon hover:underline"
              >
                <em>{item["gf_name"]}</em>
              </.link>
            </td>
            <td>
              <.badge variant={mismatch_badge_variant(item["mismatch_type"])}>
                {item["mismatch_type"]}
              </.badge>
            </td>
            <td><em>{item["wcvp_accepted_name"]}</em></td>
            <td class="text-sm text-gray-600">{item["detail"]}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp render_report_table(assigns, "in-gf-not-wcvp", items) do
    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="overflow-x-auto">
      <table class="gf-table gf-table-dark gf-table-compact">
        <thead>
          <tr>
            <th>GF Name</th>
            <th>Family</th>
            <th>Genus</th>
            <th>Closest WCVP Match</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={item <- @items}>
            <td>
              <.link
                navigate={~p"/admin/hosts/#{item["gf_species_id"]}"}
                class="text-gf-maroon hover:underline"
              >
                <em>{item["gf_name"]}</em>
              </.link>
            </td>
            <td>{item["gf_family"]}</td>
            <td><em>{item["gf_genus"]}</em></td>
            <td>
              <em :if={item["closest_wcvp_match"]}>{item["closest_wcvp_match"]}</em>
              <span :if={!item["closest_wcvp_match"]} class="text-gray-400">&mdash;</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp render_report_table(assigns, "range-updates", items) do
    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="overflow-x-auto">
      <table class="gf-table gf-table-dark gf-table-compact">
        <thead>
          <tr>
            <th>GF Name</th>
            <th>Current Places</th>
            <th>New Places</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={item <- @items}>
            <td>
              <.link
                navigate={~p"/admin/hosts/#{item["gf_species_id"]}"}
                class="text-gf-maroon hover:underline"
              >
                <em>{item["gf_name"]}</em>
              </.link>
            </td>
            <td class="text-sm">{length(item["current_places"])} places</td>
            <td>
              <span class="text-green-700 font-medium">+{length(item["new_places"])}</span>
              <span class="text-xs text-gray-500 ml-1">
                {item["new_places"] |> Enum.take(5) |> Enum.join(", ")}{if length(item["new_places"]) >
                                                                             5,
                                                                           do: "..."}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
