defmodule GallformersWeb.Admin.UsersLive do
  @moduledoc """
  Admin page for superadmins to manage user About page visibility.

  This is a cleanup tool for when someone loses admin access in Auth0
  but their show_on_about flag is still true.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Accounts

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Users")
      |> load_users()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_show_on_about", %{"id" => id}, socket) do
    user = Accounts.get_user(String.to_integer(id))

    case Accounts.update_user(user, %{show_on_about: !user.show_on_about}) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User visibility updated")
         |> load_users()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update user")}
    end
  end

  defp load_users(socket) do
    users = Accounts.list_all_users()
    assign(socket, :users, users)
  end

  defp display_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp display_name(%{nickname: nickname}) when is_binary(nickname), do: nickname
  defp display_name(_), do: "(no name)"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:crumb navigate={~p"/admin"}>Dashboard</:crumb>
          <:title>Users</:title>
          <:meta label="Users">{length(@users)}</:meta>
          <:description>
            Manage which users appear on the About page. Turn it off for anyone who has lost admin access but still shows there.
          </:description>
        </.page_header>

        <.data_table id="users" rows={@users} row_id={&"users-#{&1.id}"}>
          <:col :let={user} label="Display name" grow>
            <span class="font-semibold">{display_name(user)}</span>
          </:col>
          <:col :let={user} label="Nickname">
            <span class="text-ink-2">{user.nickname || "–"}</span>
          </:col>
          <:col :let={user} label="On the About page">
            <.toggle
              id={"show-on-about-#{user.id}"}
              name="show_on_about"
              checked={user.show_on_about}
              aria-label={"Show #{display_name(user)} on the About page"}
              phx-click="toggle_show_on_about"
              phx-value-id={user.id}
            />
          </:col>
          <:empty>No users yet.</:empty>
        </.data_table>
      </div>
    </Layouts.admin>
    """
  end
end
