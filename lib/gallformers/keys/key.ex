defmodule Gallformers.Keys.Key do
  @moduledoc """
  Ecto schema for the keys table.

  Represents a dichotomous identification key with metadata and a set of
  numbered couplets stored as a JSON object.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour Gallformers.SchemaFields

  @required_fields [:title, :version, :couplets]
  @optional_fields [:slug, :subtitle, :authors, :citation, :citation_url, :description]

  @type t :: %__MODULE__{
          id: integer() | nil,
          slug: String.t() | nil,
          title: String.t() | nil,
          subtitle: String.t() | nil,
          authors: [String.t()],
          citation: String.t() | nil,
          citation_url: String.t() | nil,
          description: String.t() | nil,
          version: String.t() | nil,
          couplets: map() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "keys" do
    field :slug, :string
    field :title, :string
    field :subtitle, :string
    field :authors, Gallformers.Articles.TagsType, default: []
    field :citation, :string
    field :citation_url, :string
    field :description, :string
    field :version, :string
    field :couplets, Gallformers.Keys.CoupletsType

    timestamps()
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Creates a changeset for a key.

  Automatically generates a slug from the title if not provided.
  """
  def changeset(key, attrs) do
    key
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> maybe_generate_slug()
    |> validate_required([:slug])
    |> validate_length(:title, min: 1, max: 300)
    |> validate_length(:slug, min: 1, max: 300)
    |> unique_constraint(:slug)
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      slug when slug in [nil, ""] ->
        case get_field(changeset, :title) do
          nil -> changeset
          title -> put_change(changeset, :slug, slugify(title))
        end

      _slug ->
        changeset
    end
  end

  @doc """
  Converts a string to a URL-friendly slug.
  """
  @spec slugify(String.t()) :: String.t()
  def slugify(string) when is_binary(string) do
    string
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/u, "")
    |> String.replace(~r/[\s_]+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  def slugify(_), do: ""
end
