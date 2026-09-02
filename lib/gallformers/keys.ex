defmodule Gallformers.Keys do
  @moduledoc """
  Context for managing dichotomous identification keys.

  Keys are stored in the database with metadata and a couplets JSON column.
  Admins can create, edit, and delete keys through the admin interface.
  """
  use Boundary,
    deps: [
      Gallformers.Repo,
      Gallformers.ChangesetHelpers,
      Gallformers.SchemaFields,
      Gallformers.ContentImages,
      Gallformers.Storage
    ],
    exports: :all

  import Ecto.Query
  alias Gallformers.Keys.Key
  alias Gallformers.Repo
  alias Gallformers.Storage.PDFKeys

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
  Gets a key by ID, returning nil if it no longer exists.
  """
  @spec get_key_by_id(integer()) :: Key.t() | nil
  def get_key_by_id(id), do: Repo.get(Key, id)

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
    s3_paths = Gallformers.ContentImages.collect_s3_paths_for_key(key.id)

    case Repo.delete(key) do
      {:ok, deleted} ->
        Gallformers.ContentImages.delete_collected_s3_paths(s3_paths)
        {:ok, deleted}

      error ->
        error
    end
  end

  @doc """
  Returns a changeset for tracking key changes.
  """
  @spec change_key(Key.t(), map()) :: Ecto.Changeset.t()
  def change_key(%Key{} = key, attrs \\ %{}) do
    Key.changeset(key, attrs)
  end

  @doc """
  Returns the URLs for a key's PDFs.
  """
  @spec pdf_urls(Key.t()) :: %{text_only: String.t(), with_images: String.t()}
  def pdf_urls(key), do: PDFKeys.public_urls(key)

  # =====================================================================
  # PDF generation — delegated to Keys.PdfGenerator
  # =====================================================================

  defdelegate generate_pdf(key, opts \\ []), to: Gallformers.Keys.PdfGenerator
  defdelegate generate_and_upload(key), to: Gallformers.Keys.PdfGenerator

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
