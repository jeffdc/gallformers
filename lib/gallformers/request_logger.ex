defmodule Gallformers.RequestLogger do
  @moduledoc """
  Logs HTTP requests to daily JSON Lines files for incident investigation.

  Attaches to Phoenix telemetry events and writes request data to
  `/data/logs/requests-YYYY-MM-DD.log` (configurable via :request_log_dir).

  Each line is a JSON object with: ts, method, path, query, status, duration_ms, ip, ua

  Log files older than 30 days are automatically deleted on startup and daily.
  """

  require Logger

  @retention_days 30
  @cleanup_interval_ms :timer.hours(24)
  @ua_max_length 200

  # --- Public API ---

  @doc """
  Attaches the telemetry handler. Call from Application.start/2.
  """
  def attach do
    if enabled?() do
      :telemetry.attach(
        "gallformers-request-logger",
        [:phoenix, :endpoint, :stop],
        &__MODULE__.handle_event/4,
        nil
      )

      schedule_cleanup()
      Logger.info("RequestLogger attached, logging to #{log_dir()}")
    end

    :ok
  end

  @doc """
  Telemetry handler - formats and logs the request.
  """
  def handle_event(_event, measurements, metadata, _config) do
    entry = format_entry(measurements, metadata)
    append_to_log(entry)
  rescue
    e ->
      # Don't let logging failures crash the request
      Logger.warning("RequestLogger failed: #{inspect(e)}")
  end

  @doc """
  Deletes log files older than retention period.
  """
  def cleanup_old_logs do
    cutoff = Date.utc_today() |> Date.add(-@retention_days)
    dir = log_dir()

    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.filter(fn filename ->
        log_file?(filename) and Date.compare(file_date(filename), cutoff) == :lt
      end)
      |> Enum.each(fn filename ->
        path = Path.join(dir, filename)
        File.rm(path)
        Logger.info("RequestLogger deleted old log: #{filename}")
      end)
    end

    :ok
  end

  # --- Private ---

  defp enabled? do
    # Disabled in test by default, can override with config
    Application.get_env(:gallformers, :request_logger_enabled, true)
  end

  defp log_dir do
    Application.get_env(:gallformers, :request_log_dir, "/data/logs")
  end

  defp log_path do
    date = Date.utc_today() |> Date.to_iso8601()
    Path.join(log_dir(), "requests-#{date}.log")
  end

  defp format_entry(measurements, metadata) do
    conn = metadata.conn
    duration_ms = div(measurements.duration, 1_000_000)

    entry = %{
      ts: DateTime.utc_now() |> DateTime.to_iso8601(),
      method: conn.method,
      path: conn.request_path,
      status: conn.status,
      duration_ms: duration_ms,
      ip: get_client_ip(conn),
      ua: truncate(get_header(conn, "user-agent"), @ua_max_length)
    }

    # Only include query if non-empty
    entry =
      if conn.query_string != "" do
        Map.put(entry, :query, conn.query_string)
      else
        entry
      end

    Jason.encode!(entry)
  end

  defp append_to_log(entry) do
    path = log_path()
    ensure_log_dir()
    File.write!(path, entry <> "\n", [:append])
  end

  defp ensure_log_dir do
    dir = log_dir()

    unless File.dir?(dir) do
      File.mkdir_p!(dir)
    end
  end

  defp get_client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "fly-client-ip") do
      [ip | _] ->
        ip

      [] ->
        case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
          [ips | _] -> ips |> String.split(",") |> List.first() |> String.trim()
          [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
        end
    end
  end

  defp get_header(conn, header) do
    case Plug.Conn.get_req_header(conn, header) do
      [value | _] -> value
      [] -> nil
    end
  end

  defp truncate(nil, _max), do: nil
  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max) <> "..."

  defp log_file?(filename) do
    String.match?(filename, ~r/^requests-\d{4}-\d{2}-\d{2}\.log$/)
  end

  defp file_date(filename) do
    # Extract date from "requests-2026-02-05.log"
    case Regex.run(~r/requests-(\d{4}-\d{2}-\d{2})\.log/, filename) do
      [_, date_str] -> Date.from_iso8601!(date_str)
      _ -> Date.utc_today()
    end
  end

  defp schedule_cleanup do
    # Run cleanup now and schedule daily
    Task.start(fn ->
      cleanup_old_logs()
      cleanup_loop()
    end)
  end

  defp cleanup_loop do
    Process.sleep(@cleanup_interval_ms)
    cleanup_old_logs()
    cleanup_loop()
  end
end
