defmodule GallformersWeb.ArticleHTML do
  @moduledoc """
  An article's page (design system, matter bc0d): the page header, the
  text in `prose`, related articles in the rail.
  """
  use GallformersWeb, :html

  embed_templates "article_html/*"

  # Updated on a later day than it was written.
  defp updated?(article),
    do: NaiveDateTime.to_date(article.updated_at) != NaiveDateTime.to_date(article.inserted_at)

  # Returns the date to display (published_at if available, otherwise inserted_at)
  defp display_date(article) do
    article.published_at || article.inserted_at
  end
end
