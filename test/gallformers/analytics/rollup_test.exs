defmodule Gallformers.Analytics.RollupTest do
  @moduledoc """
  Tests for the Analytics Rollup GenServer.

  Verifies daily aggregation into summary tables, idempotency,
  backfill of missing days, and pruning of old raw data.
  """
  use Gallformers.DataCase

  alias Gallformers.Analytics.PageView
  alias Gallformers.Analytics.Rollup

  @today ~D[2026-01-15]
  @yesterday ~D[2026-01-14]

  describe "rollup_day/1" do
    test "aggregates page views into all 5 summary tables" do
      insert_page_views(@today, [
        %{
          path: "/",
          visitor_hash: "aaa",
          referrer_host: nil,
          browser: "Chrome",
          device_type: "desktop"
        },
        %{
          path: "/",
          visitor_hash: "bbb",
          referrer_host: "google.com",
          browser: "Chrome",
          device_type: "mobile"
        },
        %{
          path: "/gall/1",
          visitor_hash: "aaa",
          referrer_host: "google.com",
          browser: "Firefox",
          device_type: "desktop"
        }
      ])

      assert :ok = Rollup.rollup_day(@today)

      # daily_stats: 3 page views, 2 unique visitors
      assert %{rows: [[3, 2]]} =
               Repo.query!("SELECT page_views, unique_visitors FROM daily_stats WHERE date = ?", [
                 Date.to_iso8601(@today)
               ])

      # daily_page_stats: "/" = 2 views/2 unique, "/gall/1" = 1 view/1 unique
      %{rows: page_rows} =
        Repo.query!(
          "SELECT path, page_views, unique_visitors FROM daily_page_stats WHERE date = ? ORDER BY page_views DESC",
          [Date.to_iso8601(@today)]
        )

      assert ["/", 2, 2] in page_rows
      assert ["/gall/1", 1, 1] in page_rows

      # daily_referrer_stats: nil = 1, "google.com" = 2
      %{rows: ref_rows} =
        Repo.query!(
          "SELECT referrer_host, page_views FROM daily_referrer_stats WHERE date = ? ORDER BY page_views DESC",
          [Date.to_iso8601(@today)]
        )

      assert [nil, 1] in ref_rows or ["", 1] in ref_rows
      assert ["google.com", 2] in ref_rows

      # daily_device_stats: desktop = 2, mobile = 1
      %{rows: device_rows} =
        Repo.query!(
          "SELECT device_type, count FROM daily_device_stats WHERE date = ? ORDER BY count DESC",
          [Date.to_iso8601(@today)]
        )

      assert ["desktop", 2] in device_rows
      assert ["mobile", 1] in device_rows

      # daily_browser_stats: Chrome = 2, Firefox = 1
      %{rows: browser_rows} =
        Repo.query!(
          "SELECT browser, count FROM daily_browser_stats WHERE date = ? ORDER BY count DESC",
          [Date.to_iso8601(@today)]
        )

      assert ["Chrome", 2] in browser_rows
      assert ["Firefox", 1] in browser_rows
    end

    test "is idempotent — running twice does not duplicate data" do
      insert_page_views(@today, [
        %{
          path: "/",
          visitor_hash: "aaa",
          referrer_host: nil,
          browser: "Chrome",
          device_type: "desktop"
        }
      ])

      assert :ok = Rollup.rollup_day(@today)
      assert :ok = Rollup.rollup_day(@today)

      assert %{rows: [[1, 1]]} =
               Repo.query!("SELECT page_views, unique_visitors FROM daily_stats WHERE date = ?", [
                 Date.to_iso8601(@today)
               ])

      assert %{num_rows: 1} =
               Repo.query!("SELECT * FROM daily_page_stats WHERE date = ?", [
                 Date.to_iso8601(@today)
               ])

      assert %{num_rows: 1} =
               Repo.query!("SELECT * FROM daily_referrer_stats WHERE date = ?", [
                 Date.to_iso8601(@today)
               ])

      assert %{num_rows: 1} =
               Repo.query!("SELECT * FROM daily_device_stats WHERE date = ?", [
                 Date.to_iso8601(@today)
               ])

      assert %{num_rows: 1} =
               Repo.query!("SELECT * FROM daily_browser_stats WHERE date = ?", [
                 Date.to_iso8601(@today)
               ])
    end

    test "does nothing for a day with no data" do
      assert :noop = Rollup.rollup_day(@today)

      assert %{num_rows: 0} =
               Repo.query!("SELECT * FROM daily_stats WHERE date = ?", [Date.to_iso8601(@today)])
    end
  end

  describe "backfill_missing/0" do
    test "rolls up past days that have raw data but no summary" do
      # Insert data for two days
      insert_page_views(@yesterday, [
        %{
          path: "/",
          visitor_hash: "aaa",
          referrer_host: nil,
          browser: "Chrome",
          device_type: "desktop"
        }
      ])

      insert_page_views(@today, [
        %{
          path: "/gall/1",
          visitor_hash: "bbb",
          referrer_host: "bing.com",
          browser: "Firefox",
          device_type: "mobile"
        }
      ])

      # Manually roll up today only — yesterday should be "missing"
      Rollup.rollup_day(@today)

      # Now backfill should pick up yesterday
      assert :ok = Rollup.backfill_missing()

      assert %{rows: [[1, 1]]} =
               Repo.query!("SELECT page_views, unique_visitors FROM daily_stats WHERE date = ?", [
                 Date.to_iso8601(@yesterday)
               ])
    end
  end

  describe "prune_old_page_views/1" do
    test "deletes raw page views older than N days" do
      old_date = Date.add(Date.utc_today(), -100)
      recent_date = Date.add(Date.utc_today(), -10)

      insert_page_views(old_date, [
        %{
          path: "/old",
          visitor_hash: "aaa",
          referrer_host: nil,
          browser: "Chrome",
          device_type: "desktop"
        }
      ])

      insert_page_views(recent_date, [
        %{
          path: "/recent",
          visitor_hash: "bbb",
          referrer_host: nil,
          browser: "Firefox",
          device_type: "mobile"
        }
      ])

      assert {1, nil} = Rollup.prune_old_page_views(90)

      # Old data is gone
      assert Repo.all(from pv in PageView, where: pv.path == "/old") == []
      # Recent data remains
      assert [%PageView{path: "/recent"}] =
               Repo.all(from pv in PageView, where: pv.path == "/recent")
    end
  end

  # -- Helpers --

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
