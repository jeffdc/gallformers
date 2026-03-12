defmodule Gallformers.Accounts do
  @moduledoc """
  The Accounts context handles user authentication and authorization.

  Authentication is handled by Auth0 via Ueberauth. User profiles are stored in
  the local database for preferences and public display (like the About page),
  but Auth0 remains the source of truth for authentication and authorization.

  Authorization is role-based, with roles provided by Auth0 custom claims:
  - `admin`: Can access admin features and modify data
  - `superadmin`: Full access including dangerous operations
  """

  import Ecto.Query

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Accounts.User
  alias Gallformers.Repo

  @doc """
  Fetches the current user from the session.

  Returns nil if no user is logged in.
  """
  @spec get_user_from_session(Plug.Conn.t() | map()) :: Auth0User.t() | nil
  def get_user_from_session(%Plug.Conn{} = conn) do
    Plug.Conn.get_session(conn, :current_user)
  end

  def get_user_from_session(%{} = session) do
    Map.get(session, "current_user")
  end

  @doc """
  Stores the user in the session after successful authentication.
  """
  @spec put_user_in_session(Plug.Conn.t(), Auth0User.t()) :: Plug.Conn.t()
  def put_user_in_session(conn, %Auth0User{} = user) do
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
  @spec user_from_auth(Ueberauth.Auth.t()) :: Auth0User.t()
  def user_from_auth(%Ueberauth.Auth{} = auth) do
    Auth0User.from_auth(auth)
  end

  @doc """
  Syncs user profile data from Auth0 to the local database.

  On successful login:
  - If the user doesn't exist, creates a new profile with data from Auth0
  - If the user exists, updates the nickname and conditionally updates display_name

  The display_name is only updated if the user hasn't customized it (i.e., if it
  currently matches the old nickname or is nil).

  ## Examples

      iex> sync_user_from_auth0(%Auth0User{id: "auth0|123", name: "Alice", nickname: "alice"})
      {:ok, %User{}}
  """
  @spec sync_user_from_auth0(Auth0User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def sync_user_from_auth0(%Auth0User{} = auth0_user) do
    case get_user_by_auth0_id(auth0_user.id) do
      nil ->
        create_user(%{
          auth0_id: auth0_user.id,
          display_name: auth0_user.name,
          nickname: auth0_user.nickname,
          show_on_about: false
        })

      %User{} = user ->
        attrs = build_update_attrs(user, auth0_user)
        update_user(user, attrs)
    end
  end

  # Build the attributes to update for an existing user.
  # Always syncs nickname from Auth0.
  # Only updates display_name if the user hasn't customized it.
  defp build_update_attrs(%User{} = user, %Auth0User{} = auth0_user) do
    attrs = %{nickname: auth0_user.nickname}

    # Only update display_name if user hasn't customized it
    # (i.e., it matches the old nickname or is nil)
    if user.display_name == user.nickname or is_nil(user.display_name) do
      Map.put(attrs, :display_name, auth0_user.name)
    else
      attrs
    end
  end

  @doc """
  Returns the DB display name from the session.

  Falls back to "Unknown" if not set.
  """
  @spec db_display_name(map()) :: String.t()
  def db_display_name(%{} = session) do
    case Map.get(session, "db_display_name") do
      nil -> "Unknown"
      "" -> "Unknown"
      name -> name
    end
  end

  @doc """
  Returns true if the user is an admin (or superadmin).

  Accepts Auth0User structs or any map with a `roles` field (to handle
  session deserialization where struct types may not be preserved).
  """
  @spec admin?(Auth0User.t() | map() | nil) :: boolean()
  def admin?(nil), do: false
  def admin?(%Auth0User{} = user), do: Auth0User.admin?(user)
  def admin?(%{roles: roles}) when is_list(roles), do: "admin" in roles or "superadmin" in roles
  def admin?(_), do: false

  @doc """
  Returns true if the user is a superadmin.

  Accepts Auth0User structs or any map with a `roles` field (to handle
  session deserialization where struct types may not be preserved).
  """
  @spec superadmin?(Auth0User.t() | map() | nil) :: boolean()
  def superadmin?(nil), do: false
  def superadmin?(%Auth0User{} = user), do: Auth0User.superadmin?(user)
  def superadmin?(%{roles: roles}) when is_list(roles), do: "superadmin" in roles
  def superadmin?(_), do: false

  @doc """
  Returns true if the user is an operator.

  Accepts Auth0User structs or any map with a `roles` field (to handle
  session deserialization where struct types may not be preserved).
  """
  @spec operator?(Auth0User.t() | map() | nil) :: boolean()
  def operator?(nil), do: false
  def operator?(%Auth0User{} = user), do: Auth0User.operator?(user)
  def operator?(%{roles: roles}) when is_list(roles), do: "operator" in roles
  def operator?(_), do: false

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

  @doc """
  Returns the Auth0 password reset URL.

  Links to Auth0's Universal Login with the reset-password screen hint,
  so the user lands directly on the password reset form.
  """
  @spec password_reset_url() :: String.t()
  def password_reset_url do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Auth0.OAuth, [])
    domain = Keyword.get(config, :domain, "")
    client_id = Keyword.get(config, :client_id, "")

    "https://#{domain}/authorize?" <>
      URI.encode_query(%{
        "client_id" => client_id,
        "response_type" => "code",
        "screen_hint" => "reset-password"
      })
  end

  # ============================================================================
  # User Profile Functions (Database-backed)
  # ============================================================================

  @doc """
  Gets a user profile by ID.

  Returns `nil` if the user does not exist.

  ## Examples

      iex> get_user(123)
      %User{}

      iex> get_user(999)
      nil
  """
  @spec get_user(integer()) :: User.t() | nil
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Gets a user profile by Auth0 ID.

  Returns `nil` if no user with that Auth0 ID exists.

  ## Examples

      iex> get_user_by_auth0_id("auth0|123")
      %User{}

      iex> get_user_by_auth0_id("auth0|unknown")
      nil
  """
  @spec get_user_by_auth0_id(String.t()) :: User.t() | nil
  def get_user_by_auth0_id(auth0_id) do
    Repo.get_by(User, auth0_id: auth0_id)
  end

  @doc """
  Gets a user profile by nickname.

  Returns `nil` if no user with that nickname exists.

  ## Examples

      iex> get_user_by_nickname("alice")
      %User{}

      iex> get_user_by_nickname("unknown")
      nil
  """
  @spec get_user_by_nickname(String.t()) :: User.t() | nil
  def get_user_by_nickname(nickname) do
    Repo.get_by(User, nickname: nickname)
  end

  @doc """
  Creates a new user profile.

  ## Examples

      iex> create_user(%{auth0_id: "auth0|123", display_name: "Alice"})
      {:ok, %User{}}

      iex> create_user(%{})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def create_user(attrs) do
    %User{}
    |> User.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing user profile.

  ## Examples

      iex> update_user(user, %{display_name: "New Name"})
      {:ok, %User{}}

      iex> update_user(user, %{inaturalist_url: "not-a-url"})
      {:error, %Ecto.Changeset{}}
  """
  @spec update_user(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists users who have opted in to appear on the About page.

  Returns users ordered by display name (nulls last).

  ## Examples

      iex> list_users_for_about_page()
      [%User{show_on_about: true}, ...]
  """
  @spec list_users_for_about_page() :: [User.t()]
  def list_users_for_about_page do
    User
    |> where([u], u.show_on_about == true)
    |> order_by([u], fragment("lower(COALESCE(?, ?))", u.display_name, u.nickname))
    |> Repo.all()
  end

  @doc """
  Lists all users ordered alphabetically by display name (with nickname fallback).

  Used by superadmin user management page.

  ## Examples

      iex> list_all_users()
      [%User{}, ...]
  """
  @spec list_all_users() :: [User.t()]
  def list_all_users do
    User
    |> order_by([u], fragment("lower(COALESCE(?, ?))", u.display_name, u.nickname))
    |> Repo.all()
  end
end
