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
    * `:require_admin_actor` guards the `:admin` live session of the admin
      screens on the new back-end (matter a856): it requires an admin, as
      `GallformersWeb.Plugs.RequireAdmin` does, and resolves the session
      user to their local user (`Gallformers.Accounts.get_user_by_auth0_id/1`),
      assigning `:current_user` (the session user, as the admin layout
      takes it) and `:actor`, the `Gallformers.Audit.Actor` their audited
      writes name. An admin with no local user (one is made at sign-in) is
      sent back to the admin dashboard.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias Gallformers.Accounts
  alias Gallformers.Accounts.User
  alias Gallformers.Audit.Actor

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

  def on_mount(:require_admin_actor, _params, session, socket) do
    session_user = session["current_user"]

    with {:cont, socket} <- require_role(session_user, &Accounts.admin?/1, socket) do
      case local_user(session_user) do
        %User{} = user ->
          {:cont,
           assign(socket, current_user: session_user, actor: Actor.user(user.id, name(user)))}

        nil ->
          {:halt,
           socket
           |> put_flash(
             :error,
             "Your user profile could not be found. Sign out and in again, then retry."
           )
           |> redirect(to: "/admin")}
      end
    end
  end

  defp local_user(%{id: auth0_id}) when is_binary(auth0_id),
    do: Accounts.get_user_by_auth0_id(auth0_id)

  defp local_user(_session_user), do: nil

  # The name the audit trail records: the profile's display name, else its
  # nickname, else the Auth0 ID (never blank).
  defp name(%User{display_name: name}) when name not in [nil, ""], do: name
  defp name(%User{nickname: nickname}) when nickname not in [nil, ""], do: nickname
  defp name(%User{auth0_id: auth0_id}), do: auth0_id

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
