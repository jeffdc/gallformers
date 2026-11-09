defmodule Gallformers.Markdown do
  @moduledoc """
  Markdown processing with glossary term auto-linking.

  Converts markdown text to HTML and automatically links glossary terms
  to their entries (`/glossary#word`), the first sentence of each
  definition in a tooltip (the `gf-tooltip` markup `UIComponents.tooltip/1`
  renders) on hover and keyboard focus: a plain link, since the dotted
  underline is `fact_ref`'s alone (matter `87a1`). Uses ETS caching for
  efficient repeated lookups.

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

  @earmark_options %Earmark.Options{
    breaks: true,
    gfm: true,
    smartypants: false
  }

  @doc """
  Renders markdown to HTML with glossary term auto-linking.

  Always returns `{:ok, html}`. Partial HTML is returned even if markdown
  has parsing errors (e.g., unsupported HTML tags like `<details>`).
  """
  @spec render(String.t()) :: {:ok, String.t()}
  def render(nil), do: {:ok, ""}
  def render(""), do: {:ok, ""}

  def render(markdown) when is_binary(markdown) do
    case Earmark.as_html(markdown, @earmark_options) do
      {:ok, html, _warnings} ->
        {:ok, linkify_glossary_terms(html)}

      {:error, html, _errors} ->
        # Return partial HTML even with errors (e.g., unsupported HTML tags like <details>)
        # This allows content with HTML elements to still render
        {:ok, linkify_glossary_terms(html)}
    end
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
    case Earmark.as_html(markdown, @earmark_options) do
      {:ok, html, _warnings} -> html
      {:error, html, _errors} -> html
    end
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
      # One pass, longest words first, so a tooltip's text is never linked.
      alternation =
        word_map
        |> Map.keys()
        |> Enum.sort_by(&String.length/1, :desc)
        |> Enum.map_join("|", &Regex.escape/1)

      # Whole words, not inside a tag or an existing link.
      pattern = ~r/(?<![<\/\w])(?<!\w)\b(#{alternation})\b(?![^<]*>)(?![^<]*<\/a>)/i
      # Ids of their own per render: one text can be on a page twice.
      prefix = "gl-#{System.unique_integer([:positive])}"
      counter = :counters.new(1, [])

      Regex.replace(pattern, html, fn _full, match ->
        :counters.add(counter, 1, 1)
        link(match, word_map[String.downcase(match)], "#{prefix}-#{:counters.get(counter, 1)}")
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
        # Lowercase word to its entry's word and first sentence, for
        # case-insensitive matching.
        Map.put(acc, String.downcase(entry.word), {entry.word, first_sentence(entry.definition)})
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

  # A glossary term: a link to its entry, its definition's first sentence
  # in a tooltip (`id` the tooltip's) when it has one.
  defp link(match, {word, definition}, id) do
    a = ~s(<a href="/glossary##{word |> String.downcase() |> URI.encode()}">#{match}</a>)

    if definition == "" do
      a
    else
      text = definition |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

      ~s(<span class="gf-tooltip"><span aria-describedby="#{id}">#{a}</span>) <>
        ~s(<span id="#{id}" role="tooltip" class="gf-tooltip-text">#{text}</span></span>)
    end
  end

  defp first_sentence(text) when is_binary(text) do
    case String.split(String.trim(text), ~r/(?<=\.)\s/, parts: 2) do
      [sentence | _] -> String.trim(sentence)
      [] -> ""
    end
  end

  defp first_sentence(_text), do: ""
end
