defmodule GallformersWeb.AnalyticsLive do
  @moduledoc """
  The public analytics page (design system, matter bc0d): for a period
  (`?range=` today, 7d, 30d or 90d; today by default) the totals, the daily
  page views and unique visitors as a `bar_chart` (longer periods), top
  pages, referrers (15 a page), and devices and browsers as `share_list`s.
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

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    range = if Map.has_key?(@ranges, params["range"]), do: params["range"], else: @default_range

    {:noreply, socket |> assign(:current_range, range) |> load_analytics(range)}
  end

  @impl true

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

  defp range_labels,
    do: [{"today", "Today"}, {"7d", "7 days"}, {"30d", "30 days"}, {"90d", "90 days"}]

  defp totals(true, stats, _days),
    do: [{stats.page_views, "Page views"}, {stats.unique_visitors, "Unique visitors"}]

  defp totals(false, _stats, days) do
    views = Enum.sum(Enum.map(days, & &1.page_views))
    visitors = Enum.sum(Enum.map(days, & &1.unique_visitors))
    busiest = Enum.max_by(days, & &1.page_views, fn -> nil end)

    [
      {views, "Page views"},
      {if(days == [], do: 0, else: round(visitors / length(days))), "Visitors a day, on average"}
    ] ++
      if(busiest,
        do: [
          {busiest.page_views,
           "Views on the busiest day (#{Calendar.strftime(busiest.date, "%b %-d")})"}
        ],
        else: []
      )
  end

  defp chart_rows(days) do
    Enum.map(days, fn d ->
      %{
        label: Calendar.strftime(d.date, "%b %-d"),
        views: d.page_views,
        visitors: d.unique_visitors
      }
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:title>Site analytics</:title>
          <:description>
            How Gallformers is used, counted without tracking anyone: see our <.link href="/privacy">privacy-protecting analytics</.link>.
          </:description>
        </.page_header>

        <.chip_nav label="Period">
          <:chip
            :for={{range, label} <- range_labels()}
            patch={~p"/analytics?range=#{range}"}
            current={@current_range == range}
          >
            {label}
          </:chip>
        </.chip_nav>

        <div class="flex flex-wrap gap-x-12 gap-y-4">
          <.stat
            :for={{value, label} <- totals(@is_single_day, @stats, @daily_stats)}
            value={value}
            label={label}
          />
        </div>

        <.section :if={!@is_single_day} title="Each day">
          <.bar_chart
            id="daily-analytics-chart"
            label="Page views and unique visitors by day"
            data={chart_rows(@daily_stats)}
            series={[
              %{key: :views, label: "Page views", tone: :brand},
              %{key: :visitors, label: "Unique visitors", tone: :autumn}
            ]}
          />
          <p class="mt-2 text-meta text-muted">
            Visitors are counted per day: someone who comes back on another day counts again.
          </p>
        </.section>

        <.section title="Top pages" count={length(@top_pages)}>
          <.data_table id="top-pages" rows={@top_pages} row_id={& &1.path} compact>
            <:col :let={page} label="Page" grow>
              <.link href={page.path} class="font-mono text-meta">{page.path}</.link>
            </:col>
            <:col :let={page} label="Views" numeric>{format_number(page.views)}</:col>
            <:col :let={page} label="Visitors" numeric>{format_number(page.unique_visitors)}</:col>
            <:empty>No page views in this period.</:empty>
          </.data_table>
        </.section>

        <div class="grid gap-section lg:grid-cols-2">
          <.section title="Where visitors came from" count={length(@all_referrers)}>
            <.data_table id="referrers" rows={@top_referrers} row_id={& &1.referrer} compact>
              <:col :let={r} label="Site" grow>{r.referrer}</:col>
              <:col :let={r} label="Views" numeric>{format_number(r.views)}</:col>
              <:empty>No referrers in this period.</:empty>
              <:footer :if={@referrer_total_pages > 1}>
                <.pagination
                  page={@referrer_page}
                  total_pages={@referrer_total_pages}
                  total_items={length(@all_referrers)}
                  page_size={15}
                  on_page_change={fn page -> JS.push("referrer_page", value: %{page: page}) end}
                />
              </:footer>
            </.data_table>
          </.section>

          <div class="flex flex-col gap-section">
            <.section title="Devices">
              <.share_list
                id="devices"
                items={@devices}
                name={&String.capitalize(&1.device_type || "unknown")}
              />
            </.section>
            <.section title="Browsers">
              <.share_list id="browsers" items={@browsers} name={&(&1.browser || "Unknown")} />
            </.section>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
