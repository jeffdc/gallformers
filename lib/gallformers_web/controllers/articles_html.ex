defmodule GallformersWeb.ArticlesHTML do
  use GallformersWeb, :html

  alias Gallformers.Articles.Article

  embed_templates "articles_html/*"

  # Returns article description if available, otherwise generates a preview from content
  defp article_preview(%Article{} = article) do
    if article.description && article.description != "" do
      article.description
    else
      content_preview(article.content)
    end
  end

  defp content_preview(content) when is_binary(content) do
    content
    |> strip_markdown()
    |> String.slice(0, 200)
    |> String.trim()
    |> then(fn preview ->
      if String.length(content) > 200, do: preview <> "...", else: preview
    end)
  end

  defp content_preview(_), do: ""

  # Returns the date to display (published_at if available, otherwise inserted_at)
  defp display_date(article) do
    article.published_at || article.inserted_at
  end

  # Strip common markdown syntax for plain text preview
  defp strip_markdown(text) do
    text
    # Remove headings (# Header)
    |> String.replace(~r/^\#{1,6}\s+/m, "")
    # Remove bold (**text** or __text__)
    |> String.replace(~r/\*\*([^*]+)\*\*/, "\\1")
    |> String.replace(~r/__([^_]+)__/, "\\1")
    # Remove italic (*text* or _text_)
    |> String.replace(~r/(?<!\*)\*([^*]+)\*(?!\*)/, "\\1")
    |> String.replace(~r/(?<!_)_([^_]+)_(?!_)/, "\\1")
    # Remove links [text](url)
    |> String.replace(~r/\[([^\]]+)\]\([^)]+\)/, "\\1")
    # Remove images ![alt](url)
    |> String.replace(~r/!\[[^\]]*\]\([^)]+\)/, "")
    # Remove inline code `code`
    |> String.replace(~r/`([^`]+)`/, "\\1")
    # Remove blockquotes
    |> String.replace(~r/^>\s*/m, "")
    # Collapse multiple spaces/newlines
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
