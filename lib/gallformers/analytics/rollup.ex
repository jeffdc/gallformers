defmodule Gallformers.Analytics.Rollup do
  @moduledoc """
  GenServer that aggregates raw `page_views` into daily summary tables.

  Runs nightly at ~00:05 UTC to roll up yesterday's data and prune old raw rows.
  On startup, backfills any past days that have raw data but no summary.
  """

  use GenServer

  import Ecto.Query

  require Logger

  alias Gallformers.Analytics.PageView
  alias Gallformers.Repo

  @default_prune_days 90

  # -- Public API --

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Aggregates a single day's raw page_views into the 5 summary tables.

  Idempotent: uses DELETE + INSERT for multi-row tables, INSERT OR REPLACE
  for the single-row daily_stats. Returns `:noop` if no raw data exists
  for the given day.
  """
  @spec rollup_day(Date.t()) :: :ok | :noop
  def rollup_day(date) do
    {from_dt, to_dt} = date_bounds(date)
    date_str = Date.to_iso8601(date)

    base_query =
      from(pv in PageView,
        where: pv.inserted_at >= ^from_dt and pv.inserted_at < ^to_dt
      )

    count = Repo.aggregate(base_query, :count)

    if count == 0 do
      :noop
    else
      Repo.transaction(fn ->
        rollup_daily_stats(base_query, date_str)
        rollup_daily_page_stats(base_query, date_str)
        rollup_daily_referrer_stats(base_query, date_str)
        rollup_daily_device_stats(base_query, date_str)
        rollup_daily_browser_stats(base_query, date_str)
      end)

      :ok
    end
  end

  @doc """
  Finds past days with raw page_views but no corresponding daily_stats row,
  and rolls up each missing day.
  """
  @spec backfill_missing() :: :ok
  def backfill_missing do
    raw_dates =
      from(pv in PageView,
        select: fragment("DISTINCT date(?)", pv.inserted_at)
      )
      |> Repo.all()

    %{rows: existing_rows} = Repo.query!("SELECT date FROM daily_stats", [])
    existing_dates = MapSet.new(existing_rows, fn [d] -> d end)

    today_str = Date.to_iso8601(Date.utc_today())

    missing =
      raw_dates
      |> Enum.reject(&(&1 == today_str or MapSet.member?(existing_dates, &1)))
      |> Enum.sort()

    results =
      for date_str <- missing do
        {:ok, date} = Date.from_iso8601(date_str)

        try do
          rollup_day(date)
        rescue
          e ->
            Logger.error("Analytics backfill failed for #{date_str}: #{Exception.message(e)}")
            {:error, date_str}
        end
      end

    failed = Enum.filter(results, &match?({:error, _}, &1))

    if failed != [] do
      Logger.warning(
        "Analytics backfill: #{length(failed)} dates failed out of #{length(missing)}"
      )
    end

    if missing != [] do
      Logger.info("Analytics backfill: processed #{length(missing) - length(failed)} dates")
    end

    :ok
  end

  @doc """
  Deletes raw page_views older than `days` days. Returns `{count, nil}`.
  """
  @spec prune_old_page_views(integer()) :: {non_neg_integer(), nil}
  def prune_old_page_views(days \\ @default_prune_days) do
    cutoff = NaiveDateTime.new!(Date.add(Date.utc_today(), -days), ~T[00:00:00])

    from(pv in PageView, where: pv.inserted_at < ^cutoff)
    |> Repo.delete_all()
  end

  # -- GenServer callbacks --

  @impl true
  def init(_opts) do
    Gallformers.Async.run(fn -> backfill_missing() end)
    schedule_next_run()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:run_rollup, state) do
    yesterday = Date.add(Date.utc_today(), -1)

    case rollup_day(yesterday) do
      :ok -> Logger.info("Analytics rollup completed for #{yesterday}")
      :noop -> Logger.debug("Analytics rollup: no data for #{yesterday}")
    end

    {pruned, _} = prune_old_page_views()

    if pruned > 0 do
      Logger.info("Analytics rollup: pruned #{pruned} old page views")
    end

    schedule_next_run()
    {:noreply, state}
  end

  # -- Private --

  defp schedule_next_run do
    ms = ms_until_next_run()
    Process.send_after(self(), :run_rollup, ms)
  end

  defp ms_until_next_run do
    now = NaiveDateTime.utc_now()
    today = NaiveDateTime.to_date(now)
    # Target: next midnight + 5 minutes
    target = NaiveDateTime.new!(Date.add(today, 1), ~T[00:05:00])
    max(NaiveDateTime.diff(target, now, :millisecond), 1_000)
  end

  defp date_bounds(date) do
    {NaiveDateTime.new!(date, ~T[00:00:00]), NaiveDateTime.new!(Date.add(date, 1), ~T[00:00:00])}
  end

  defp rollup_daily_stats(base_query, date_str) do
    %{page_views: pv, unique_visitors: uv} =
      from(pv in base_query,
        select: %{
          page_views: count(pv.id),
          unique_visitors: count(pv.visitor_hash, :distinct)
        }
      )
      |> Repo.one!()

    Repo.query!(
      "INSERT OR REPLACE INTO daily_stats (date, page_views, unique_visitors) VALUES (?, ?, ?)",
      [date_str, pv, uv]
    )
  end

  defp rollup_daily_page_stats(base_query, date_str) do
    rows =
      from(pv in base_query,
        group_by: pv.path,
        select: {pv.path, count(pv.id), count(pv.visitor_hash, :distinct)}
      )
      |> Repo.all()

    Repo.query!("DELETE FROM daily_page_stats WHERE date = ?", [date_str])

    for {path, views, unique} <- rows do
      Repo.query!(
        "INSERT INTO daily_page_stats (date, path, page_views, unique_visitors) VALUES (?, ?, ?, ?)",
        [date_str, path, views, unique]
      )
    end
  end

  defp rollup_daily_referrer_stats(base_query, date_str) do
    rows =
      from(pv in base_query,
        group_by: pv.referrer_host,
        select: {pv.referrer_host, count(pv.id)}
      )
      |> Repo.all()

    Repo.query!("DELETE FROM daily_referrer_stats WHERE date = ?", [date_str])

    for {referrer, views} <- rows do
      Repo.query!(
        "INSERT INTO daily_referrer_stats (date, referrer_host, page_views) VALUES (?, ?, ?)",
        [date_str, referrer, views]
      )
    end
  end

  defp rollup_daily_device_stats(base_query, date_str) do
    rows =
      from(pv in base_query,
        group_by: pv.device_type,
        select: {pv.device_type, count(pv.id)}
      )
      |> Repo.all()

    Repo.query!("DELETE FROM daily_device_stats WHERE date = ?", [date_str])

    for {device, cnt} <- rows do
      Repo.query!(
        "INSERT INTO daily_device_stats (date, device_type, count) VALUES (?, ?, ?)",
        [date_str, device, cnt]
      )
    end
  end

  defp rollup_daily_browser_stats(base_query, date_str) do
    rows =
      from(pv in base_query,
        group_by: pv.browser,
        select: {pv.browser, count(pv.id)}
      )
      |> Repo.all()

    Repo.query!("DELETE FROM daily_browser_stats WHERE date = ?", [date_str])

    for {browser, cnt} <- rows do
      Repo.query!(
        "INSERT INTO daily_browser_stats (date, browser, count) VALUES (?, ?, ?)",
        [date_str, browser, cnt]
      )
    end
  end
end
