defmodule Gallformers.Keys do
  @moduledoc """
  Context for managing dichotomous identification keys.

  Keys are stored in the database with metadata and a couplets JSON column.
  Admins can create, edit, and delete keys through the admin interface.
  """

  import Ecto.Query
  alias Gallformers.Keys.Key
  alias Gallformers.Repo

  @doc """
  Returns a list of all available keys (metadata only, no couplet data).
  """
  @spec list_keys() :: [Key.t()]
  def list_keys do
    Key
    |> select([k], %{
      id: k.id,
      slug: k.slug,
      title: k.title,
      subtitle: k.subtitle,
      authors: k.authors,
      citation: k.citation,
      citation_url: k.citation_url,
      description: k.description,
      version: k.version
    })
    |> order_by([k], asc: k.title)
    |> Repo.all()
  end

  @doc """
  Returns the full key data for the given slug, including all couplets.
  """
  @spec get_key(String.t()) :: {:ok, Key.t()} | {:error, :not_found}
  def get_key(slug) do
    case Repo.get_by(Key, slug: slug) do
      nil -> {:error, :not_found}
      key -> {:ok, key}
    end
  end

  @doc """
  Gets a key by ID. Raises if not found.
  """
  @spec get_key!(integer()) :: Key.t()
  def get_key!(id) do
    Repo.get!(Key, id)
  end

  @doc """
  Returns the couplet numbers for a key, sorted numerically.
  """
  @spec couplet_numbers(Key.t() | map()) :: [String.t()]
  def couplet_numbers(key) do
    key.couplets
    |> Map.keys()
    |> Enum.sort_by(&String.to_integer/1)
  end

  @doc """
  Creates a new key.
  """
  @spec create_key(map()) :: {:ok, Key.t()} | {:error, Ecto.Changeset.t()}
  def create_key(attrs \\ %{}) do
    %Key{}
    |> Key.changeset(attrs)
    |> ensure_unique_slug()
    |> Repo.insert()
  end

  @doc """
  Updates an existing key.
  """
  @spec update_key(Key.t(), map()) :: {:ok, Key.t()} | {:error, Ecto.Changeset.t()}
  def update_key(%Key{} = key, attrs) do
    key
    |> Key.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a key.
  """
  @spec delete_key(Key.t()) :: {:ok, Key.t()} | {:error, Ecto.Changeset.t()}
  def delete_key(%Key{} = key) do
    Repo.delete(key)
  end

  @doc """
  Returns a changeset for tracking key changes.
  """
  @spec change_key(Key.t(), map()) :: Ecto.Changeset.t()
  def change_key(%Key{} = key, attrs \\ %{}) do
    Key.changeset(key, attrs)
  end

  # Ensures the slug is unique by appending a number if necessary
  defp ensure_unique_slug(changeset) do
    slug = Ecto.Changeset.get_field(changeset, :slug)
    exclude_id = changeset.data.id

    if slug && slug_exists?(slug, exclude_id) do
      unique_slug = find_unique_slug(slug, exclude_id, 2)
      Ecto.Changeset.put_change(changeset, :slug, unique_slug)
    else
      changeset
    end
  end

  defp slug_exists?(slug, nil) do
    Repo.exists?(from(k in Key, where: k.slug == ^slug))
  end

  defp slug_exists?(slug, exclude_id) do
    Repo.exists?(from(k in Key, where: k.slug == ^slug and k.id != ^exclude_id))
  end

  defp find_unique_slug(base_slug, exclude_id, n) do
    candidate = "#{base_slug}-#{n}"

    if slug_exists?(candidate, exclude_id) do
      find_unique_slug(base_slug, exclude_id, n + 1)
    else
      candidate
    end
  end
end
