defmodule GallformersWeb.Helpers do
  @moduledoc """
  View helper functions for the Gallformers application.

  These helpers are automatically imported into all views and LiveViews
  via `GallformersWeb.html_helpers/0`.
  """

  @doc """
  Formats an integer with thousand separators (commas).

  ## Examples

      iex> format_number(1234)
      "1,234"

      iex> format_number(1234567)
      "1,234,567"

      iex> format_number(42)
      "42"
  """
  def format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  def format_number(num), do: to_string(num)

  @doc """
  The " ·" that follows the `index`-th of `items` in an inline list that
  wraps, or nil after the last. Put it inside each item's `whitespace-nowrap`
  span so a wrapped line never starts with a separator.

      iex> list_separator(0, [:a, :b])
      " ·"

      iex> list_separator(1, [:a, :b])
      nil
  """
  @spec list_separator(non_neg_integer(), list()) :: String.t() | nil
  def list_separator(index, items), do: if(index < length(items) - 1, do: " ·")

  @doc """
  Returns true if the given string is a valid HTTP(S) URL safe for use in `<.link href={}>`.

  Returns false for nil, empty strings, and strings without a valid http/https scheme,
  preventing Phoenix `<.link>` from crashing on malformed URLs.
  """
  def valid_url?(nil), do: false
  def valid_url?(""), do: false

  def valid_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        true

      _ ->
        false
    end
  end

  def valid_url?(_), do: false

  @doc """
  How long ago `at` was, in a few words, as of `now` (both UTC).

      iex> time_ago(~N[2026-11-06 12:00:00], ~N[2026-11-06 12:00:30])
      "just now"

      iex> time_ago(~N[2026-11-06 11:15:00], ~N[2026-11-06 12:00:00])
      "45 min ago"

      iex> time_ago(~N[2026-11-06 07:00:00], ~N[2026-11-06 12:00:00])
      "5 h ago"

      iex> time_ago(~N[2026-11-05 09:00:00], ~N[2026-11-06 12:00:00])
      "yesterday"

      iex> time_ago(~N[2026-11-01 12:00:00], ~N[2026-11-06 12:00:00])
      "5 days ago"
  """
  @spec time_ago(NaiveDateTime.t() | DateTime.t(), NaiveDateTime.t()) :: String.t()
  def time_ago(at, now \\ NaiveDateTime.utc_now())
  def time_ago(%DateTime{} = at, now), do: time_ago(DateTime.to_naive(at), now)

  def time_ago(%NaiveDateTime{} = at, now) do
    minutes = div(NaiveDateTime.diff(now, at), 60)
    days = div(minutes, 60 * 24)

    cond do
      minutes < 1 -> "just now"
      minutes < 60 -> "#{minutes} min ago"
      minutes < 60 * 24 -> "#{div(minutes, 60)} h ago"
      days == 1 -> "yesterday"
      true -> "#{days} days ago"
    end
  end
end
