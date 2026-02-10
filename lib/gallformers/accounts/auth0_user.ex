defmodule Gallformers.Accounts.Auth0User do
  @moduledoc """
  Represents an authenticated user from Auth0.

  This is not a database-backed schema - user data comes from Auth0 claims.
  The struct holds the relevant user information extracted from the Auth0 response.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          email: String.t() | nil,
          name: String.t() | nil,
          nickname: String.t() | nil,
          picture: String.t() | nil,
          roles: [String.t()]
        }

  defstruct [:id, :email, :name, :nickname, :picture, roles: []]

  @doc """
  Creates an Auth0User struct from Ueberauth Auth0 response.

  ## Examples

      iex> auth = %Ueberauth.Auth{uid: "auth0|123", info: %{email: "test@example.com"}}
      iex> Auth0User.from_auth(auth)
      %Auth0User{id: "auth0|123", email: "test@example.com", ...}
  """
  @spec from_auth(Ueberauth.Auth.t()) :: t()
  def from_auth(%Ueberauth.Auth{} = auth) do
    %__MODULE__{
      id: auth.uid,
      email: auth.info.email,
      name: auth.info.name,
      nickname: auth.info.nickname,
      picture: auth.info.image,
      roles: extract_roles(auth)
    }
  end

  # Auth0 custom claims use a namespace to avoid collisions
  # The roles claim is at https://gallformers.org/roles
  defp extract_roles(%Ueberauth.Auth{extra: %{raw_info: %{user: user}}}) do
    Map.get(user, "https://gallformers.org/roles", [])
  end

  defp extract_roles(_), do: []

  @doc """
  Returns true if the user has the admin role.
  """
  @spec admin?(t()) :: boolean()
  def admin?(%__MODULE__{roles: roles}) do
    "admin" in roles or "superadmin" in roles
  end

  @doc """
  Returns true if the user has the superadmin role.
  """
  @spec superadmin?(t()) :: boolean()
  def superadmin?(%__MODULE__{roles: roles}) do
    "superadmin" in roles
  end

  @doc """
  Returns the display name for the user, preferring name over nickname over email.
  """
  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{name: name}) when name not in [nil, ""], do: name
  def display_name(%__MODULE__{nickname: nickname}) when nickname not in [nil, ""], do: nickname
  def display_name(%__MODULE__{email: email}) when email not in [nil, ""], do: email
  def display_name(_), do: "Unknown User"
end
