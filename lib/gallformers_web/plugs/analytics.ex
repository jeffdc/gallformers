defmodule GallformersWeb.Plugs.Analytics do
  @moduledoc """
  Plug that tracks page views for analytics.

  Runs after the response is sent and spawns an async task to record
  the page view, ensuring no impact on response time.
  """

  import Plug.Conn

  alias Gallformers.Analytics

  def init(opts), do: opts

  def call(conn, _opts) do
    # Store analytics data in session for LiveView navigations
    conn = store_analytics_in_session(conn)

    register_before_send(conn, fn conn ->
      if conn.status == 200 and Analytics.should_track?(conn.request_path, user_agent(conn)) do
        track(conn)
      end

      conn
    end)
  end

  defp track(conn) do
    ip = get_client_ip(conn)
    user_agent = user_agent(conn)
    {browser, device_type} = Analytics.parse_user_agent(user_agent)

    attrs = %{
      path: conn.request_path,
      referrer_host: Analytics.extract_referrer_host(referrer(conn), conn.host),
      browser: browser,
      device_type: device_type,
      visitor_hash: Analytics.generate_visitor_hash(ip, user_agent)
    }

    Analytics.track_page_view(attrs)
  end

  defp user_agent(conn) do
    case get_req_header(conn, "user-agent") do
      [ua | _] -> ua
      [] -> nil
    end
  end

  defp referrer(conn) do
    case get_req_header(conn, "referer") do
      [ref | _] -> ref
      [] -> nil
    end
  end

  defp get_client_ip(conn) do
    # Check for forwarded IP (from Fly.io proxy)
    case get_req_header(conn, "fly-client-ip") do
      [ip | _] ->
        ip

      [] ->
        case get_req_header(conn, "x-forwarded-for") do
          [ips | _] -> ips |> String.split(",") |> List.first() |> String.trim()
          [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
        end
    end
  end

  defp store_analytics_in_session(conn) do
    ip = get_client_ip(conn)
    user_agent = user_agent(conn)
    {browser, device_type} = Analytics.parse_user_agent(user_agent)
    visitor_hash = Analytics.generate_visitor_hash(ip, user_agent)

    conn
    |> put_session(:analytics_browser, browser)
    |> put_session(:analytics_device_type, device_type)
    |> put_session(:analytics_visitor_hash, visitor_hash)
    |> put_session(:analytics_ip, ip)
    |> put_session(:analytics_user_agent, user_agent)
    |> put_session(:analytics_hash_date, Date.utc_today() |> Date.to_iso8601())
  end
end
