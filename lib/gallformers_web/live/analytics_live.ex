defmodule GallformersWeb.AnalyticsLive do
  @moduledoc """
  Public page for viewing site analytics.

  Displays page views, unique visitors, top pages, referrers,
  device types, and browser breakdown for a configurable date range.
  """

  use GallformersWeb, :live_view

  alias Gallformers.Analytics

  @default_range "today"
  @referrer_page_size 15
  @ranges %{
    "today" => 0,
    "7d" => 6,
    "30d" => 29,
    "90d" => 89
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Analytics")
      |> assign(:page_description, "View Gallformers site usage statistics and analytics.")
      |> assign(:page_url, "/analytics")
      |> assign(:page_image, nil)
      |> assign(:page_json_ld, nil)
      |> assign(:current_range, @default_range)
      |> load_analytics(@default_range)

    {:ok, socket}
  end

  @impl true
  def handle_event("change_range", %{"range" => range}, socket) do
    socket =
      socket
      |> assign(:current_range, range)
      |> load_analytics(range)

    {:noreply, socket}
  end

  def handle_event("referrer_page", %{"page" => page}, socket) when is_integer(page) do
    {:noreply, assign_referrer_page(socket, socket.assigns.all_referrers, page)}
  end

  defp load_analytics(socket, range) do
    {from_date, to_date} = date_range(range)
    is_single_day = from_date == to_date
    all_referrers = Analytics.top_referrers(from_date, to_date)

    socket
    |> assign(:from_date, from_date)
    |> assign(:to_date, to_date)
    |> assign(:is_single_day, is_single_day)
    |> assign(:stats, if(is_single_day, do: Analytics.stats(from_date, to_date), else: nil))
    |> assign(
      :daily_stats,
      if(is_single_day, do: nil, else: Analytics.daily_stats(from_date, to_date))
    )
    |> assign(:top_pages, Analytics.top_pages(from_date, to_date))
    |> assign(:all_referrers, all_referrers)
    |> assign(:referrer_page, 1)
    |> assign_referrer_page(all_referrers, 1)
    |> assign(:devices, add_percentages(Analytics.device_breakdown(from_date, to_date)))
    |> assign(:browsers, add_percentages(Analytics.browser_breakdown(from_date, to_date)))
  end

  defp assign_referrer_page(socket, all_referrers, page) do
    total = length(all_referrers)
    total_pages = max(1, ceil(total / @referrer_page_size))
    page = min(page, total_pages)

    paged =
      all_referrers
      |> Enum.drop((page - 1) * @referrer_page_size)
      |> Enum.take(@referrer_page_size)

    socket
    |> assign(:referrer_page, page)
    |> assign(:referrer_total_pages, total_pages)
    |> assign(:top_referrers, paged)
  end

  defp date_range(range) do
    days_ago = Map.get(@ranges, range, 6)
    to_date = Date.utc_today()
    from_date = Date.add(to_date, -days_ago)
    {from_date, to_date}
  end

  defp add_percentages(items) do
    total = Enum.reduce(items, 0, fn item, acc -> acc + item.count end)

    Enum.map(items, fn item ->
      percentage = if total > 0, do: Float.round(item.count / total * 100, 1), else: 0.0
      Map.put(item, :percentage, percentage)
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gf-maroon mb-2">Site Analytics</h1>
          <p class="text-gray-600">
            Transparent site usage statistics. Learn more about our <.link
              href="/privacy"
              class="text-gf-maroon hover:underline"
            >privacy-protecting analytics</.link>.
          </p>
        </div>

        <%!-- Date Range Selector --%>
        <div class="flex items-center gap-2">
          <span class="text-sm text-gray-600">Period:</span>
          <.range_button range="today" label="Today" current={@current_range} />
          <.range_button range="7d" label="7 days" current={@current_range} />
          <.range_button range="30d" label="30 days" current={@current_range} />
          <.range_button range="90d" label="90 days" current={@current_range} />
        </div>

        <%!-- Stats Summary (single day only) --%>
        <div :if={@is_single_day} class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <.stat_card title="Page Views" value={@stats.page_views} icon="ph-eye" />
          <.stat_card title="Unique Visitors" value={@stats.unique_visitors} icon="ph-users" />
        </div>

        <%!-- Daily Breakdown Chart (multi-day) --%>
        <div :if={!@is_single_day} class="bg-white rounded-lg border border-gray-200 overflow-hidden">
          <div class="px-4 py-3 border-b border-gray-200 bg-gray-50">
            <h3 class="text-lg font-semibold text-gray-900">Daily Breakdown</h3>
            <p class="text-sm text-gray-600 mt-1">
              Note: Unique visitors are counted per day. The same person visiting on different days appears as unique on each day.
            </p>
          </div>
          <div class="p-4">
            <.daily_chart data={@daily_stats} />
          </div>
        </div>

        <%!-- Top Pages --%>
        <div class="bg-white rounded-lg border border-gray-200 overflow-hidden">
          <div class="px-4 py-3 border-b border-gray-200 bg-gray-50">
            <h3 class="text-lg font-semibold text-gray-900">Top Pages</h3>
          </div>
          <table class="gf-table gf-table-dense">
            <thead>
              <tr>
                <th>Path</th>
                <th class="text-center">Views</th>
                <th class="text-center">Unique Visitors</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={page <- @top_pages}>
                <td class="font-mono text-sm">{page.path}</td>
                <td class="text-center">{format_number(page.views)}</td>
                <td class="text-center">{format_number(page.unique_visitors)}</td>
              </tr>
              <tr :if={@top_pages == []}>
                <td colspan="3" class="text-center text-gray-500 py-8">
                  No page views recorded for this period.
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%!-- Two Column Layout for Referrers and Device/Browser --%>
        <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <%!-- Top Referrers --%>
          <div class="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <div class="px-4 py-3 border-b border-gray-200 bg-gray-50">
              <h3 class="text-lg font-semibold text-gray-900">Top Referrers</h3>
            </div>
            <table class="gf-table gf-table-dense">
              <thead>
                <tr>
                  <th>Source</th>
                  <th class="text-center">Views</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={referrer <- @top_referrers}>
                  <td>{referrer.referrer}</td>
                  <td class="text-center">{format_number(referrer.views)}</td>
                </tr>
                <tr :if={@top_referrers == []}>
                  <td colspan="2" class="text-center text-gray-500 py-8">
                    No referrer data for this period.
                  </td>
                </tr>
              </tbody>
            </table>
            <div :if={@referrer_total_pages > 1} class="px-4 py-2 border-t border-gray-200">
              <.pagination
                page={@referrer_page}
                total_pages={@referrer_total_pages}
                total_items={length(@all_referrers)}
                page_size={15}
                on_page_change={fn page -> JS.push("referrer_page", value: %{page: page}) end}
              />
            </div>
          </div>

          <%!-- Devices and Browsers --%>
          <div class="space-y-6">
            <%!-- Devices --%>
            <div class="bg-white rounded-lg border border-gray-200 overflow-hidden">
              <div class="px-4 py-3 border-b border-gray-200 bg-gray-50">
                <h3 class="text-lg font-semibold text-gray-900">Devices</h3>
              </div>
              <table class="gf-table gf-table-dense">
                <thead>
                  <tr>
                    <th>Type</th>
                    <th class="text-center">Count</th>
                    <th class="text-center">%</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={device <- @devices}>
                    <td class="capitalize">{device.device_type}</td>
                    <td class="text-center">{format_number(device.count)}</td>
                    <td class="text-center">{device.percentage}%</td>
                  </tr>
                  <tr :if={@devices == []}>
                    <td colspan="3" class="text-center text-gray-500 py-8">
                      No device data for this period.
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <%!-- Browsers --%>
            <div class="bg-white rounded-lg border border-gray-200 overflow-hidden">
              <div class="px-4 py-3 border-b border-gray-200 bg-gray-50">
                <h3 class="text-lg font-semibold text-gray-900">Browsers</h3>
              </div>
              <table class="gf-table gf-table-dense">
                <thead>
                  <tr>
                    <th>Browser</th>
                    <th class="text-center">Count</th>
                    <th class="text-center">%</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={browser <- @browsers}>
                    <td>{browser.browser}</td>
                    <td class="text-center">{format_number(browser.count)}</td>
                    <td class="text-center">{browser.percentage}%</td>
                  </tr>
                  <tr :if={@browsers == []}>
                    <td colspan="3" class="text-center text-gray-500 py-8">
                      No browser data for this period.
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # =================================================================
  # Private Components
  # =================================================================

  defp range_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="change_range"
      phx-value-range={@range}
      class={[
        "px-3 py-1 text-sm rounded-md transition-colors",
        if(@range == @current,
          do: "bg-gf-maroon text-white",
          else: "bg-gray-100 text-gray-700 hover:bg-gray-200"
        )
      ]}
    >
      {@label}
    </button>
    """
  end

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-white rounded-lg border border-gray-200 p-4">
      <div class="flex items-center">
        <div class="flex-shrink-0">
          <div class="rounded-md bg-gf-maroon/10 p-3">
            <.icon name={@icon} class="h-6 w-6 text-gf-maroon" />
          </div>
        </div>
        <div class="ml-4">
          <dt class="text-sm font-medium text-gray-500">{@title}</dt>
          <dd class="text-2xl font-semibold text-gray-900">{format_number(@value)}</dd>
        </div>
      </div>
    </div>
    """
  end

  defp daily_chart(assigns) do
    # Prepare data for D3 (format dates nicely)
    chart_data =
      Enum.map(assigns.data, fn day ->
        %{
          date: Calendar.strftime(day.date, "%b %d"),
          page_views: day.page_views,
          unique_visitors: day.unique_visitors
        }
      end)

    assigns = assign(assigns, :chart_data, Jason.encode!(chart_data))

    ~H"""
    <div
      :if={@data != []}
      phx-hook="DailyChart"
      id="daily-analytics-chart"
      data-chart={@chart_data}
      class="w-full"
    >
    </div>
    <div :if={@data == []} class="text-center text-gray-500 py-8">
      No data for this period.
    </div>
    """
  end
end
