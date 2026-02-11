defmodule Gallformers.Accounts.User do
  @moduledoc """
  Database-backed user profile schema.

  Stores user preferences and profile information for display on the site.
  Authentication and authorization are handled by Auth0 - this schema only
  stores user-editable profile data.

  ## Fields

  - `auth0_id` - Unique identifier from Auth0 (e.g., "auth0|12345")
  - `display_name` - User's chosen display name (from Auth0, editable)
  - `nickname` - Fallback display name from Auth0
  - `about_me` - User's bio/description text
  - `inaturalist_url` - Link to user's iNaturalist profile
  - `social_url` - Link to social media (Twitter, Mastodon, etc.)
  - `personal_url` - Link to personal website
  - `show_on_about` - Whether to display user on the About page
  """

  use Ecto.Schema
  import Ecto.Changeset

  @behaviour Gallformers.SchemaFields

  @required_fields [:auth0_id]

  @type t :: %__MODULE__{
          id: integer() | nil,
          auth0_id: String.t(),
          display_name: String.t() | nil,
          nickname: String.t() | nil,
          about_me: String.t() | nil,
          inaturalist_url: String.t() | nil,
          social_url: String.t() | nil,
          personal_url: String.t() | nil,
          show_on_about: boolean(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "users" do
    field :auth0_id, :string
    field :display_name, :string
    field :nickname, :string
    field :about_me, :string
    field :inaturalist_url, :string
    field :social_url, :string
    field :personal_url, :string
    field :show_on_about, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Changeset for creating a new user profile.

  Requires `auth0_id` to be present.
  """
  @spec create_changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def create_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :auth0_id,
      :display_name,
      :nickname,
      :about_me,
      :inaturalist_url,
      :social_url,
      :personal_url,
      :show_on_about
    ])
    |> validate_required(@required_fields)
    |> unique_constraint(:auth0_id)
    |> validate_url(:inaturalist_url)
    |> validate_url(:social_url)
    |> validate_url(:personal_url)
  end

  @doc """
  Changeset for updating an existing user profile.

  Does not allow changing the `auth0_id`.
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :display_name,
      :nickname,
      :about_me,
      :inaturalist_url,
      :social_url,
      :personal_url,
      :show_on_about
    ])
    |> validate_required([:display_name])
    |> validate_url(:inaturalist_url)
    |> validate_url(:social_url)
    |> validate_url(:personal_url)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: scheme, host: host}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _ ->
          [{field, "must be a valid URL"}]
      end
    end)
  end
end
