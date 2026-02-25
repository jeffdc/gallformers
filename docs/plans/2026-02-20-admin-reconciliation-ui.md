# Admin Reconciliation UI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Surface WCVP reconciliation reports in the admin UI with a dashboard summary card and a dedicated detail page.

**Architecture:** A new `Gallformers.Wcvp.Reports` context module reads JSON report files from disk. A dashboard card shows the latest run summary. A dedicated `/admin/reconciliation` LiveView renders report tables with search and pagination for large reports.

**Tech Stack:** Phoenix LiveView, existing `.card`/`.table`/`.pagination`/`.search_input` components, JSON file reads via `Jason`.

---

### Task 1: Create the Reports Context Module

**Files:**
- Create: `lib/gallformers/wcvp/reports.ex`
- Test: `test/gallformers/wcvp/reports_test.exs`

This module reads reconciliation report directories and JSON files. It provides summary counts without loading full reports, and full report loading for the detail page.

**Step 1: Write the test file**

```elixir
# test/gallformers/wcvp/reports_test.exs
defmodule Gallformers.Wcvp.ReportsTest do
  use ExUnit.Case, async: true

  alias Gallformers.Wcvp.Reports

  @fixture_dir "test/support/fixtures/reconciliation"

  setup do
    # Create a fixture reconciliation directory with small sample reports
    run_dir = Path.join(@fixture_dir, "2026-01-15")
    File.mkdir_p!(run_dir)

    File.write!(
      Path.join(run_dir, "taxonomy-mismatches.json"),
      Jason.encode!([
        %{
          gf_species_id: 1,
          gf_name: "Quercus alba",
          mismatch_type: "family",
          detail: "Family differs",
          gf_family: "Fagaceae",
          gf_genus: "Quercus",
          wcvp_accepted_name: "Quercus alba",
          wcvp_family: "Fagaceae2",
          wcvp_genus: "Quercus"
        }
      ])
    )

    File.write!(
      Path.join(run_dir, "in-gf-not-wcvp.json"),
      Jason.encode!([
        %{gf_species_id: 2, gf_name: "Xanthium sp", gf_family: "Asteraceae", gf_genus: "Xanthium"}
      ])
    )

    File.write!(
      Path.join(run_dir, "range-updates.json"),
      Jason.encode!([
        %{gf_species_id: 3, gf_name: "Zizia aurea", current_places: ["AL"], new_places: ["US-DC"]}
      ])
    )

    File.write!(
      Path.join(run_dir, "in-wcvp-not-gf-usca.json"),
      Jason.encode!([
        %{wcvp_id: "100", wcvp_name: "Rosa carolina", wcvp_family: "Rosaceae"}
      ])
    )

    File.write!(
      Path.join(run_dir, "in-wcvp-not-gf-hemisphere.json"),
      Jason.encode!([
        %{wcvp_id: "200", wcvp_name: "Tmesipteris oblongifolia", wcvp_family: "Psilotaceae"}
      ])
    )

    on_exit(fn -> File.rm_rf!(@fixture_dir) end)

    %{run_dir: run_dir}
  end

  describe "list_runs/1" do
    test "returns available run dates in reverse chronological order" do
      runs = Reports.list_runs(@fixture_dir)
      assert runs == ["2026-01-15"]
    end

    test "returns empty list when no runs exist" do
      assert Reports.list_runs("nonexistent/path") == []
    end
  end

  describe "summary/2" do
    test "returns counts for all report types" do
      summary = Reports.summary("2026-01-15", @fixture_dir)

      assert summary.run_date == "2026-01-15"
      assert summary.taxonomy_mismatches == 1
      assert summary.gf_not_in_wcvp == 1
      assert summary.range_updates == 1
      assert summary.wcvp_not_in_gf_usca == 1
      assert summary.wcvp_not_in_gf_hemisphere == 1
    end

    test "returns nil for nonexistent run" do
      assert Reports.summary("1999-01-01", @fixture_dir) == nil
    end
  end

  describe "load_report/3" do
    test "loads and returns parsed report data" do
      {:ok, items} = Reports.load_report("2026-01-15", "taxonomy-mismatches", @fixture_dir)
      assert length(items) == 1
      assert hd(items)["gf_name"] == "Quercus alba"
    end

    test "returns error for missing report" do
      assert {:error, :not_found} = Reports.load_report("2026-01-15", "nonexistent", @fixture_dir)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/gallformers/wcvp/reports_test.exs`
Expected: Compilation error — `Gallformers.Wcvp.Reports` not found.

**Step 3: Write the implementation**

```elixir
# lib/gallformers/wcvp/reports.ex
defmodule Gallformers.Wcvp.Reports do
  @moduledoc """
  Reads WCVP reconciliation report files from disk.

  Reports are stored as JSON files in date-stamped directories under
  `priv/repo/data/reconciliation/YYYY-MM-DD/`. This module provides
  functions to list available runs, get summary counts, and load
  individual report files.
  """

  @default_base_dir "priv/repo/data/reconciliation"

  @report_names ~w(
    taxonomy-mismatches
    in-gf-not-wcvp
    in-wcvp-not-gf-usca
    in-wcvp-not-gf-hemisphere
    range-updates
  )

  @doc """
  Returns available report run dates, most recent first.
  """
  def list_runs(base_dir \\ @default_base_dir) do
    case File.ls(base_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&date_dir?/1)
        |> Enum.sort(:desc)

      {:error, _} ->
        []
    end
  end

  @doc """
  Returns a summary map with counts for each report type in a given run.
  Returns nil if the run directory doesn't exist.
  """
  def summary(run_date, base_dir \\ @default_base_dir) do
    dir = Path.join(base_dir, run_date)

    if File.dir?(dir) do
      %{
        run_date: run_date,
        taxonomy_mismatches: count_items(dir, "taxonomy-mismatches"),
        gf_not_in_wcvp: count_items(dir, "in-gf-not-wcvp"),
        range_updates: count_items(dir, "range-updates"),
        wcvp_not_in_gf_usca: count_items(dir, "in-wcvp-not-gf-usca"),
        wcvp_not_in_gf_hemisphere: count_items(dir, "in-wcvp-not-gf-hemisphere")
      }
    end
  end

  @doc """
  Loads and parses a specific report file. Returns {:ok, items} or {:error, reason}.
  """
  def load_report(run_date, report_name, base_dir \\ @default_base_dir)
      when report_name in @report_names do
    path = Path.join([base_dir, run_date, "#{report_name}.json"])

    case File.read(path) do
      {:ok, content} -> {:ok, Jason.decode!(content)}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def load_report(_run_date, _report_name, _base_dir), do: {:error, :invalid_report}

  # -- Private --

  defp date_dir?(name), do: Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, name)

  defp count_items(dir, report_name) do
    path = Path.join(dir, "#{report_name}.json")

    case File.read(path) do
      {:ok, content} -> content |> Jason.decode!() |> length()
      {:error, _} -> 0
    end
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/gallformers/wcvp/reports_test.exs`
Expected: All 5 tests pass.

**Step 5: Commit**

```bash
git add lib/gallformers/wcvp/reports.ex test/gallformers/wcvp/reports_test.exs
git commit -m "Add WCVP Reports context for reading reconciliation data from disk"
```

---

### Task 2: Add Dashboard Card

**Files:**
- Modify: `lib/gallformers_web/live/admin/dashboard_live.ex`

Add a "WCVP Reconciliation" section to the admin dashboard below the stats cards. Shows the last run date, summary counts, and a link to the detail page.

**Step 1: Add the Reports alias and load summary in `assign_stats`**

In `dashboard_live.ex`, add `alias Gallformers.Wcvp.Reports` to the alias block (line 8).

Update `assign_stats/1` to also load the latest reconciliation summary:

```elixir
defp assign_stats(socket) do
  stats = %{
    gall_count: Galls.count_galls(),
    host_count: Plants.count_hosts(),
    source_count: Sources.count_sources(),
    image_count: Images.count_images()
  }

  reconciliation =
    case Reports.list_runs() do
      [latest | _] -> Reports.summary(latest)
      [] -> nil
    end

  socket
  |> assign(:stats, stats)
  |> assign(:reconciliation, reconciliation)
end
```

**Step 2: Add the reconciliation card to the template**

Insert after the stats grid (after line 186, before `</Layouts.admin>`):

```heex
<%!-- WCVP Reconciliation --%>
<%= if @reconciliation do %>
  <div class="mt-8">
    <h2 class="text-sm font-medium text-gray-500 mb-3">WCVP Reconciliation</h2>
    <a
      href="/admin/reconciliation"
      class="block rounded-lg border border-gray-200 bg-white p-4 hover:shadow-md hover:-translate-y-0.5 transition-all group"
    >
      <div class="flex items-center justify-between mb-3">
        <div class="flex items-center gap-2">
          <div class="rounded-lg bg-blue-50 p-2">
            <.icon name="ph-arrows-clockwise" class="h-5 w-5 text-blue-600" />
          </div>
          <span class="font-medium text-gray-900 group-hover:text-gf-maroon">
            Latest Run: {@reconciliation.run_date}
          </span>
        </div>
        <.icon name="ph-arrow-right" class="h-4 w-4 text-gray-400 group-hover:text-gf-maroon" />
      </div>
      <div class="grid grid-cols-2 sm:grid-cols-5 gap-3 text-sm">
        <div>
          <div class="text-gray-500">Mismatches</div>
          <div class="font-semibold text-gray-800">
            {format_number(@reconciliation.taxonomy_mismatches)}
          </div>
        </div>
        <div>
          <div class="text-gray-500">Not in WCVP</div>
          <div class="font-semibold text-gray-800">
            {format_number(@reconciliation.gf_not_in_wcvp)}
          </div>
        </div>
        <div>
          <div class="text-gray-500">Range Updates</div>
          <div class="font-semibold text-gray-800">
            {format_number(@reconciliation.range_updates)}
          </div>
        </div>
        <div>
          <div class="text-gray-500">US/CA Gaps</div>
          <div class="font-semibold text-gray-800">
            {format_number(@reconciliation.wcvp_not_in_gf_usca)}
          </div>
        </div>
        <div>
          <div class="text-gray-500">Hemisphere Gaps</div>
          <div class="font-semibold text-gray-800">
            {format_number(@reconciliation.wcvp_not_in_gf_hemisphere)}
          </div>
        </div>
      </div>
    </a>
  </div>
<% end %>
```

**Step 3: Verify it compiles and renders**

Run: `mix compile --warnings-as-errors`
Expected: Clean compile.

Run: `mix test test/gallformers_web/live/admin/dashboard_live_test.exs` (if it exists, otherwise skip)

**Step 4: Commit**

```bash
git add lib/gallformers_web/live/admin/dashboard_live.ex
git commit -m "Add WCVP reconciliation summary card to admin dashboard"
```

---

### Task 3: Create the Reconciliation LiveView

**Files:**
- Create: `lib/gallformers_web/live/admin/reconciliation_live.ex`
- Modify: `lib/gallformers_web/router.ex` (line ~124, add route in admin scope)

This is a single-page LiveView that shows all 5 reports with expandable sections. The large reports (US/CA, hemisphere) get pagination. All reports get search.

**Step 1: Add the route**

In `router.ex`, inside the admin scope (after line 124, before the `end` on line 125), add:

```elixir
# Reconciliation reports
live "/reconciliation", Admin.ReconciliationLive
```

**Step 2: Create the LiveView**

```elixir
# lib/gallformers_web/live/admin/reconciliation_live.ex
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
      # Collapse if already expanded
      {:noreply,
       socket
       |> assign(:expanded_report, nil)
       |> assign(:report_data, [])
       |> assign(:search_query, "")
       |> assign(:current_page, 1)}
    else
      {:ok, data} = Reports.load_report(socket.assigns.selected_run, report_name)

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
        v when is_binary(v) -> String.downcase(v) |> String.contains?(q)
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

  defp report_label("taxonomy-mismatches"), do: "Taxonomy Mismatches"
  defp report_label("in-gf-not-wcvp"), do: "Not Found in WCVP"
  defp report_label("range-updates"), do: "Range Updates"
  defp report_label("in-wcvp-not-gf-usca"), do: "US/CA Species Not in Gallformers"
  defp report_label("in-wcvp-not-gf-hemisphere"), do: "Hemisphere Species Not in Gallformers"

  defp report_description("taxonomy-mismatches"),
    do: "Species where gallformers and WCVP disagree on taxonomy"

  defp report_description("in-gf-not-wcvp"),
    do: "Gallformers species with no WCVP match (exact, fuzzy, or synonym)"

  defp report_description("range-updates"),
    do: "Matched species where WCVP has additional place data"

  defp report_description("in-wcvp-not-gf-usca"),
    do: "Accepted WCVP species in US/Canada not yet in gallformers"

  defp report_description("in-wcvp-not-gf-hemisphere"),
    do: "Accepted WCVP species elsewhere in the Western Hemisphere"

  defp report_count(summary, "taxonomy-mismatches"), do: summary.taxonomy_mismatches
  defp report_count(summary, "in-gf-not-wcvp"), do: summary.gf_not_in_wcvp
  defp report_count(summary, "range-updates"), do: summary.range_updates
  defp report_count(summary, "in-wcvp-not-gf-usca"), do: summary.wcvp_not_in_gf_usca
  defp report_count(summary, "in-wcvp-not-gf-hemisphere"), do: summary.wcvp_not_in_gf_hemisphere

  defp report_icon("taxonomy-mismatches"), do: "ph-arrows-left-right"
  defp report_icon("in-gf-not-wcvp"), do: "ph-magnifying-glass"
  defp report_icon("range-updates"), do: "ph-map-pin"
  defp report_icon("in-wcvp-not-gf-usca"), do: "ph-flag"
  defp report_icon("in-wcvp-not-gf-hemisphere"), do: "ph-globe"

  @report_order ~w(
    taxonomy-mismatches
    in-gf-not-wcvp
    range-updates
    in-wcvp-not-gf-usca
    in-wcvp-not-gf-hemisphere
  )

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :report_order, @report_order)

    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="WCVP Reconciliation">
      <div class="space-y-6">
        <%!-- Header with run selector --%>
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
          <%!-- Report cards --%>
          <div class="space-y-3">
            <div :for={report_name <- @report_order}>
              <% count = report_count(@summary, report_name) %>
              <% expanded = @expanded_report == report_name %>

              <%!-- Card header (clickable) --%>
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
                    name={if expanded, do: "ph-caret-up", else: "ph-caret-down"}
                    class="h-4 w-4 text-gray-400"
                  />
                </div>
              </button>

              <%!-- Expanded report table --%>
              <div
                :if={expanded}
                class="border border-t-0 border-gray-200 rounded-b-lg bg-white p-4"
              >
                <%!-- Search --%>
                <div class="mb-4 max-w-md">
                  <form phx-change="search" phx-submit="search">
                    <.search_input
                      id={"search-#{report_name}"}
                      name="query"
                      value={@search_query}
                      placeholder="Filter results..."
                      phx_debounce="300"
                    />
                  </form>
                </div>

                <% filtered = filtered_data(@report_data, @search_query) %>
                <% page_items = paginate(filtered, @current_page, @page_size) %>
                <% total = length(filtered) %>
                <% pages = total_pages(total, @page_size) %>

                <%!-- Report-specific table --%>
                {render_report_table(assigns, report_name, page_items)}

                <%!-- Pagination --%>
                <div class="mt-4 flex items-center justify-between text-sm text-gray-500">
                  <span>
                    Showing {min((@current_page - 1) * @page_size + 1, total)}-{min(@current_page * @page_size, total)} of {format_number(total)}
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
              Run <code class="bg-gray-100 px-1 rounded">mix gallformers.wcvp.reconcile</code> to generate reports.
            </p>
          </div>
        <% end %>
      </div>
    </Layouts.admin>
    """
  end

  # -- Report-specific table renderers --
  # Each returns a HEEx template fragment for the table rows specific to that report type.

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
              <.link navigate={~p"/admin/hosts/#{item["gf_species_id"]}"} class="text-gf-maroon hover:underline">
                <em>{item["gf_name"]}</em>
              </.link>
            </td>
            <td>
              <.badge variant={mismatch_variant(item["mismatch_type"])}>
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
              <.link navigate={~p"/admin/hosts/#{item["gf_species_id"]}"} class="text-gf-maroon hover:underline">
                <em>{item["gf_name"]}</em>
              </.link>
            </td>
            <td>{item["gf_family"]}</td>
            <td><em>{item["gf_genus"]}</em></td>
            <td>
              <em :if={item["closest_wcvp_match"]}>{item["closest_wcvp_match"]}</em>
              <span :if={!item["closest_wcvp_match"]} class="text-gray-400">—</span>
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
              <.link navigate={~p"/admin/hosts/#{item["gf_species_id"]}"} class="text-gf-maroon hover:underline">
                <em>{item["gf_name"]}</em>
              </.link>
            </td>
            <td class="text-sm">{length(item["current_places"])} places</td>
            <td>
              <span class="text-green-700 font-medium">+{length(item["new_places"])}</span>
              <span class="text-xs text-gray-500 ml-1">
                {Enum.take(item["new_places"], 5) |> Enum.join(", ")}{if length(item["new_places"]) > 5, do: "..."}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp render_report_table(assigns, "in-wcvp-not-gf-usca", items) do
    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="overflow-x-auto">
      <table class="gf-table gf-table-dark gf-table-compact">
        <thead>
          <tr>
            <th>WCVP Name</th>
            <th>Family</th>
            <th>Distribution</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={item <- @items}>
            <td><em>{item["wcvp_name"]}</em></td>
            <td>{item["wcvp_family"]}</td>
            <td class="text-sm text-gray-600">
              {Enum.take(item["wcvp_distribution"] || [], 5) |> Enum.join(", ")}{if length(item["wcvp_distribution"] || []) > 5, do: "..."}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp render_report_table(assigns, "in-wcvp-not-gf-hemisphere", items) do
    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="overflow-x-auto">
      <table class="gf-table gf-table-dark gf-table-compact">
        <thead>
          <tr>
            <th>WCVP Name</th>
            <th>Family</th>
            <th>Distribution</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={item <- @items}>
            <td><em>{item["wcvp_name"]}</em></td>
            <td>{item["wcvp_family"]}</td>
            <td class="text-sm text-gray-600">
              {Enum.take(item["wcvp_distribution"] || [], 5) |> Enum.join(", ")}{if length(item["wcvp_distribution"] || []) > 5, do: "..."}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp mismatch_variant("synonym"), do: "warning"
  defp mismatch_variant("family"), do: "danger"
  defp mismatch_variant("genus"), do: "danger"
  defp mismatch_variant("fuzzy_name"), do: "info"
  defp mismatch_variant(_), do: "default"
end
```

**Step 3: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: Clean compile.

**Step 4: Commit**

```bash
git add lib/gallformers_web/live/admin/reconciliation_live.ex lib/gallformers_web/router.ex
git commit -m "Add admin reconciliation reports page with expandable report tables"
```

---

### Task 4: Verify End-to-End

**Step 1: Run the full test suite**

Run: `mix precommit`
Expected: All checks pass (format, credo, tests).

**Step 2: Manual verification**

Start the dev server (`mix phx.server`), log in as admin, and verify:
1. Dashboard shows the reconciliation card with correct counts
2. Clicking the card navigates to `/admin/reconciliation`
3. Each report section expands/collapses
4. Search filters results
5. Pagination works on the US/CA report (17K entries)

**Step 3: Fix any issues found and commit**

If precommit or manual testing reveals issues, fix them and commit as a separate "Fix ..." commit.
