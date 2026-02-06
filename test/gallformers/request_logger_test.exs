defmodule Gallformers.RequestLoggerTest do
  use ExUnit.Case, async: true

  alias Gallformers.RequestLogger

  @moduletag :unit

  setup do
    # Use a temp directory for testing
    tmp_dir = Path.join(System.tmp_dir!(), "request_logger_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    # Configure the test to use this directory and be enabled
    Application.put_env(:gallformers, :request_log_dir, tmp_dir)
    Application.put_env(:gallformers, :request_logger_enabled, true)

    on_exit(fn ->
      # Cleanup
      File.rm_rf!(tmp_dir)
      Application.delete_env(:gallformers, :request_log_dir)
      Application.put_env(:gallformers, :request_logger_enabled, false)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "handle_event/4" do
    test "writes JSON line to log file", %{tmp_dir: tmp_dir} do
      conn = %Plug.Conn{
        method: "GET",
        request_path: "/species/123",
        query_string: "tab=hosts",
        status: 200,
        remote_ip: {127, 0, 0, 1},
        req_headers: [
          {"user-agent", "Mozilla/5.0 Test Browser"},
          {"fly-client-ip", "73.162.41.92"}
        ]
      }

      measurements = %{duration: 45_000_000}
      metadata = %{conn: conn}

      RequestLogger.handle_event([:phoenix, :endpoint, :stop], measurements, metadata, nil)

      # Find the log file
      [log_file] = File.ls!(tmp_dir)
      assert String.starts_with?(log_file, "requests-")
      assert String.ends_with?(log_file, ".log")

      # Read and parse the log entry
      content = File.read!(Path.join(tmp_dir, log_file))
      entry = Jason.decode!(String.trim(content))

      assert entry["method"] == "GET"
      assert entry["path"] == "/species/123"
      assert entry["query"] == "tab=hosts"
      assert entry["status"] == 200
      assert entry["duration_ms"] == 45
      assert entry["ip"] == "73.162.41.92"
      assert entry["ua"] == "Mozilla/5.0 Test Browser"
      assert entry["ts"] =~ ~r/^\d{4}-\d{2}-\d{2}T/
    end

    test "omits query when empty", %{tmp_dir: tmp_dir} do
      conn = %Plug.Conn{
        method: "GET",
        request_path: "/",
        query_string: "",
        status: 200,
        remote_ip: {127, 0, 0, 1},
        req_headers: []
      }

      RequestLogger.handle_event(
        [:phoenix, :endpoint, :stop],
        %{duration: 10_000_000},
        %{conn: conn},
        nil
      )

      [log_file] = File.ls!(tmp_dir)
      content = File.read!(Path.join(tmp_dir, log_file))
      entry = Jason.decode!(String.trim(content))

      refute Map.has_key?(entry, "query")
    end

    test "truncates long user agents", %{tmp_dir: tmp_dir} do
      long_ua = String.duplicate("x", 300)

      conn = %Plug.Conn{
        method: "GET",
        request_path: "/",
        query_string: "",
        status: 200,
        remote_ip: {127, 0, 0, 1},
        req_headers: [{"user-agent", long_ua}]
      }

      RequestLogger.handle_event(
        [:phoenix, :endpoint, :stop],
        %{duration: 10_000_000},
        %{conn: conn},
        nil
      )

      [log_file] = File.ls!(tmp_dir)
      content = File.read!(Path.join(tmp_dir, log_file))
      entry = Jason.decode!(String.trim(content))

      # 200 chars + "..."
      assert String.length(entry["ua"]) == 203
      assert String.ends_with?(entry["ua"], "...")
    end

    test "falls back to x-forwarded-for when fly-client-ip missing", %{tmp_dir: tmp_dir} do
      conn = %Plug.Conn{
        method: "GET",
        request_path: "/",
        query_string: "",
        status: 200,
        remote_ip: {127, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "1.2.3.4, 5.6.7.8"}]
      }

      RequestLogger.handle_event(
        [:phoenix, :endpoint, :stop],
        %{duration: 10_000_000},
        %{conn: conn},
        nil
      )

      [log_file] = File.ls!(tmp_dir)
      content = File.read!(Path.join(tmp_dir, log_file))
      entry = Jason.decode!(String.trim(content))

      assert entry["ip"] == "1.2.3.4"
    end
  end

  describe "cleanup_old_logs/0" do
    test "deletes files older than 30 days", %{tmp_dir: tmp_dir} do
      # Create some log files with different dates
      old_date = Date.utc_today() |> Date.add(-35) |> Date.to_iso8601()
      recent_date = Date.utc_today() |> Date.add(-5) |> Date.to_iso8601()
      today_date = Date.utc_today() |> Date.to_iso8601()

      File.write!(Path.join(tmp_dir, "requests-#{old_date}.log"), "old")
      File.write!(Path.join(tmp_dir, "requests-#{recent_date}.log"), "recent")
      File.write!(Path.join(tmp_dir, "requests-#{today_date}.log"), "today")
      # Non-log file should be ignored
      File.write!(Path.join(tmp_dir, "other.txt"), "ignored")

      RequestLogger.cleanup_old_logs()

      files = File.ls!(tmp_dir) |> Enum.sort()
      assert files == ["other.txt", "requests-#{recent_date}.log", "requests-#{today_date}.log"]
    end
  end
end
