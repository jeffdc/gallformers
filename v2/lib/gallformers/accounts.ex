defmodule Gallformers.Accounts do
  @moduledoc """
  The Accounts context handles user authentication and authorization.

  Authentication is handled by Auth0 via Ueberauth. Users are not stored in the
  local database - instead, we rely on Auth0 for user management and extract
  user information from the authentication response.

  Authorization is role-based, with roles provided by Auth0 custom claims:
  - `admin`: Can access admin features and modify data
  - `superadmin`: Full access including dangerous operations
  """

  alias Gallformers.Accounts.User

  @doc """
  Fetches the current user from the session.

  Returns nil if no user is logged in.
  """
  @spec get_user_from_session(Plug.Conn.t() | map()) :: User.t() | nil
  def get_user_from_session(%Plug.Conn{} = conn) do
    Plug.Conn.get_session(conn, :current_user)
  end

  def get_user_from_session(%{} = session) do
    Map.get(session, "current_user")
  end

  @doc """
  Stores the user in the session after successful authentication.
  """
  @spec put_user_in_session(Plug.Conn.t(), User.t()) :: Plug.Conn.t()
  def put_user_in_session(conn, %User{} = user) do
    conn
    |> Plug.Conn.put_session(:current_user, user)
    |> Plug.Conn.configure_session(renew: true)
  end

  @doc """
  Removes the user from the session (logout).
  """
  @spec clear_session(Plug.Conn.t()) :: Plug.Conn.t()
  def clear_session(conn) do
    Plug.Conn.configure_session(conn, drop: true)
  end

  @doc """
  Creates a User struct from an Ueberauth authentication response.
  """
  @spec user_from_auth(Ueberauth.Auth.t()) :: User.t()
  def user_from_auth(%Ueberauth.Auth{} = auth) do
    User.from_auth(auth)
  end

  @doc """
  Returns true if the user is an admin (or superadmin).
  """
  @spec admin?(User.t() | nil) :: boolean()
  def admin?(nil), do: false
  def admin?(%User{} = user), do: User.admin?(user)

  @doc """
  Returns true if the user is a superadmin.
  """
  @spec superadmin?(User.t() | nil) :: boolean()
  def superadmin?(nil), do: false
  def superadmin?(%User{} = user), do: User.superadmin?(user)

  @doc """
  Returns the Auth0 logout URL.

  This URL will clear the Auth0 session and redirect back to the specified URL.
  """
  @spec logout_url(String.t()) :: String.t()
  def logout_url(return_to) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Auth0.OAuth, [])
    domain = Keyword.get(config, :domain, "")
    client_id = Keyword.get(config, :client_id, "")

    "https://#{domain}/v2/logout?" <>
      URI.encode_query(%{
        "client_id" => client_id,
        "returnTo" => return_to
      })
  end
end
