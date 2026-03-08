defmodule GallformersWeb.ArticleHTML do
  use GallformersWeb, :html

  embed_templates "article_html/*"

  # Returns the date to display (published_at if available, otherwise inserted_at)
  defp display_date(article) do
    article.published_at || article.inserted_at
  end
end
