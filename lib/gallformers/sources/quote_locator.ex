defmodule Gallformers.Sources.QuoteLocator do
  @moduledoc """
  Finds a quote in a document item's text and returns where it is in the
  item's ORIGINAL text.

  A quote matches the way the import contract's validator accepts it
  (`normalize`, `dehyphenate` and `quote_in` in `priv/import/validate.py`):
  both texts are NFKC-normalised, soft hyphens are removed and every
  whitespace run becomes one space (with none at either end); if the quote is
  not found that way, both are also dehyphenated — a word character, `-`, a
  space and a word character lose the `-` and the space, so `"glob-\\nular"`
  reads `"globular"`. Keep this in step with `validate.py`.

  ## Spans

  A span is `{start, length}` in Unicode codepoints of the original text (the
  unit Python's string indices, Docling's `charspan` and PostgreSQL's
  `substr` use; not bytes, and not graphemes as `String.slice/3` counts).
  `slice/2` cuts it out.

  ## Mapping a match back to the original text

  The text is normalised one grapheme cluster at a time, and every character
  of the normalised text remembers the codepoint range of the original
  grapheme it came from:

    * NFKC of a grapheme may give several characters (`"ﬁ"` becomes `"f"`,
      `"i"`) or fewer (`"e"` plus a combining accent becomes `"é"`); each of
      them carries the whole grapheme's range.
    * A removed soft hyphen leaves nothing behind.
    * A collapsed whitespace run becomes one space carrying the range from
      the run's first original character to its last.
    * Dehyphenation drops the `-` and the space; the characters around them
      keep their own ranges.

  A match covering normalised characters `i..j` then spans the original text
  from the start of character `i`'s range to the end of character `j`'s, so
  everything that produced the match is inside the span, including a line
  break and hyphen the quote skipped. Because ranges are whole graphemes, a
  match that starts or ends inside a grapheme's expansion (the `"i"` of
  `"ﬁ"`) takes that whole grapheme.

  Normalising per grapheme gives the same text as normalising the whole
  string, because NFKC composition never reaches across a grapheme cluster
  boundary (combining marks are part of their base's cluster). The quote
  itself is normalised as a whole string, exactly as the validator does.

  When the quote occurs more than once, the first occurrence is returned.
  """

  @soft_hyphen 0x00AD

  @typedoc "`{start, length}` in codepoints of the original text."
  @type span :: {non_neg_integer(), non_neg_integer()}

  # A normalised character and the original codepoint range [from, to) it came from.
  @typep char_entry :: {char(), non_neg_integer(), non_neg_integer()}

  # Python's str.isspace(), which str.split() and the regex \s use.
  defguardp is_space(c)
            when c in 0x09..0x0D or c in 0x1C..0x20 or c in 0x2000..0x200A or
                   c in [0x85, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000]

  @doc """
  Locates `quote` in `item_text`.

  Returns `{:ok, {start, length}}`, the first occurrence's span in the
  original `item_text`, or `:error` when the quote is not there (or is
  blank).
  """
  @spec locate(String.t(), String.t()) :: {:ok, span()} | :error
  def locate(item_text, quote) when is_binary(item_text) and is_binary(quote) do
    text = normalized_entries(item_text)
    wanted = quote |> String.normalize(:nfkc) |> normalized_entries() |> Enum.map(&elem(&1, 0))

    cond do
      wanted == [] -> :error
      span = find(text, wanted) -> {:ok, span}
      span = find(dehyphenate(text), dehyphenate_chars(wanted)) -> {:ok, span}
      true -> :error
    end
  end

  @doc "The part of `text` a span covers, cut by codepoint."
  @spec slice(String.t(), span()) :: String.t()
  def slice(text, {start, length}) when is_binary(text) do
    text |> String.to_charlist() |> Enum.slice(start, length) |> List.to_string()
  end

  # -- normalisation ---------------------------------------------------------

  @spec normalized_entries(String.t()) :: [char_entry()]
  defp normalized_entries(text) do
    text
    |> nfkc_entries()
    |> Enum.reject(fn {c, _from, _to} -> c == @soft_hyphen end)
    |> collapse_whitespace()
  end

  defp nfkc_entries(text) do
    {entries, _offset} =
      text
      |> String.graphemes()
      |> Enum.flat_map_reduce(0, fn grapheme, offset ->
        next = offset + length(String.to_charlist(grapheme))

        normalised =
          grapheme |> String.normalize(:nfkc) |> String.to_charlist()

        {Enum.map(normalised, &{&1, offset, next}), next}
      end)

    entries
  end

  # Each whitespace run becomes one space spanning the run; runs at either
  # end are dropped (Python's " ".join(text.split())).
  defp collapse_whitespace(entries) do
    {out, _run} =
      Enum.reduce(entries, {[], nil}, fn
        {c, from, to}, {out, nil} when is_space(c) -> {out, {from, to}}
        {c, _from, to}, {out, {run_from, _}} when is_space(c) -> {out, {run_from, to}}
        entry, {[], _run} -> {[entry], nil}
        entry, {out, nil} -> {[entry | out], nil}
        entry, {out, {from, to}} -> {[entry, {?\s, from, to} | out], nil}
      end)

    Enum.reverse(out)
  end

  # re.sub(r"(\w)-\s+(\w)", r"\1\2", text) on normalised text, where a
  # whitespace run is already one space. Like re.sub, matches don't overlap:
  # the second word character is consumed with its match.
  defp dehyphenate(entries), do: dehyphenate(entries, [], &elem(&1, 0))

  defp dehyphenate_chars(chars), do: dehyphenate(chars, [], & &1)

  defp dehyphenate([a, hyphen, space, b | rest], acc, char) do
    if char.(hyphen) == ?- and char.(space) == ?\s and word?(char.(a)) and word?(char.(b)) do
      dehyphenate(rest, [b, a | acc], char)
    else
      dehyphenate([hyphen, space, b | rest], [a | acc], char)
    end
  end

  defp dehyphenate(rest, acc, _char), do: Enum.reverse(acc, rest)

  # Python's \w: alphanumeric (letters and numbers) or underscore.
  defp word?(c), do: Regex.match?(~r/\A[\p{L}\p{N}_]\z/u, <<c::utf8>>)

  # -- matching ----------------------------------------------------------------

  @spec find([char_entry()], [char()]) :: span() | nil
  defp find(entries, wanted) do
    haystack = entries |> Enum.map(&elem(&1, 0)) |> List.to_string()

    case :binary.match(haystack, List.to_string(wanted)) do
      {byte_pos, _bytes} ->
        first = haystack |> binary_part(0, byte_pos) |> String.to_charlist() |> length()
        last = first + length(wanted) - 1
        indexed = List.to_tuple(entries)
        {_, from, _} = elem(indexed, first)
        {_, _, to} = elem(indexed, last)
        {from, to - from}

      :nomatch ->
        nil
    end
  end
end
