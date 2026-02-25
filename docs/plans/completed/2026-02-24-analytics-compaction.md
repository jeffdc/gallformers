# Analytics Compaction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Roll up raw page_views into summary tables so multi-day analytics queries are fast at any range, and cap unbounded table growth with a 90-day retention window.

**Architecture:** Five summary tables aggregated nightly by a GenServer. Multi-day queries read summaries + today's raw data. Raw rows pruned after 90 days.

**Tech Stack:** Ecto migrations (SQLite), GenServer, existing Analytics context

---

### Task 1: Migration — Create summary tables

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_create_analytics_summary_tables.exs`

**Step 1: Generate the migration**

Run: `mix ecto.gen.migration create_analytics_summary_tables`

**Step 2: Write the migration**

```elixir
defmodule Gallformers.Repo.Migrations.CreateAnalyticsSummaryTables do
  use Ecto.Migration

  def change do
    create table(:daily_stats) do
      add :date, :date, null: false
      add :page_views, :integer, null: false, default: 0
      add :unique_visitors, :integer, null: false, default: 0
    end

    create unique_index(:daily_stats, [:date])

    create table(:daily_page_stats) do
      add :date, :date, null: false
      add :path, :string, null: false
      add :page_views, :integer, null: false, default: 0
      add :unique_visitors, :integer, null: false, default: 0
    end

    create unique_index(:daily_page_stats, [:date, :path])
    create index(:daily_page_stats, [:date])

    create table(:daily_referrer_stats) do
      add :date, :date, null: false
      add :referrer_host, :string
      add :page_views, :integer, null: false, default: 0
    end

    create unique_index(:daily_referrer_stats, [:date, :referrer_host])
    create index(:daily_referrer_stats, [:date])

    create table(:daily_device_stats) do
      add :date, :date, null: false
      add :device_type, :string
      add :count, :integer, null: false, default: 0
    end

    create unique_index(:daily_device_stats, [:date, :device_type])
    create index(:daily_device_stats, [:date])

    create table(:daily_browser_stats) do
      add :date, :date, null: false
      add :browser, :string
      add :count, :integer, null: false, default: 0
    end

    create unique_index(:daily_browser_stats, [:date, :browser])
    create index(:daily_browser_stats, [:date])
  end
end
```

**Step 3: Run the migration**

Run: `mix ecto.migrate`
Expected: Migration runs cleanly, 5 tables created.

**Step 4: Commit**

```
git add priv/repo/migrations/*create_analytics_summary_tables*
git commit -m "Add analytics summary tables for rollup compaction"
```

---

### Task 2: Rollup logic — `Analytics.Rollup` GenServer

**Files:**
- Create: `lib/gallformers/analytics/rollup.ex`
- Modify: `lib/gallformers/application.ex:10-21` (add to children)

**Step 1: Write the failing test**

Create `test/gallformers/analytics/rollup_test.exs`:

```elixir
defmodule Gallformers.Analytics.RollupTest do
  use Gallformers.DataCase

  alias Gallformers.Analytics.PageView
  alias Gallformers.Analytics.Rollup
  alias Gallformers.Repo

  import Ecto.Query

  describe "rollup_day/1" do
    test "aggregates page_views into daily_stats" do
      yesterday = Date.add(Date.utc_today(), -1)

      insert_page_views(yesterday, [
        %{path: "/a", visitor_hash: "v1", referrer_host: nil, browser: "Chrome", device_type: "desktop"},
        %{path: "/b", visitor_hash: "v1", referrer_host: "google.com", browser: "Chrome", device_type: "desktop"},
        %{path: "/a", visitor_hash: "v2", referrer_host: nil, browser: "Firefox", device_type: "mobile"}
      ])

      assert :ok = Rollup.rollup_day(yesterday)

      # daily_stats
      [row] = Repo.all(from ds in "daily_stats", where: ds.date == ^yesterday,
                select: %{page_views: ds.page_views, unique_visitors: ds.unique_visitors})
      assert row.page_views == 3
      assert row.unique_visitors == 2

      # daily_page_stats
      page_stats = Repo.all(from dp in "daily_page_stats", where: dp.date == ^yesterday,
                     select: %{path: dp.path, page_views: dp.page_views, unique_visitors: dp.unique_visitors},
                     order_by: dp.path)
      assert length(page_stats) == 2
      assert Enum.find(page_stats, &(&1.path == "/a")).page_views == 2
      assert Enum.find(page_stats, &(&1.path == "/a")).unique_visitors == 2
      assert Enum.find(page_stats, &(&1.path == "/b")).page_views == 1

      # daily_referrer_stats
      ref_stats = Repo.all(from dr in "daily_referrer_stats", where: dr.date == ^yesterday,
                    select: %{referrer_host: dr.referrer_host, page_views: dr.page_views})
      assert length(ref_stats) == 2

      # daily_device_stats
      dev_stats = Repo.all(from dd in "daily_device_stats", where: dd.date == ^yesterday,
                    select: %{device_type: dd.device_type, count: dd.count})
      assert length(dev_stats) == 2

      # daily_browser_stats
      br_stats = Repo.all(from db in "daily_browser_stats", where: db.date == ^yesterday,
                   select: %{browser: db.browser, count: db.count})
      assert length(br_stats) == 2
    end

    test "is idempotent — re-running replaces existing data" do
      yesterday = Date.add(Date.utc_today(), -1)

      insert_page_views(yesterday, [
        %{path: "/x", visitor_hash: "v1", referrer_host: nil, browser: "Chrome", device_type: "desktop"}
      ])

      assert :ok = Rollup.rollup_day(yesterday)
      assert :ok = Rollup.rollup_day(yesterday)

      count = Repo.one(from ds in "daily_stats", where: ds.date == ^yesterday, select: count())
      assert count == 1
    end

    test "does nothing for a day with no data" do
      far_future = Date.add(Date.utc_today(), 1000)
      assert :ok = Rollup.rollup_day(far_future)

      count = Repo.one(from ds in "daily_stats", where: ds.date == ^far_future, select: count())
      assert count == 0
    end
  end

  describe "backfill_missing/0" do
    test "rolls up past days that have raw data but no summary" do
      two_days_ago = Date.add(Date.utc_today(), -2)

      insert_page_views(two_days_ago, [
        %{path: "/backfill", visitor_hash: "v1", referrer_host: nil, browser: "Chrome", device_type: "desktop"}
      ])

      assert :ok = Rollup.backfill_missing()

      count = Repo.one(from ds in "daily_stats", where: ds.date == ^two_days_ago, select: count())
      assert count == 1
    end
  end

  describe "prune_old_page_views/1" do
    test "deletes raw page_views older than retention days" do
      old_date = Date.add(Date.utc_today(), -100)

      insert_page_views(old_date, [
        %{path: "/old", visitor_hash: "v1", referrer_host: nil, browser: "Chrome", device_type: "desktop"}
      ])

      {deleted, _} = Rollup.prune_old_page_views(90)
      assert deleted >= 1

      remaining = Repo.one(from pv in PageView,
                    where: pv.inserted_at < ^NaiveDateTime.new!(Date.add(Date.utc_today(), -90), ~T[00:00:00]),
                    select: count())
      assert remaining == 0
    end
  end

  # Helper to insert page views for a specific date
  defp insert_page_views(date, entries) do
    for {entry, i} <- Enum.with_index(entries) do
      Repo.insert!(%PageView{
        path: entry.path,
        visitor_hash: entry.visitor_hash,
        referrer_host: entry.referrer_host,
        browser: entry.browser,
        device_type: entry.device_type,
        inserted_at: NaiveDateTime.new!(date, Time.new!(12, i, 0))
      })
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/gallformers/analytics/rollup_test.exs`
Expected: Compilation error — `Rollup` module doesn't exist.

**Step 3: Write the Rollup GenServer**

Create `lib/gallformers/analytics/rollup.ex`:

```elixir
defmodule Gallformers.Analytics.Rollup do
  @moduledoc """
  Nightly rollup of raw page_views into summary tables.

  On startup, backfills any un-rolled-up past days. Then schedules
  a daily job shortly after midnight UTC to roll up the previous day
  and prune raw data older than the retention window.
  """
  use GenServer

  import Ecto.Query

  require Logger

  alias Gallformers.Analytics.PageView
  alias Gallformers.Repo

  @retention_days 90
  # Run at 00:05 UTC daily
  @run_after_midnight_ms :timer.minutes(5)

  # ── Client API ──

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Roll up a single day's raw data into summary tables. Idempotent."
  @spec rollup_day(Date.t()) :: :ok
  def rollup_day(date) do
    {from_dt, to_dt} = date_bounds(date)

    base_query = from(pv in PageView, where: pv.inserted_at >= ^from_dt and pv.inserted_at < ^to_dt)

    # Check if there's any data for this day
    count = Repo.one(from pv in base_query, select: count())

    if count > 0 do
      rollup_daily_stats(date, base_query)
      rollup_daily_page_stats(date, base_query)
      rollup_daily_referrer_stats(date, base_query)
      rollup_daily_device_stats(date, base_query)
      rollup_daily_browser_stats(date, base_query)
    end

    :ok
  end

  @doc "Find past days with raw data but no summary and roll them up."
  @spec backfill_missing() :: :ok
  def backfill_missing do
    yesterday = Date.add(Date.utc_today(), -1)

    # Find distinct dates in page_views that don't have a daily_stats row
    dates_with_data =
      from(pv in PageView,
        where: pv.inserted_at < ^NaiveDateTime.new!(Date.utc_today(), ~T[00:00:00]),
        select: fragment("DISTINCT date(?)", pv.inserted_at)
      )
      |> Repo.all()
      |> Enum.map(fn date_str -> Date.from_iso8601!(date_str) end)
      |> Enum.filter(&(Date.compare(&1, yesterday) != :gt))

    existing_dates =
      from(ds in "daily_stats", select: ds.date)
      |> Repo.all()
      |> MapSet.new()

    missing = Enum.reject(dates_with_data, &(&1 in existing_dates))

    if missing != [] do
      Logger.info("Analytics rollup: backfilling #{length(missing)} day(s)")
    end

    Enum.each(missing, &rollup_day/1)
    :ok
  end

  @doc "Delete raw page_views older than `days` days. Returns {count, nil}."
  @spec prune_old_page_views(integer()) :: {integer(), nil}
  def prune_old_page_views(days \\ @retention_days) do
    cutoff = NaiveDateTime.new!(Date.add(Date.utc_today(), -days), ~T[00:00:00])

    from(pv in PageView, where: pv.inserted_at < ^cutoff)
    |> Repo.delete_all()
  end

  # ── GenServer Callbacks ──

  @impl true
  def init(_opts) do
    # Backfill on startup (async so we don't block app boot)
    Gallformers.Async.run(fn ->
      backfill_missing()
    end)

    schedule_next_run()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:run_rollup, state) do
    yesterday = Date.add(Date.utc_today(), -1)
    Logger.info("Analytics rollup: rolling up #{yesterday}")

    rollup_day(yesterday)

    {pruned, _} = prune_old_page_views()

    if pruned > 0 do
      Logger.info("Analytics rollup: pruned #{pruned} old page views")
    end

    schedule_next_run()
    {:noreply, state}
  end

  # ── Private ──

  defp schedule_next_run do
    ms_until_midnight = ms_until_next_midnight()
    Process.send_after(self(), :run_rollup, ms_until_midnight + @run_after_midnight_ms)
  end

  defp ms_until_next_midnight do
    now = NaiveDateTime.utc_now()
    tomorrow = NaiveDateTime.new!(Date.add(Date.utc_today(), 1), ~T[00:00:00])
    NaiveDateTime.diff(tomorrow, now, :millisecond) |> max(0)
  end

  defp date_bounds(date) do
    {NaiveDateTime.new!(date, ~T[00:00:00]),
     NaiveDateTime.new!(Date.add(date, 1), ~T[00:00:00])}
  end

  defp rollup_daily_stats(date, base_query) do
    %{page_views: pv, unique_visitors: uv} =
      from(pv in base_query,
        select: %{
          page_views: count(pv.id),
          unique_visitors: count(pv.visitor_hash, :distinct)
        }
      )
      |> Repo.one()

    Repo.query!(
      "INSERT OR REPLACE INTO daily_stats (date, page_views, unique_visitors) VALUES (?1, ?2, ?3)",
      [date, pv, uv]
    )
  end

  defp rollup_daily_page_stats(date, base_query) do
    # Delete existing rows for this date first, then insert fresh
    Repo.query!("DELETE FROM daily_page_stats WHERE date = ?1", [date])

    from(pv in base_query,
      group_by: pv.path,
      select: %{
        path: pv.path,
        page_views: count(pv.id),
        unique_visitors: count(pv.visitor_hash, :distinct)
      }
    )
    |> Repo.all()
    |> Enum.each(fn row ->
      Repo.query!(
        "INSERT INTO daily_page_stats (date, path, page_views, unique_visitors) VALUES (?1, ?2, ?3, ?4)",
        [date, row.path, row.page_views, row.unique_visitors]
      )
    end)
  end

  defp rollup_daily_referrer_stats(date, base_query) do
    Repo.query!("DELETE FROM daily_referrer_stats WHERE date = ?1", [date])

    from(pv in base_query,
      group_by: pv.referrer_host,
      select: %{referrer_host: pv.referrer_host, page_views: count(pv.id)}
    )
    |> Repo.all()
    |> Enum.each(fn row ->
      Repo.query!(
        "INSERT INTO daily_referrer_stats (date, referrer_host, page_views) VALUES (?1, ?2, ?3)",
        [date, row.referrer_host, row.page_views]
      )
    end)
  end

  defp rollup_daily_device_stats(date, base_query) do
    Repo.query!("DELETE FROM daily_device_stats WHERE date = ?1", [date])

    from(pv in base_query,
      group_by: pv.device_type,
      select: %{device_type: pv.device_type, count: count(pv.id)}
    )
    |> Repo.all()
    |> Enum.each(fn row ->
      Repo.query!(
        "INSERT INTO daily_device_stats (date, device_type, count) VALUES (?1, ?2, ?3)",
        [date, row.device_type, row.count]
      )
    end)
  end

  defp rollup_daily_browser_stats(date, base_query) do
    Repo.query!("DELETE FROM daily_browser_stats WHERE date = ?1", [date])

    from(pv in base_query,
      group_by: pv.browser,
      select: %{browser: pv.browser, count: count(pv.id)}
    )
    |> Repo.all()
    |> Enum.each(fn row ->
      Repo.query!(
        "INSERT INTO daily_browser_stats (date, browser, count) VALUES (?1, ?2, ?3)",
        [date, row.browser, row.count]
      )
    end)
  end
end
```

**Step 4: Run tests**

Run: `mix test test/gallformers/analytics/rollup_test.exs`
Expected: All pass.

**Step 5: Add to supervision tree**

In `lib/gallformers/application.ex`, add `Gallformers.Analytics.Rollup` to the children list, before the Endpoint:

```elixir
# Analytics rollup (nightly summary aggregation)
Gallformers.Analytics.Rollup,
```

**Step 6: Commit**

```
git add lib/gallformers/analytics/rollup.ex test/gallformers/analytics/rollup_test.exs lib/gallformers/application.ex
git commit -m "Add analytics rollup GenServer with backfill, prune, and nightly schedule"
```

---

### Task 3: Rewrite query functions to read from summaries

**Files:**
- Modify: `lib/gallformers/analytics.ex:153-326` (query functions section)
- Test: `test/gallformers/analytics_test.exs` (existing tests should still pass)

**Step 1: Write tests for summary-backed queries**

Add to `test/gallformers/analytics_test.exs`, a new describe block:

```elixir
describe "summary-backed queries" do
  alias Gallformers.Analytics.Rollup

  setup do
    yesterday = Date.add(Date.utc_today(), -1)
    two_days_ago = Date.add(Date.utc_today(), -2)

    # Insert raw data for past days and roll them up
    for {date, entries} <- [
      {two_days_ago, [
        %{path: "/species/1", visitor_hash: "v1", referrer_host: "google.com", browser: "Chrome", device_type: "desktop"},
        %{path: "/species/1", visitor_hash: "v2", referrer_host: nil, browser: "Firefox", device_type: "mobile"},
        %{path: "/gall/1", visitor_hash: "v1", referrer_host: "google.com", browser: "Chrome", device_type: "desktop"}
      ]},
      {yesterday, [
        %{path: "/species/1", visitor_hash: "v3", referrer_host: "reddit.com", browser: "Safari", device_type: "desktop"},
        %{path: "/host/1", visitor_hash: "v3", referrer_host: "reddit.com", browser: "Safari", device_type: "desktop"}
      ]}
    ] do
      for {entry, i} <- Enum.with_index(entries) do
        Repo.insert!(%PageView{
          path: entry.path,
          visitor_hash: entry.visitor_hash,
          referrer_host: entry.referrer_host,
          browser: entry.browser,
          device_type: entry.device_type,
          inserted_at: NaiveDateTime.new!(date, Time.new!(12, i, 0))
        })
      end

      Rollup.rollup_day(date)
    end

    # Insert today's raw data (not rolled up)
    Repo.insert!(%PageView{
      path: "/species/1",
      visitor_hash: "v4",
      referrer_host: nil,
      browser: "Chrome",
      device_type: "desktop",
      inserted_at: NaiveDateTime.new!(Date.utc_today(), ~T[10:00:00])
    })

    %{yesterday: yesterday, two_days_ago: two_days_ago}
  end

  test "daily_stats combines summaries with today's raw data", ctx do
    daily = Analytics.daily_stats(ctx.two_days_ago, Date.utc_today())

    assert length(daily) == 3

    day1 = Enum.find(daily, &(&1.date == ctx.two_days_ago))
    assert day1.page_views == 3
    assert day1.unique_visitors == 2

    today = Enum.find(daily, &(&1.date == Date.utc_today()))
    assert today.page_views >= 1
  end

  test "top_pages combines summaries with today's raw data", ctx do
    pages = Analytics.top_pages(ctx.two_days_ago, Date.utc_today())

    species_1 = Enum.find(pages, &(&1.path == "/species/1"))
    assert species_1.views >= 4
  end

  test "top_referrers combines summaries with today's raw data", ctx do
    referrers = Analytics.top_referrers(ctx.two_days_ago, Date.utc_today())
    labels = Enum.map(referrers, & &1.referrer)

    assert "google.com" in labels
    assert "reddit.com" in labels
    assert "Direct" in labels
  end

  test "device_breakdown combines summaries with today's raw data", ctx do
    devices = Analytics.device_breakdown(ctx.two_days_ago, Date.utc_today())

    desktop = Enum.find(devices, &(&1.device_type == "desktop"))
    assert desktop.count >= 4
  end

  test "browser_breakdown combines summaries with today's raw data", ctx do
    browsers = Analytics.browser_breakdown(ctx.two_days_ago, Date.utc_today())

    chrome = Enum.find(browsers, &(&1.browser == "Chrome"))
    assert chrome.count >= 3
  end

  test "single-day query still uses raw data" do
    today = Date.utc_today()
    stats = Analytics.stats(today, today)

    # Should find today's raw data
    assert stats.page_views >= 1
  end
end
```

**Step 2: Run test to see baseline**

Run: `mix test test/gallformers/analytics_test.exs`
Expected: Existing tests pass, new tests may fail (queries still use raw data so some might pass).

**Step 3: Rewrite the query functions**

Replace the query functions section in `lib/gallformers/analytics.ex` (lines 153-326). The key change: multi-day queries read from summary tables for past days, raw `page_views` for today only, then combine.

The `stats/2` function stays mostly the same for single-day (it already reads raw). For multi-day, aggregate from `daily_stats`.

The `daily_stats/2` function reads from `daily_stats` table for past days, queries raw for today, fills zeros.

`top_pages/2` reads `daily_page_stats` for past days + raw for today, sums, sorts, limits.

`top_referrers/2` reads `daily_referrer_stats` for past days + raw for today, sums, sorts.

`device_breakdown/2` reads `daily_device_stats` + raw for today, sums, sorts.

`browser_breakdown/2` reads `daily_browser_stats` + raw for today, sums, sorts.

Key implementation pattern for each function:

```elixir
defp split_range(from_date, to_date) do
  today = Date.utc_today()
  includes_today = Date.compare(to_date, today) != :lt and Date.compare(from_date, today) != :gt
  summary_end = Date.add(today, -1)

  cond do
    # Single day = today → raw only
    from_date == to_date and from_date == today ->
      {:raw_only, from_date, to_date}

    # Range doesn't include today → summaries only
    not includes_today ->
      {:summary_only, from_date, to_date}

    # Range includes today → summaries for past days + raw for today
    true ->
      {:mixed, from_date, summary_end, today}
  end
end
```

Each query function calls `split_range/2` and dispatches accordingly. For `:mixed`, it runs two queries and merges results in Elixir.

**Step 4: Run all analytics tests**

Run: `mix test test/gallformers/analytics_test.exs`
Expected: All tests pass (old and new).

**Step 5: Commit**

```
git add lib/gallformers/analytics.ex test/gallformers/analytics_test.exs
git commit -m "Rewrite analytics queries to read from summary tables for multi-day ranges"
```

---

### Task 4: Verify LiveView still works end-to-end

**Files:**
- Test: `test/gallformers_web/live/analytics_live_test.exs` (if exists, else create)

**Step 1: Check for existing LiveView tests**

Run: `find test -name "*analytics*live*" -o -name "*analytics*test*" | head`

If no LiveView test exists, write a basic smoke test:

```elixir
defmodule GallformersWeb.AnalyticsLiveTest do
  use GallformersWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "analytics page" do
    test "renders with default 'today' range", %{conn: conn} do
      {:ok, view, html} = live(conn, "/analytics")

      assert html =~ "Site Analytics"
      assert html =~ "Today"
    end

    test "switches to 7-day range", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/analytics")

      html = render_click(view, "change_range", %{"range" => "7d"})
      assert html =~ "Daily Breakdown"
    end

    test "switches to 30-day range without timeout", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/analytics")

      html = render_click(view, "change_range", %{"range" => "30d"})
      assert html =~ "Daily Breakdown"
    end
  end
end
```

**Step 2: Run the LiveView test**

Run: `mix test test/gallformers_web/live/analytics_live_test.exs`
Expected: All pass.

**Step 3: Commit**

```
git add test/gallformers_web/live/analytics_live_test.exs
git commit -m "Add analytics LiveView smoke tests"
```

---

### Task 5: Run full test suite and verify

**Step 1: Run precommit**

Run: `mix precommit`
Expected: All checks pass (format, credo, tests).

**Step 2: Manual verification (optional)**

Start dev server: `mix phx.server`
- Visit `/analytics` → "Today" view should work (raw query)
- Click "7 days" → should work (summaries + today)
- Click "30 days" → should be fast now
- Click "90 days" → should be fast now

**Step 3: Final commit if any fixups needed**

If precommit required formatting or credo fixes, commit those.
