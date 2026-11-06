defmodule GallformersWeb.Admin.OpsLive do
  @moduledoc """
  Operator-only page for managing site-wide operational settings:
  banner visibility, banner text, and read-only mode.
  """

  use GallformersWeb, :live_view

  alias Gallformers.SiteSettings

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    if connected?(socket), do: SiteSettings.subscribe()

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Site operations")
      |> assign_settings()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_banner", _params, socket) do
    new_value = !socket.assigns.banner_enabled
    SiteSettings.set("banner_enabled", new_value)
    {:noreply, assign(socket, :banner_enabled, new_value)}
  end

  def handle_event("toggle_read_only", _params, socket) do
    new_value = !socket.assigns.read_only
    SiteSettings.set("read_only", new_value)
    {:noreply, assign(socket, :read_only, new_value)}
  end

  def handle_event("save_banner_text", %{"banner_text" => text}, socket) do
    SiteSettings.set("banner_text", text)

    socket =
      socket
      |> assign(:banner_text, text)
      |> put_flash(:info, "Banner text updated.")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:setting_updated, key, value}, socket) do
    socket =
      case key do
        "banner_enabled" -> assign(socket, :banner_enabled, value)
        "banner_text" -> assign(socket, :banner_text, value)
        "read_only" -> assign(socket, :read_only, value)
        _ -> socket
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex max-w-form flex-col gap-section">
        <.page_header>
          <:crumb navigate={~p"/admin"}>Dashboard</:crumb>
          <:title>Site operations</:title>
          <:description>Switches that take effect on the live site at once.</:description>
        </.page_header>

        <.panel title="Site banner">
          <div class="flex flex-col gap-block">
            <div>
              <.toggle
                id="banner-enabled"
                name="banner_enabled"
                checked={@banner_enabled}
                label="Show the banner"
                phx-click="toggle_banner"
              />
              <p class="gf-hint">A notice across the top of every page.</p>
            </div>

            <form id="banner-text-form" phx-submit="save_banner_text" class="flex flex-col gap-2">
              <.input
                id="banner-text"
                name="banner_text"
                type="text"
                label="Banner text"
                value={@banner_text}
              />
              <div>
                <.button type="submit" variant="secondary" phx-disable-with="Saving…">
                  Save banner text
                </.button>
              </div>
            </form>
          </div>
        </.panel>

        <.panel title="Read-only mode">
          <.toggle
            id="read-only"
            name="read_only"
            checked={@read_only}
            label="Read-only"
            phx-click="toggle_read_only"
          />
          <p class="gf-hint">
            Blocks every change across the site. Use it during maintenance or migrations.
          </p>
        </.panel>
      </div>
    </Layouts.admin>
    """
  end

  defp assign_settings(socket) do
    socket
    |> assign(:banner_enabled, SiteSettings.banner_enabled?())
    |> assign(:banner_text, SiteSettings.banner_text())
    |> assign(:read_only, SiteSettings.read_only?())
  end
end
