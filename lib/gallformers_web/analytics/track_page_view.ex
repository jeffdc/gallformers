defmodule GallformersWeb.Analytics.TrackPageView do
  @moduledoc """
  LiveView on_mount hook for tracking page views.

  Tracks page views for LiveView navigations that happen over WebSocket
  (which bypass the HTTP Plug). The initial page load is already tracked
  by the Analytics Plug, so we skip the first handle_params call.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias Gallformers.Analytics

  def on_mount(:default, _params, session, socket) do
    # Assign analytics data from session (set by Analytics plug)
    socket =
      assign(socket,
        analytics_browser: session["analytics_browser"],
        analytics_device_type: session["analytics_device_type"],
        analytics_visitor_hash: session["analytics_visitor_hash"],
        analytics_ip: session["analytics_ip"],
        analytics_user_agent: session["analytics_user_agent"],
        analytics_hash_date: session["analytics_hash_date"]
      )

    socket =
      if connected?(socket) do
        socket
        # Skip the first handle_params - it's the initial page load already tracked by the Plug
        |> assign(:analytics_skip_initial, true)
        |> attach_hook(:track_page_view, :handle_params, &track_navigation/3)
      else
        socket
      end

    {:cont, socket}
  end

  defp track_navigation(_params, uri, socket) do
    # Skip tracking on the initial handle_params call (already tracked by Plug)
    if socket.assigns[:analytics_skip_initial] do
      {:cont, assign(socket, :analytics_skip_initial, false)}
    else
      %URI{path: path} = URI.parse(uri)

      # Get tracking data from socket assigns (set by initial HTTP request)
      # For LiveView navigations, we reuse the visitor hash from the session
      visitor_hash = get_visitor_hash(socket)

      if Analytics.should_track?(path, nil) and visitor_hash do
        attrs = %{
          path: path,
          referrer_host: "(internal)",
          browser: socket.assigns[:analytics_browser],
          device_type: socket.assigns[:analytics_device_type],
          visitor_hash: visitor_hash
        }

        Analytics.track_page_view(attrs)
      end

      {:cont, socket}
    end
  end

  defp get_visitor_hash(socket) do
    stored_hash = socket.assigns[:analytics_visitor_hash]
    hash_date = socket.assigns[:analytics_hash_date]
    today = Date.utc_today() |> Date.to_iso8601()

    cond do
      # No hash available — skip tracking (caller checks for nil)
      is_nil(stored_hash) ->
        nil

      # Hash is from today — use it
      hash_date == today ->
        stored_hash

      # Hash is stale (past midnight UTC) — regenerate from stored IP/UA
      true ->
        ip = socket.assigns[:analytics_ip]
        ua = socket.assigns[:analytics_user_agent]

        if ip do
          Analytics.generate_visitor_hash(ip, ua)
        else
          nil
        end
    end
  end
end
