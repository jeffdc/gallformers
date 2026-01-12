defmodule GallformersWeb.AuthController do
  @moduledoc """
  Controller for handling Auth0 OAuth authentication via Ueberauth.
  """

  use GallformersWeb, :controller

  plug Ueberauth

  alias Gallformers.Accounts
  alias Gallformers.Accounts.User

  @doc """
  Handles the OAuth callback from Auth0.

  On success, creates a user from the auth response and stores it in the session.
  On failure, redirects to the home page with an error message.
  """
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user = Accounts.user_from_auth(auth)

    conn
    |> Accounts.put_user_in_session(user)
    |> put_flash(:info, "Welcome back, #{User.display_name(user)}!")
    |> redirect(to: get_return_to(conn))
  end

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, _params) do
    # Log the failure for debugging
    require Logger
    Logger.warning("Auth0 authentication failed: #{inspect(failure)}")

    conn
    |> put_flash(:error, "Authentication failed. Please try again.")
    |> redirect(to: ~p"/")
  end

  @doc """
  Logs the user out by clearing the session and redirecting to Auth0 logout.
  """
  def logout(conn, _params) do
    return_to = url(~p"/")
    logout_url = Accounts.logout_url(return_to)

    conn
    |> Accounts.clear_session()
    |> redirect(external: logout_url)
  end

  # Get the return URL from session or default to admin dashboard
  defp get_return_to(conn) do
    case get_session(conn, :return_to) do
      nil -> ~p"/admin"
      path -> path
    end
  end
end
