defmodule Gallformers.Markdown do
  @moduledoc """
  Markdown processing with glossary term auto-linking.

  Converts markdown text to HTML and automatically links glossary terms
  to their definitions. Uses ETS caching for efficient repeated lookups.

  ## Usage

      iex> Gallformers.Markdown.render("A **cynipid** gall wasp")
      {:ok, "<p>A <strong><a href=\\"/glossary#cynipid\\" ...>cynipid</a></strong> gall wasp</p>"}

      iex> Gallformers.Markdown.render_unsafe("Some *markdown* text")
      "<p>Some <em>markdown</em> text</p>"
  """
  use Boundary, deps: [Gallformers.Glossaries], exports: :all

  alias Gallformers.Glossaries

  @ets_table :glossary_terms
  @cache_ttl_ms :timer.minutes(15)

  # GitHub-flavoured Markdown with hard line breaks and no smart quotes. Raw
  # HTML is let through (Source descriptions and articles use <details>, <b>
  # and links) and then sanitized with MDEx's default allowlist, which drops
  # scripts, event handlers and other unsafe markup.
  @mdex_options [
    extension: [table: true, strikethrough: true, autolink: true, tasklist: true],
    render: [hardbreaks: true, unsafe: true],
    sanitize: MDEx.Document.default_sanitize_options()
  ]

  @doc """
  Renders markdown to HTML with glossary term auto-linking.

  Always returns `{:ok, html}`: any input renders, its raw HTML sanitized.
  """
  @spec render(String.t()) :: {:ok, String.t()}
  def render(nil), do: {:ok, ""}
  def render(""), do: {:ok, ""}

  def render(markdown) when is_binary(markdown) do
    {:ok, linkify_glossary_terms(to_html(markdown))}
  end

  @doc """
  Renders markdown to HTML, unwrapping the result tuple.

  Convenience function that extracts the HTML from `render/1`.
  """
  @spec render!(String.t()) :: String.t()
  def render!(markdown) do
    {:ok, html} = render(markdown)
    html
  end

  @doc """
  Renders markdown to HTML without glossary linking.

  Returns raw HTML string (no tuple wrapper). Use for content that
  shouldn't have glossary terms linked.
  """
  @spec render_plain(String.t()) :: String.t()
  def render_plain(nil), do: ""
  def render_plain(""), do: ""

  def render_plain(markdown) when is_binary(markdown) do
    to_html(markdown)
  end

  @doc """
  Links glossary terms within an already-rendered HTML string.

  Useful when you want to add glossary linking to content that
  wasn't rendered through this module.
  """
  @spec linkify_glossary_terms(String.t()) :: String.t()
  def linkify_glossary_terms(html) when is_binary(html) do
    word_map = get_glossary_word_map()

    if map_size(word_map) == 0 do
      html
    else
      # Sort words by length (longest first) to avoid partial matches
      words =
        word_map
        |> Map.keys()
        |> Enum.sort_by(&String.length/1, :desc)

      Enum.reduce(words, html, fn word, acc ->
        linkify_word(acc, word, word_map)
      end)
    end
  end

  @doc """
  Refreshes the glossary term cache.

  Call this when glossary terms have been updated.
  """
  @spec refresh_cache() :: :ok
  def refresh_cache do
    ensure_ets_table()
    :ets.delete_all_objects(@ets_table)
    load_glossary_to_cache()
    :ok
  end

  @doc """
  Initializes the ETS table for glossary caching.

  Called automatically when needed, but can be called explicitly
  during application startup.
  """
  @spec init_cache() :: :ok
  def init_cache do
    ensure_ets_table()
    :ok
  end

  # Private functions

  defp to_html(markdown), do: MDEx.to_html!(markdown, @mdex_options)

  defp get_glossary_word_map do
    ensure_ets_table()

    case :ets.lookup(@ets_table, :word_map) do
      [{:word_map, word_map, timestamp}] ->
        if cache_expired?(timestamp) do
          load_glossary_to_cache()
        else
          word_map
        end

      [] ->
        load_glossary_to_cache()
    end
  end

  # Terms that are too common to auto-link (defined elsewhere or ubiquitous on site)
  @excluded_terms MapSet.new(["gall"])

  defp load_glossary_to_cache do
    word_map =
      Glossaries.list_glossary()
      |> Enum.reject(fn entry -> MapSet.member?(@excluded_terms, String.downcase(entry.word)) end)
      |> Enum.reduce(%{}, fn entry, acc ->
        # Store lowercase word mapping to original word for case-insensitive matching
        Map.put(acc, String.downcase(entry.word), entry.word)
      end)

    :ets.insert(@ets_table, {:word_map, word_map, System.monotonic_time(:millisecond)})
    word_map
  rescue
    # If database isn't available yet (e.g., during migrations), return empty map
    _ -> %{}
  end

  defp cache_expired?(timestamp) do
    System.monotonic_time(:millisecond) - timestamp > @cache_ttl_ms
  end

  defp ensure_ets_table do
    case :ets.whereis(@ets_table) do
      :undefined ->
        try do
          :ets.new(@ets_table, [:named_table, :public, :set])
        catch
          # Handle race condition: another process created the table between
          # our whereis check and the new call
          :error, :badarg -> :ok
        end

      _tid ->
        :ok
    end
  end

  defp linkify_word(html, word, word_map) do
    original_word = Map.get(word_map, word)
    anchor = String.downcase(original_word) |> URI.encode()

    # Build regex pattern for whole word matching (case-insensitive)
    # Avoid matching inside HTML tags or existing links
    pattern = ~r/(?<![<\/\w])(?<!\w)\b(#{Regex.escape(word)})\b(?![^<]*>)(?![^<]*<\/a>)/i

    Regex.replace(pattern, html, fn _full, match ->
      ~s(<a href="/glossary##{anchor}" class="glossary-link" title="View definition">#{match}</a>)
    end)
  end
end
