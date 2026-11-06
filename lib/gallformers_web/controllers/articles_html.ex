defmodule GallformersWeb.ArticlesHTML do
  @moduledoc """
  The Articles list (design system, matter bc0d): topic chips, the newest
  article featured, the rest as `article_card`s tinted by their first
  topic, and More to read.
  """
  use GallformersWeb, :html

  alias Gallformers.Articles.Article

  embed_templates "articles_html/*"

  # An article's first topic with a look of its own sets its card's icon and
  # tone; other articles get the plain card.
  @topic_looks %{
    "identification" => %{icon: "ph-magnifying-glass-plus", tone: :sky},
    "guide" => %{icon: "ph-compass", tone: :sky},
    "faq" => %{icon: "ph-question", tone: :autumn},
    "taxonomy" => %{icon: "ph-dna", tone: :autumn},
    "undescribed" => %{icon: "ph-detective", tone: :autumn},
    "meta" => %{icon: "ph-users-three", tone: :brand},
    "contributing" => %{icon: "ph-users-three", tone: :brand},
    "supporters" => %{icon: "ph-hand-heart", tone: :brand}
  }

  defp topic_look(%Article{tags: tags}),
    do: Enum.find_value(tags, %{icon: "ph-article", tone: :plain}, &@topic_looks[&1])

  defp card_meta(article), do: "#{article.author} · #{format_date(display_date(article))}"

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
    # Remove list markers (- item, * item, 1. item)
    |> String.replace(~r/^\s*(?:[-*+]|\d+\.)\s+/m, "")
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
