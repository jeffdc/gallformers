defmodule Gallformers.Articles do
  @moduledoc """
  The Articles context.

  Provides functions for working with reference articles including
  listing, creating, updating, and searching by tags.
  """

  import Ecto.Query
  alias Gallformers.Articles.Article
  alias Gallformers.Repo

  @doc """
  Returns all articles, optionally filtered.

  ## Options

    * `:published_only` - if true, only returns published articles (default: false)
    * `:tag` - filter by a specific tag

  """
  @spec list_articles(keyword()) :: [Article.t()]
  def list_articles(opts \\ []) do
    published_only = Keyword.get(opts, :published_only, false)
    tag = Keyword.get(opts, :tag)

    Article
    |> maybe_filter_published(published_only)
    |> maybe_filter_by_tag(tag)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  defp maybe_filter_published(query, true) do
    where(query, [a], a.is_published == true)
  end

  defp maybe_filter_published(query, _), do: query

  defp maybe_filter_by_tag(query, nil), do: query
  defp maybe_filter_by_tag(query, ""), do: query

  defp maybe_filter_by_tag(query, tag) do
    where(
      query,
      [a],
      fragment(
        "EXISTS (SELECT 1 FROM jsonb_array_elements_text(?::jsonb) AS t(value) WHERE t.value = ?)",
        a.tags,
        ^tag
      )
    )
  end

  @doc """
  Returns all published articles ordered by date (newest first).
  """
  @spec list_published_articles() :: [Article.t()]
  def list_published_articles do
    list_articles(published_only: true)
  end

  @doc """
  Returns all unique tags across all articles, sorted alphabetically.
  """
  @spec list_all_tags() :: [String.t()]
  def list_all_tags do
    Article
    |> select([a], a.tags)
    |> Repo.all()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns a list of {id, title} tuples for all articles, sorted by title.

  Useful for dropdown filters in the image browser.
  """
  @spec list_article_options() :: [{integer(), String.t()}]
  def list_article_options do
    Article
    |> select([a], {a.id, a.title})
    |> order_by([a], asc: a.title)
    |> Repo.all()
  end

  @doc """
  Finds all articles that contain a reference to the given image URL in their content.

  Used to check if an image can be safely deleted.

  Returns a list of {id, title} tuples for articles containing the URL.
  """
  @spec find_articles_referencing_image(String.t()) :: [{integer(), String.t()}]
  def find_articles_referencing_image(image_url) when is_binary(image_url) do
    # Search for the URL in article content
    search_pattern = "%#{image_url}%"

    Article
    |> where([a], like(a.content, ^search_pattern))
    |> select([a], {a.id, a.title})
    |> order_by([a], asc: a.title)
    |> Repo.all()
  end

  @doc """
  Gets an article by ID.

  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_article!(integer()) :: Article.t()
  def get_article!(id) do
    Repo.get!(Article, id)
  end

  @doc """
  Gets an article by slug.

  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_article_by_slug!(String.t()) :: Article.t()
  def get_article_by_slug!(slug) do
    Repo.get_by!(Article, slug: slug)
  end

  @doc """
  Gets an article by slug, returning nil if not found.
  """
  @spec get_article_by_slug(String.t()) :: Article.t() | nil
  def get_article_by_slug(slug) do
    Repo.get_by(Article, slug: slug)
  end

  @doc """
  Creates an article.

  If the generated slug already exists, appends a number to make it unique.
  Sets published_at if the article is being created as published.
  """
  @spec create_article(map()) :: {:ok, Article.t()} | {:error, Ecto.Changeset.t()}
  def create_article(attrs \\ %{}) do
    %Article{}
    |> Article.changeset(attrs)
    |> ensure_unique_slug()
    |> maybe_set_published_at(nil)
    |> Repo.insert()
    |> broadcast(:article_created)
  end

  @doc """
  Updates an article.

  Sets published_at when transitioning from unpublished to published.
  """
  @spec update_article(Article.t(), map()) :: {:ok, Article.t()} | {:error, Ecto.Changeset.t()}
  def update_article(%Article{} = article, attrs) do
    article
    |> Article.changeset(attrs)
    |> maybe_set_published_at(article)
    |> Repo.update()
    |> broadcast(:article_updated)
  end

  # Sets published_at when an article transitions to published status
  defp maybe_set_published_at(changeset, original_article) do
    is_publishing = Ecto.Changeset.get_field(changeset, :is_published) == true
    was_published = original_article != nil and original_article.is_published == true
    has_published_at = Ecto.Changeset.get_field(changeset, :published_at) != nil

    if is_publishing and not was_published and not has_published_at do
      Ecto.Changeset.put_change(
        changeset,
        :published_at,
        DateTime.utc_now() |> DateTime.truncate(:second)
      )
    else
      changeset
    end
  end

  # Ensures the slug is unique by appending a number if necessary
  defp ensure_unique_slug(changeset) do
    slug = Ecto.Changeset.get_field(changeset, :slug)
    # Exclude current article id when updating (nil for new articles)
    exclude_id = changeset.data.id

    if slug && slug_exists?(slug, exclude_id) do
      unique_slug = find_unique_slug(slug, exclude_id, 2)
      Ecto.Changeset.put_change(changeset, :slug, unique_slug)
    else
      changeset
    end
  end

  defp slug_exists?(slug, nil) do
    Repo.exists?(from(a in Article, where: a.slug == ^slug))
  end

  defp slug_exists?(slug, exclude_id) do
    Repo.exists?(from(a in Article, where: a.slug == ^slug and a.id != ^exclude_id))
  end

  defp find_unique_slug(base_slug, exclude_id, n) do
    candidate = "#{base_slug}-#{n}"

    if slug_exists?(candidate, exclude_id) do
      find_unique_slug(base_slug, exclude_id, n + 1)
    else
      candidate
    end
  end

  @doc """
  Deletes an article.
  """
  @spec delete_article(Article.t()) :: {:ok, Article.t()} | {:error, Ecto.Changeset.t()}
  def delete_article(%Article{} = article) do
    s3_paths = Gallformers.ContentImages.collect_s3_paths_for_article(article.id)

    case Repo.delete(article) do
      {:ok, deleted} ->
        Gallformers.ContentImages.delete_collected_s3_paths(s3_paths)
        {:ok, deleted} |> broadcast(:article_deleted)

      error ->
        error
    end
  end

  @doc """
  Returns a changeset for tracking article changes.
  """
  @spec change_article(Article.t(), map()) :: Ecto.Changeset.t()
  def change_article(%Article{} = article, attrs \\ %{}) do
    Article.changeset(article, attrs)
  end

  @doc """
  Returns articles related to the given article by shared tags.

  Finds published articles that share at least one tag with the given article,
  excluding the article itself. Results are ordered by most recent first.

  ## Options

    * `:limit` - maximum number of articles to return (default: 5)

  """
  @spec list_related_articles(Article.t(), keyword()) :: [Article.t()]
  def list_related_articles(%Article{} = article, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    if article.tags == [] do
      []
    else
      tags = article.tags

      from(a in Article,
        where: a.id != ^article.id and a.is_published == true,
        where:
          fragment(
            "EXISTS (SELECT 1 FROM jsonb_array_elements_text(?::jsonb) AS t(value) WHERE t.value = ANY(?))",
            a.tags,
            type(^tags, {:array, :string})
          ),
        order_by: [desc: a.inserted_at],
        limit: ^limit
      )
      |> Repo.all()
    end
  end

  @doc """
  Returns all unique tags with their counts.

  Returns a list of maps: `[%{tag: "biology", count: 3}, ...]`

  ## Options

    * `:published_only` - if true, only counts tags from published articles (default: false)

  """
  @spec list_tags(keyword()) :: [%{tag: String.t(), count: integer()}]
  def list_tags(opts \\ []) do
    published_only = Keyword.get(opts, :published_only, false)

    query =
      if published_only do
        from(a in Article, where: a.is_published == true, select: a.tags)
      else
        from(a in Article, select: a.tags)
      end

    query
    |> Repo.all()
    |> Enum.flat_map(fn tags -> tags || [] end)
    |> Enum.frequencies()
    |> Enum.map(fn {tag, count} -> %{tag: tag, count: count} end)
    |> Enum.sort_by(& &1.tag)
  end

  defp broadcast({:ok, article}, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, "articles", {event, article})
    {:ok, article}
  end

  defp broadcast({:error, changeset}, _event) do
    {:error, changeset}
  end
end
