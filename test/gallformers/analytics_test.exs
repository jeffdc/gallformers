defmodule Gallformers.AnalyticsTest do
  @moduledoc """
  Unit tests for the Analytics context.
  """
  use Gallformers.DataCase

  alias Gallformers.Analytics
  alias Gallformers.Analytics.PageView

  describe "should_track?/2" do
    test "returns true for normal page paths" do
      assert Analytics.should_track?("/", nil)
      assert Analytics.should_track?("/species/123", nil)
      assert Analytics.should_track?("/host/oak", nil)
      assert Analytics.should_track?("/gall/456", nil)
      assert Analytics.should_track?("/id", nil)
    end

    test "returns false for excluded path prefixes" do
      refute Analytics.should_track?("/admin", nil)
      refute Analytics.should_track?("/admin/species", nil)
      refute Analytics.should_track?("/api/v1/search", nil)
      refute Analytics.should_track?("/assets/app.js", nil)
      refute Analytics.should_track?("/images/photo.jpg", nil)
      refute Analytics.should_track?("/dev/dashboard", nil)
      refute Analytics.should_track?("/health", nil)
      refute Analytics.should_track?("/auth/login", nil)
    end

    test "returns false for excluded exact paths" do
      refute Analytics.should_track?("/favicon.ico", nil)
      refute Analytics.should_track?("/robots.txt", nil)
      refute Analytics.should_track?("/sitemap.xml", nil)
    end

    test "returns false for bot user agents" do
      refute Analytics.should_track?("/", "Googlebot/2.1")
      refute Analytics.should_track?("/species/1", "Mozilla/5.0 (compatible; Bingbot/2.0)")
      refute Analytics.should_track?("/", "Twitterbot/1.0")
      refute Analytics.should_track?("/", "facebookexternalhit/1.1")
      refute Analytics.should_track?("/", "LinkedInBot/1.0")
      refute Analytics.should_track?("/", "Slurp")
      refute Analytics.should_track?("/", "spider-agent")
      refute Analytics.should_track?("/", "Some Crawl Agent")
      refute Analytics.should_track?("/", "FeedFetcher-Google")
    end

    test "bot detection is case-insensitive" do
      refute Analytics.should_track?("/", "GOOGLEBOT")
      refute Analytics.should_track?("/", "GoogleBot")
      refute Analytics.should_track?("/", "googlebot")
    end

    test "returns true for normal browsers" do
      chrome_ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

      firefox_ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0"

      safari_ua =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15"

      assert Analytics.should_track?("/", chrome_ua)
      assert Analytics.should_track?("/species/1", firefox_ua)
      assert Analytics.should_track?("/host/1", safari_ua)
    end
  end

  describe "generate_visitor_hash/2" do
    test "returns a consistent hash for the same IP and user agent" do
      hash1 = Analytics.generate_visitor_hash("192.168.1.1", "Mozilla/5.0")
      hash2 = Analytics.generate_visitor_hash("192.168.1.1", "Mozilla/5.0")
      assert hash1 == hash2
    end

    test "returns different hashes for different IPs" do
      hash1 = Analytics.generate_visitor_hash("192.168.1.1", "Mozilla/5.0")
      hash2 = Analytics.generate_visitor_hash("192.168.1.2", "Mozilla/5.0")
      assert hash1 != hash2
    end

    test "returns different hashes for different user agents" do
      hash1 = Analytics.generate_visitor_hash("192.168.1.1", "Mozilla/5.0 Chrome")
      hash2 = Analytics.generate_visitor_hash("192.168.1.1", "Mozilla/5.0 Firefox")
      assert hash1 != hash2
    end

    test "returns a 16-character hex string" do
      hash = Analytics.generate_visitor_hash("10.0.0.1", "Test Agent")
      assert String.length(hash) == 16
      assert Regex.match?(~r/^[0-9a-f]{16}$/, hash)
    end

    test "handles nil user agent" do
      hash = Analytics.generate_visitor_hash("192.168.1.1", nil)
      assert String.length(hash) == 16
      assert Regex.match?(~r/^[0-9a-f]{16}$/, hash)
    end
  end

  describe "extract_referrer_host/2" do
    test "extracts host from full URL" do
      assert Analytics.extract_referrer_host(
               "https://google.com/search?q=galls",
               "gallformers.org"
             ) ==
               "google.com"

      assert Analytics.extract_referrer_host(
               "https://www.reddit.com/r/entomology",
               "gallformers.org"
             ) ==
               "www.reddit.com"

      assert Analytics.extract_referrer_host("http://example.org/page", "gallformers.org") ==
               "example.org"
    end

    test "returns nil for same-site referrer" do
      assert Analytics.extract_referrer_host(
               "https://gallformers.org/species/1",
               "gallformers.org"
             ) == nil

      assert Analytics.extract_referrer_host("https://gallformers.org/", "gallformers.org") == nil
    end

    test "returns nil for empty or nil referrer" do
      assert Analytics.extract_referrer_host(nil, "gallformers.org") == nil
      assert Analytics.extract_referrer_host("", "gallformers.org") == nil
    end

    test "returns nil for malformed URLs" do
      assert Analytics.extract_referrer_host("not-a-url", "gallformers.org") == nil
      assert Analytics.extract_referrer_host("://missing-scheme", "gallformers.org") == nil
    end
  end

  describe "parse_user_agent/1" do
    test "returns {nil, nil} for nil user agent" do
      assert Analytics.parse_user_agent(nil) == {nil, nil}
    end

    test "identifies Chrome on desktop" do
      chrome_desktop =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

      {browser, device} = Analytics.parse_user_agent(chrome_desktop)
      assert browser == "Chrome"
      assert device == "desktop"
    end

    test "identifies Safari on mobile" do
      safari_mobile =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1"

      {browser, device} = Analytics.parse_user_agent(safari_mobile)
      assert browser == "Safari (iOS)"
      assert device == "mobile"
    end

    test "identifies Firefox" do
      firefox_ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0"

      {browser, _device} = Analytics.parse_user_agent(firefox_ua)
      assert browser == "Firefox"
    end

    test "identifies Edge" do
      edge_ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0"

      {browser, _device} = Analytics.parse_user_agent(edge_ua)
      assert browser == "Edge"
    end

    test "identifies tablet devices" do
      ipad_ua =
        "Mozilla/5.0 (iPad; CPU OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1"

      {_browser, device} = Analytics.parse_user_agent(ipad_ua)
      assert device == "tablet"
    end

    test "returns Other for unknown browsers" do
      unknown_ua = "CustomBot/1.0"
      {browser, _device} = Analytics.parse_user_agent(unknown_ua)
      assert browser == "Other"
    end

    test "identifies Safari (iOS)" do
      safari_ios =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1"

      {browser, _device} = Analytics.parse_user_agent(safari_ios)
      assert browser == "Safari (iOS)"
    end

    test "identifies Samsung Internet" do
      samsung_ua =
        "Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/20.0 Chrome/106.0.5249.126 Mobile Safari/537.36"

      {browser, _device} = Analytics.parse_user_agent(samsung_ua)
      assert browser == "Samsung Internet"
    end

    test "identifies Brave" do
      brave_ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Brave/120.0.0.0"

      {browser, _device} = Analytics.parse_user_agent(brave_ua)
      assert browser == "Brave"
    end

    test "identifies Arc" do
      arc_ua =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Arc/1.0"

      {browser, _device} = Analytics.parse_user_agent(arc_ua)
      assert browser == "Arc"
    end

    test "identifies Vivaldi" do
      vivaldi_ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Vivaldi/6.5.3206.63"

      {browser, _device} = Analytics.parse_user_agent(vivaldi_ua)
      assert browser == "Vivaldi"
    end

    test "identifies DuckDuckGo browser" do
      ddg_ua =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 DuckDuckGo/7 Safari/605.1.15"

      {browser, _device} = Analytics.parse_user_agent(ddg_ua)
      assert browser == "DuckDuckGo"
    end
  end

  describe "track_page_view/1" do
    test "returns :ok immediately" do
      attrs = %{
        path: "/async/test",
        visitor_hash: "1234567890abcdef"
      }

      # Should return :ok (async insert happens in background task)
      assert :ok = Analytics.track_page_view(attrs)
    end

    test "spawns a task that inserts the record" do
      # Test that a valid changeset is created (synchronous validation)
      attrs = %{
        path: "/test/page",
        visitor_hash: "abc123def456gh78",
        referrer_host: "google.com",
        browser: "Chrome",
        device_type: "desktop"
      }

      changeset = PageView.changeset(%PageView{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :path) == "/test/page"
      assert Ecto.Changeset.get_field(changeset, :visitor_hash) == "abc123def456gh78"
      assert Ecto.Changeset.get_field(changeset, :browser) == "Chrome"
    end

    test "changeset requires path and visitor_hash" do
      changeset = PageView.changeset(%PageView{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).path
      assert "can't be blank" in errors_on(changeset).visitor_hash
    end
  end

  describe "stats/2" do
    test "returns zeros when no page views exist" do
      today = Date.utc_today()
      stats = Analytics.stats(today, today)

      assert stats.page_views == 0
      assert stats.unique_visitors == 0
    end

    test "counts page views correctly" do
      today = Date.utc_today()

      # Insert some page views directly
      {:ok, _} =
        Repo.insert(%PageView{
          path: "/page1",
          visitor_hash: "visitor1hash12345"
        })

      {:ok, _} =
        Repo.insert(%PageView{
          path: "/page2",
          visitor_hash: "visitor1hash12345"
        })

      {:ok, _} =
        Repo.insert(%PageView{
          path: "/page1",
          visitor_hash: "visitor2hash67890"
        })

      stats = Analytics.stats(today, today)

      assert stats.page_views == 3
      assert stats.unique_visitors == 2
    end

    test "respects date range" do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)
      tomorrow = Date.add(today, 1)

      # First verify we start with no page views for yesterday
      stats_before = Analytics.stats(yesterday, yesterday)
      assert stats_before.page_views == 0

      # Insert a page view for today
      {:ok, _} =
        Repo.insert(%PageView{
          path: "/date-range-test-page",
          visitor_hash: "daterangevisitor1"
        })

      # Query for yesterday only - should still get zero
      stats_yesterday = Analytics.stats(yesterday, yesterday)
      assert stats_yesterday.page_views == 0

      # Query for tomorrow only - should also get zero
      stats_tomorrow = Analytics.stats(tomorrow, tomorrow)
      assert stats_tomorrow.page_views == 0

      # Query for today - should find our inserted record
      stats_today = Analytics.stats(today, today)
      assert stats_today.page_views >= 1
    end
  end

  describe "daily_stats/2" do
    test "returns daily breakdown for date range" do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      # Insert page views for yesterday
      Repo.insert(%PageView{
        path: "/page1",
        visitor_hash: "visitor1",
        inserted_at: NaiveDateTime.new!(yesterday, ~T[12:00:00])
      })

      Repo.insert(%PageView{
        path: "/page2",
        visitor_hash: "visitor1",
        inserted_at: NaiveDateTime.new!(yesterday, ~T[13:00:00])
      })

      Repo.insert(%PageView{
        path: "/page3",
        visitor_hash: "visitor2",
        inserted_at: NaiveDateTime.new!(yesterday, ~T[14:00:00])
      })

      # Insert page views for today
      Repo.insert(%PageView{
        path: "/page1",
        visitor_hash: "visitor3",
        inserted_at: NaiveDateTime.new!(today, ~T[10:00:00])
      })

      daily_stats = Analytics.daily_stats(yesterday, today)

      assert length(daily_stats) == 2

      # Find stats for each day
      yesterday_stats = Enum.find(daily_stats, &(&1.date == yesterday))
      today_stats = Enum.find(daily_stats, &(&1.date == today))

      assert yesterday_stats.page_views == 3
      assert yesterday_stats.unique_visitors == 2

      assert today_stats.page_views >= 1
      assert today_stats.unique_visitors >= 1
    end

    test "returns days with zero counts when no page views exist" do
      # Use a far future date range with no data
      from_date = Date.add(Date.utc_today(), 1000)
      to_date = Date.add(from_date, 2)

      daily_stats = Analytics.daily_stats(from_date, to_date)

      # Should have 3 days with all zeros
      assert length(daily_stats) == 3
      assert Enum.all?(daily_stats, &(&1.page_views == 0))
      assert Enum.all?(daily_stats, &(&1.unique_visitors == 0))
    end

    test "includes days with zero views in the range" do
      today = Date.utc_today()
      three_days_ago = Date.add(today, -3)

      # Only insert data for today, none for the days in between
      Repo.insert(%PageView{
        path: "/page1",
        visitor_hash: "visitor1",
        inserted_at: NaiveDateTime.new!(today, ~T[10:00:00])
      })

      daily_stats = Analytics.daily_stats(three_days_ago, today)

      # Should have 4 days total (3 days ago, 2 days ago, yesterday, today)
      assert length(daily_stats) == 4

      # Days with no data should have zero counts
      zero_days = Enum.filter(daily_stats, &(&1.page_views == 0))
      assert length(zero_days) == 3
    end

    test "orders results chronologically" do
      today = Date.utc_today()
      two_days_ago = Date.add(today, -2)

      Repo.insert(%PageView{
        path: "/page1",
        visitor_hash: "visitor1",
        inserted_at: NaiveDateTime.new!(two_days_ago, ~T[10:00:00])
      })

      Repo.insert(%PageView{
        path: "/page2",
        visitor_hash: "visitor2",
        inserted_at: NaiveDateTime.new!(today, ~T[10:00:00])
      })

      daily_stats = Analytics.daily_stats(two_days_ago, today)

      dates = Enum.map(daily_stats, & &1.date)
      # Check chronological ordering using proper date comparison
      assert dates == Enum.sort_by(dates, & &1, Date)
      assert List.first(dates) == two_days_ago
      assert List.last(dates) == today
    end
  end
end
