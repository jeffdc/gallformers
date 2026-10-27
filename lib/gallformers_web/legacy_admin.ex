defmodule GallformersWeb.LegacyAdmin do
  @moduledoc """
  The switch for the old-domain admin screens (matter `a856`).

  On taxogall the old Gall / Host / gall–host / range / taxonomy / section /
  Source / species–source / image / filter-term screens write only the old
  tables, so they damage data the new back-end reads. They are disabled, not
  deleted: each screen's code goes when its replacement lands.

  `config :gallformers, legacy_admin_enabled: false` turns them off (dev and
  prod); test turns them on so their tests keep running. The flag is read at
  runtime, so a test can flip it with `Application.put_env/3`.

  A disabled screen is stopped in two places, because plugs don't run on live
  navigation or when a socket connects:

    * `GallformersWeb.Plugs.RequireLegacyAdmin` on the HTTP request renders
      the "being rebuilt" page in place (status 200).
    * `on_mount(:ensure_enabled, ...)`, on the gated routes' live sessions,
      sends the socket to the admin dashboard with the same notice as a flash
      (a LiveView can't render another page from `on_mount`).

  `enabled?/0` also hides every link to the gated screens.
  """

  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  @notice "This admin screen is being rebuilt"

  @doc """
  Whether the old admin screens are enabled.
  """
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:gallformers, :legacy_admin_enabled, false) == true

  @doc """
  The notice shown in place of a disabled screen.
  """
  @spec notice() :: String.t()
  def notice, do: @notice

  @doc """
  The note shown on links and actions to a disabled screen.
  """
  @spec disabled_message() :: String.t()
  def disabled_message, do: "Being rebuilt (taxogall step 10)"

  @doc """
  LiveView `on_mount` hook for the gated routes' live sessions: halts the
  mount and sends the socket to the admin dashboard when the old admin
  screens are disabled.
  """
  @spec on_mount(
          :ensure_enabled,
          map() | :not_mounted_at_router,
          map(),
          Phoenix.LiveView.Socket.t()
        ) ::
          {:cont | :halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:ensure_enabled, _params, _session, socket) do
    if enabled?() do
      {:cont, socket}
    else
      {:halt, socket |> put_flash(:info, "#{@notice}.") |> redirect(to: "/admin")}
    end
  end
end
