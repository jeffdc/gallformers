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
        analytics_visitor_hash: session["analytics_visitor_hash"]
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
      if Analytics.should_track?(path, nil) do
        visitor_hash = get_visitor_hash(socket)

        attrs = %{
          path: path,
          referrer_host: nil,
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
    # Use stored hash from initial page load, or generate a fallback
    socket.assigns[:analytics_visitor_hash] ||
      Analytics.generate_visitor_hash("unknown", nil)
  end
end
