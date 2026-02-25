defmodule Gallformers.Analytics do
  @moduledoc """
  The Analytics context.

  Provides privacy-respecting page view tracking and reporting.
  No personally identifiable information is stored - visitor uniqueness
  is determined by a daily hash that cannot be reversed.
  """

  import Ecto.Query

  require Logger

  alias Gallformers.Analytics.PageView
  alias Gallformers.Repo

  # Paths to exclude from tracking
  @excluded_path_prefixes ["/admin", "/api", "/assets", "/images", "/dev", "/health", "/auth"]
  @excluded_paths ["/favicon.ico", "/robots.txt", "/sitemap.xml", "/analytics"]

  # Bot user agent patterns (case-insensitive)
  @bot_patterns ~w(bot spider crawl slurp feedfetcher facebookexternalhit twitterbot linkedinbot)

  @doc """
  Records a page view asynchronously.

  Takes connection info and spawns a task to insert the record,
  ensuring page loads are never slowed by analytics.
  """
  @spec track_page_view(map()) :: :ok
  def track_page_view(attrs) do
    Gallformers.Async.run(fn ->
      case %PageView{} |> PageView.changeset(attrs) |> Repo.insert() do
        {:ok, _} ->
          :ok

        {:error, changeset} ->
          Logger.warning(
            "Analytics: failed to insert page view for #{attrs[:path]}: #{inspect(changeset.errors)}"
          )
      end
    end)
  end

  @doc """
  Determines if a request should be tracked.

  Returns false for:
  - Excluded paths (admin, api, assets, etc.)
  - Known bot user agents
  """
  @spec should_track?(String.t(), String.t() | nil) :: boolean()
  def should_track?(path, user_agent) do
    not excluded_path?(path) and not bot?(user_agent)
  end

  defp excluded_path?(path) do
    path in @excluded_paths or
      Enum.any?(@excluded_path_prefixes, &String.starts_with?(path, &1))
  end

  defp bot?(nil), do: false

  defp bot?(user_agent) do
    ua_lower = String.downcase(user_agent)
    Enum.any?(@bot_patterns, &String.contains?(ua_lower, &1))
  end

  @doc """
  Generates a daily visitor hash from IP and user agent.

  This allows counting unique visitors without storing identifiable data.
  The hash changes daily, preventing cross-day tracking.
  """
  @spec generate_visitor_hash(String.t(), String.t() | nil) :: String.t()
  def generate_visitor_hash(ip, user_agent) do
    date = Date.utc_today() |> Date.to_iso8601()
    data = "#{date}|#{ip}|#{user_agent || ""}"
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower) |> binary_part(0, 16)
  end

  @doc """
  Extracts the host from a referrer URL.

  Returns nil for empty referrers or same-site referrers.
  """
  @spec extract_referrer_host(String.t() | nil, String.t()) :: String.t() | nil
  def extract_referrer_host(nil, _site_host), do: nil
  def extract_referrer_host("", _site_host), do: nil

  def extract_referrer_host(referrer, site_host) do
    case URI.parse(referrer) do
      %URI{host: nil} -> nil
      %URI{host: host} when host == site_host -> nil
      %URI{host: host} -> host
    end
  end

  @doc """
  Parses user agent into browser family and device type.
  """
  @spec parse_user_agent(String.t() | nil) :: {String.t() | nil, String.t() | nil}
  def parse_user_agent(nil), do: {nil, nil}

  def parse_user_agent(user_agent) do
    {detect_browser(user_agent), detect_device_type(user_agent)}
  end

  defp detect_browser(user_agent) do
    detect_chromium_based(user_agent) ||
      detect_common_browsers(user_agent) ||
      "Other"
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp detect_chromium_based(user_agent) do
    cond do
      String.contains?(user_agent, "SamsungBrowser") -> "Samsung Internet"
      String.contains?(user_agent, "Brave") -> "Brave"
      String.contains?(user_agent, "Arc/") -> "Arc"
      String.contains?(user_agent, "Vivaldi") -> "Vivaldi"
      String.contains?(user_agent, "DuckDuckGo") -> "DuckDuckGo"
      Browser.edge?(user_agent) -> "Edge"
      Browser.opera?(user_agent) -> "Opera"
      Browser.chrome?(user_agent) -> "Chrome"
      true -> nil
    end
  end

  defp detect_common_browsers(user_agent) do
    cond do
      Browser.firefox?(user_agent) -> "Firefox"
      safari_ios?(user_agent) -> "Safari (iOS)"
      Browser.safari?(user_agent) -> "Safari"
      Browser.ie?(user_agent) -> "IE"
      true -> nil
    end
  end

  defp safari_ios?(user_agent) do
    Browser.safari?(user_agent) and
      (String.contains?(user_agent, "iPhone") or String.contains?(user_agent, "iPad"))
  end

  defp detect_device_type(user_agent) do
    cond do
      Browser.mobile?(user_agent) -> "mobile"
      Browser.tablet?(user_agent) -> "tablet"
      true -> "desktop"
    end
  end

  # =================================================================
  # Query Functions
  # =================================================================

  # Converts a date range to NaiveDateTime bounds using half-open interval [from, to).
  # The upper bound is midnight of the day AFTER to_date, ensuring all timestamps
  # on the last day are included regardless of sub-second precision.
  defp date_bounds(from_date, to_date) do
    {NaiveDateTime.new!(from_date, ~T[00:00:00]),
     NaiveDateTime.new!(Date.add(to_date, 1), ~T[00:00:00])}
  end

  # Determines which data sources to use for a date range.
  # Returns:
  #   {:raw_only, from, to}           - entire range uses raw page_views
  #   {:summary_only, from, to}       - entire range uses summary tables
  #   {:mixed, from, summary_end, today} - past days from summaries, today from raw
  defp split_range(from_date, to_date) do
    today = Date.utc_today()

    cond do
      # Entire range is today only -> raw
      from_date == today and to_date == today ->
        {:raw_only, from_date, to_date}

      # Range ends before today -> summaries only
      Date.compare(to_date, today) == :lt ->
        {:summary_only, from_date, to_date}

      # Range starts today or later -> raw only
      Date.compare(from_date, today) != :lt ->
        {:raw_only, from_date, to_date}

      # Mixed: past days use summaries, today uses raw
      true ->
        {:mixed, from_date, Date.add(today, -1), today}
    end
  end

  @doc """
  Returns page view stats for a date range.
  """
  @spec stats(Date.t(), Date.t()) :: map()
  def stats(from_date, to_date) do
    case split_range(from_date, to_date) do
      {:raw_only, from, to} ->
        raw_stats(from, to)

      {:summary_only, from, to} ->
        summary_stats(from, to)

      {:mixed, from, summary_end, today} ->
        s = summary_stats(from, summary_end)
        r = raw_stats(today, today)

        %{
          page_views: s.page_views + r.page_views,
          unique_visitors: s.unique_visitors + r.unique_visitors
        }
    end
  end

  defp raw_stats(from_date, to_date) do
    {from_dt, to_dt} = date_bounds(from_date, to_date)

    query =
      from(pv in PageView,
        where: pv.inserted_at >= ^from_dt and pv.inserted_at < ^to_dt,
        select: %{
          page_views: count(pv.id),
          unique_visitors: count(pv.visitor_hash, :distinct)
        }
      )

    Repo.one(query) || %{page_views: 0, unique_visitors: 0}
  end

  defp summary_stats(from_date, to_date) do
    from_str = Date.to_iso8601(from_date)
    to_str = Date.to_iso8601(to_date)

    result =
      from(ds in "daily_stats",
        where: ds.date >= ^from_str and ds.date <= ^to_str,
        select: %{
          page_views: sum(ds.page_views),
          unique_visitors: sum(ds.unique_visitors)
        }
      )
      |> Repo.one()

    %{
      page_views: result.page_views || 0,
      unique_visitors: result.unique_visitors || 0
    }
  end

  @doc """
  Returns daily breakdown of page views and unique visitors for a date range.

  Each day in the range is included, even if there were no page views.
  Returns a list of maps with keys: :date, :page_views, :unique_visitors
  """
  @spec daily_stats(Date.t(), Date.t()) :: [map()]
  def daily_stats(from_date, to_date) do
    stats_with_data =
      case split_range(from_date, to_date) do
        {:raw_only, from, to} ->
          raw_daily_stats(from, to)

        {:summary_only, from, to} ->
          summary_daily_stats(from, to)

        {:mixed, from, summary_end, today} ->
          summary_daily_stats(from, summary_end) ++ raw_daily_stats(today, today)
      end

    fill_missing_days(from_date, to_date, stats_with_data)
  end

  defp raw_daily_stats(from_date, to_date) do
    {from_dt, to_dt} = date_bounds(from_date, to_date)

    from(pv in PageView,
      where: pv.inserted_at >= ^from_dt and pv.inserted_at < ^to_dt,
      group_by: fragment("date(?)", pv.inserted_at),
      select: %{
        date: fragment("date(?)", pv.inserted_at),
        page_views: count(pv.id),
        unique_visitors: count(pv.visitor_hash, :distinct)
      },
      order_by: fragment("date(?)", pv.inserted_at)
    )
    |> Repo.all()
    |> Enum.map(fn stat ->
      {:ok, date} = Date.from_iso8601(stat.date)
      %{stat | date: date}
    end)
  end

  defp summary_daily_stats(from_date, to_date) do
    from_str = Date.to_iso8601(from_date)
    to_str = Date.to_iso8601(to_date)

    from(ds in "daily_stats",
      where: ds.date >= ^from_str and ds.date <= ^to_str,
      select: %{
        date: ds.date,
        page_views: ds.page_views,
        unique_visitors: ds.unique_visitors
      },
      order_by: ds.date
    )
    |> Repo.all()
    |> Enum.map(fn stat ->
      {:ok, date} = Date.from_iso8601(stat.date)
      %{stat | date: date}
    end)
  end

  defp fill_missing_days(from_date, to_date, stats_with_data) do
    # Create a map for quick lookup
    stats_map = Map.new(stats_with_data, &{&1.date, &1})

    # Generate all dates in range
    Date.range(from_date, to_date)
    |> Enum.map(fn date ->
      Map.get(stats_map, date, %{
        date: date,
        page_views: 0,
        unique_visitors: 0
      })
    end)
    # Explicitly sort by date to ensure chronological order
    # (Enum.sort doesn't work correctly on Date structs due to term ordering)
    |> Enum.sort_by(& &1.date, Date)
  end

  @doc """
  Returns top pages for a date range.
  """
  @spec top_pages(Date.t(), Date.t(), integer()) :: [map()]
  def top_pages(from_date, to_date, limit \\ 20) do
    case split_range(from_date, to_date) do
      {:raw_only, from, to} ->
        raw_top_pages(from, to, limit)

      {:summary_only, from, to} ->
        summary_top_pages(from, to, limit)

      {:mixed, from, summary_end, today} ->
        merge_by_key(
          summary_top_pages(from, summary_end, :unlimited),
          raw_top_pages(today, today, :unlimited),
          :path,
          fn a, b ->
            %{
              path: a.path,
              views: a.views + b.views,
              unique_visitors: a.unique_visitors + b.unique_visitors
            }
          end
        )
        |> Enum.sort_by(& &1.views, :desc)
        |> Enum.take(limit)
    end
  end

  defp raw_top_pages(from_date, to_date, limit) do
    {from_dt, to_dt} = date_bounds(from_date, to_date)

    query =
      from(pv in PageView,
        where: pv.inserted_at >= ^from_dt and pv.inserted_at < ^to_dt,
        group_by: pv.path,
        select: %{
          path: pv.path,
          views: count(pv.id),
          unique_visitors: count(pv.visitor_hash, :distinct)
        },
        order_by: [desc: count(pv.id)]
      )

    query = if limit == :unlimited, do: query, else: from(q in query, limit: ^limit)
    Repo.all(query)
  end

  defp summary_top_pages(from_date, to_date, limit) do
    from_str = Date.to_iso8601(from_date)
    to_str = Date.to_iso8601(to_date)

    query =
      from(dp in "daily_page_stats",
        where: dp.date >= ^from_str and dp.date <= ^to_str,
        group_by: dp.path,
        select: %{
          path: dp.path,
          views: sum(dp.page_views),
          unique_visitors: sum(dp.unique_visitors)
        },
        order_by: [desc: sum(dp.page_views)]
      )

    query = if limit == :unlimited, do: query, else: from(q in query, limit: ^limit)
    Repo.all(query)
  end

  @doc """
  Returns top referrers for a date range.
  """
  @spec top_referrers(Date.t(), Date.t()) :: [map()]
  def top_referrers(from_date, to_date) do
    rows =
      case split_range(from_date, to_date) do
        {:raw_only, from, to} ->
          raw_top_referrers(from, to)

        {:summary_only, from, to} ->
          summary_top_referrers(from, to)

        {:mixed, from, summary_end, today} ->
          merge_by_key(
            summary_top_referrers(from, summary_end),
            raw_top_referrers(today, today),
            :referrer,
            fn a, b -> %{referrer: a.referrer, views: a.views + b.views} end
          )
          |> Enum.sort_by(& &1.views, :desc)
      end

    Enum.map(rows, fn row ->
      label =
        case row.referrer do
          nil -> "Direct"
          "(internal)" -> "Internal"
          host -> host
        end

      %{row | referrer: label}
    end)
  end

  defp raw_top_referrers(from_date, to_date) do
    {from_dt, to_dt} = date_bounds(from_date, to_date)

    from(pv in PageView,
      where: pv.inserted_at >= ^from_dt and pv.inserted_at < ^to_dt,
      group_by: pv.referrer_host,
      select: %{
        referrer: pv.referrer_host,
        views: count(pv.id)
      },
      order_by: [desc: count(pv.id)]
    )
    |> Repo.all()
  end

  defp summary_top_referrers(from_date, to_date) do
    from_str = Date.to_iso8601(from_date)
    to_str = Date.to_iso8601(to_date)

    from(dr in "daily_referrer_stats",
      where: dr.date >= ^from_str and dr.date <= ^to_str,
      group_by: dr.referrer_host,
      select: %{
        referrer: dr.referrer_host,
        views: sum(dr.page_views)
      },
      order_by: [desc: sum(dr.page_views)]
    )
    |> Repo.all()
  end

  @doc """
  Returns device type breakdown for a date range.
  """
  @spec device_breakdown(Date.t(), Date.t()) :: [map()]
  def device_breakdown(from_date, to_date) do
    rows =
      case split_range(from_date, to_date) do
        {:raw_only, from, to} ->
          raw_device_breakdown(from, to)

        {:summary_only, from, to} ->
          summary_device_breakdown(from, to)

        {:mixed, from, summary_end, today} ->
          merge_by_key(
            summary_device_breakdown(from, summary_end),
            raw_device_breakdown(today, today),
            :device_type,
            fn a, b -> %{device_type: a.device_type, count: a.count + b.count} end
          )
          |> Enum.sort_by(& &1.count, :desc)
      end

    Enum.map(rows, fn row ->
      %{row | device_type: row.device_type || "Unknown"}
    end)
  end

  defp raw_device_breakdown(from_date, to_date) do
    {from_dt, to_dt} = date_bounds(from_date, to_date)

    from(pv in PageView,
      where: pv.inserted_at >= ^from_dt and pv.inserted_at < ^to_dt,
      group_by: pv.device_type,
      select: %{
        device_type: pv.device_type,
        count: count(pv.id)
      },
      order_by: [desc: count(pv.id)]
    )
    |> Repo.all()
  end

  defp summary_device_breakdown(from_date, to_date) do
    from_str = Date.to_iso8601(from_date)
    to_str = Date.to_iso8601(to_date)

    from(dd in "daily_device_stats",
      where: dd.date >= ^from_str and dd.date <= ^to_str,
      group_by: dd.device_type,
      select: %{
        device_type: dd.device_type,
        count: sum(dd.count)
      },
      order_by: [desc: sum(dd.count)]
    )
    |> Repo.all()
  end

  @doc """
  Returns browser breakdown for a date range.
  """
  @spec browser_breakdown(Date.t(), Date.t()) :: [map()]
  def browser_breakdown(from_date, to_date) do
    rows =
      case split_range(from_date, to_date) do
        {:raw_only, from, to} ->
          raw_browser_breakdown(from, to)

        {:summary_only, from, to} ->
          summary_browser_breakdown(from, to)

        {:mixed, from, summary_end, today} ->
          merge_by_key(
            summary_browser_breakdown(from, summary_end),
            raw_browser_breakdown(today, today),
            :browser,
            fn a, b -> %{browser: a.browser, count: a.count + b.count} end
          )
          |> Enum.sort_by(& &1.count, :desc)
      end

    Enum.map(rows, fn row ->
      %{row | browser: row.browser || "Unknown"}
    end)
  end

  defp raw_browser_breakdown(from_date, to_date) do
    {from_dt, to_dt} = date_bounds(from_date, to_date)

    from(pv in PageView,
      where: pv.inserted_at >= ^from_dt and pv.inserted_at < ^to_dt,
      group_by: pv.browser,
      select: %{
        browser: pv.browser,
        count: count(pv.id)
      },
      order_by: [desc: count(pv.id)]
    )
    |> Repo.all()
  end

  defp summary_browser_breakdown(from_date, to_date) do
    from_str = Date.to_iso8601(from_date)
    to_str = Date.to_iso8601(to_date)

    from(db in "daily_browser_stats",
      where: db.date >= ^from_str and db.date <= ^to_str,
      group_by: db.browser,
      select: %{
        browser: db.browser,
        count: sum(db.count)
      },
      order_by: [desc: sum(db.count)]
    )
    |> Repo.all()
  end

  # Merges two lists of maps by a key field, combining duplicates with merge_fn.
  # Items that only appear in one list are included as-is.
  defp merge_by_key(list_a, list_b, key, merge_fn) do
    b_map = Map.new(list_b, &{Map.get(&1, key), &1})

    {merged, used_keys} =
      Enum.reduce(list_a, {[], MapSet.new()}, fn a, {acc, used} ->
        k = Map.get(a, key)

        case Map.get(b_map, k) do
          nil -> {[a | acc], used}
          b -> {[merge_fn.(a, b) | acc], MapSet.put(used, k)}
        end
      end)

    # Add items from list_b that weren't in list_a
    only_in_b =
      Enum.reject(list_b, fn b -> MapSet.member?(used_keys, Map.get(b, key)) end)

    Enum.reverse(merged) ++ only_in_b
  end
end
