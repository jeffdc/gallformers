defmodule GallformersWeb.Live.UserAuth do
  @moduledoc """
  LiveView on_mount hooks for the current user.

    * `:fetch_current_user` makes the current user available to public
      LiveViews for the layout (header/footer display).
    * `:require_superadmin` and `:require_operator` guard the role-restricted
      admin live sessions. Plugs only run on HTTP requests, not on live
      navigation or socket connects, so these hooks enforce the same role
      checks as `GallformersWeb.Plugs.RequireSuperAdmin` and
      `GallformersWeb.Plugs.RequireOperator` whenever such a LiveView mounts.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias Gallformers.Accounts

  def on_mount(:fetch_current_user, _params, session, socket) do
    current_user = session["current_user"]
    {:cont, assign(socket, current_user: current_user)}
  end

  def on_mount(:require_superadmin, _params, session, socket) do
    require_role(session["current_user"], &Accounts.superadmin?/1, socket)
  end

  def on_mount(:require_operator, _params, session, socket) do
    require_role(session["current_user"], &Accounts.operator?/1, socket)
  end

  defp require_role(nil, _has_role?, socket) do
    {:halt,
     socket
     |> put_flash(:error, "You must log in to access this page.")
     |> redirect(to: "/auth/auth0")}
  end

  defp require_role(user, has_role?, socket) do
    if has_role?.(user) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> put_flash(:error, "You don't have permission to access that page.")
       |> redirect(to: "/admin")}
    end
  end
end
