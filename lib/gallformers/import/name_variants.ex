defmodule Gallformers.Import.NameVariants do
  @moduledoc """
  Spelling and ending variants of a Latin epithet, for the import's
  suggestions (queue triage rules F and G): a name the tree or WCVP holds in
  another spelling is offered to a curator, never resolved
  (`docs/import/producer-guide-background.md`, *What Gallformers does on
  import*: fuzzy matching may only suggest).

    * Endings: -us/-a/-um, -er/-ra/-rum, -is/-e (gender), -a/-ae, -i/-ii.
    * Spellings: ii/i inside the word ("vacciniifoliae", "vaccinifoliae"),
      and the ligatures as old Sources print them, æ as ae, a or e, œ as oe
      or e (`Gallformers.Taxa.NameNormalizer` already spells out æ and œ).

  `same_epithet?/2` is narrower: one epithet in another gender, or ii/i at
  the end, is the same epithet (rule C: a synonym that is the same name in
  another combination). A genitive is not its nominative ("nigrae" is not
  "nigra").
  """

  alias Gallformers.Taxa.NameNormalizer

  @ending_groups [~w(us a um), ~w(er ra rum), ~w(is e), ~w(a ae), ~w(i ii)]
  # Gender endings to the stem they share, longest first.
  @genders [
    {"rum", "r"},
    {"ra", "r"},
    {"er", "r"},
    {"um", ""},
    {"us", ""},
    {"a", ""},
    {"is", "i"}
  ]
  @markers ~w(var. subsp. ssp. f. forma subvar.)
  @min_stem 2

  @doc "The variants of `word` (normalized), not `word` itself."
  @spec variants(String.t()) :: [String.t()]
  def variants(word) when is_binary(word) do
    word = NameNormalizer.normalize(word)

    for inner <- spellings(word), v <- [inner | endings(inner)], v != word, uniq: true, do: v
  end

  defp spellings(word) do
    Enum.uniq([
      word,
      String.replace(word, "ii", "i"),
      String.replace(word, "ae", "a"),
      String.replace(word, "ae", "e"),
      String.replace(word, "ae", "oe"),
      String.replace(word, "oe", "ae"),
      String.replace(word, "oe", "e")
    ])
  end

  defp endings(word) do
    for group <- @ending_groups,
        suffix <- List.wrap(ending(word, group)),
        other <- group,
        other != suffix,
        do: String.replace_suffix(word, suffix, other)
  end

  # The longest ending of `group` that `word` has, leaving a stem. A word in
  # -ae or -oe does not end in -e.
  defp ending(word, group) do
    group
    |> Enum.sort_by(&(-String.length(&1)))
    |> Enum.find(fn suffix ->
      String.ends_with?(word, suffix) and
        String.length(word) - String.length(suffix) >= @min_stem and
        not (suffix == "e" and String.ends_with?(word, ["ae", "oe"]))
    end)
  end

  @doc "Whether two epithets (normalized) are one epithet, in another gender or with ii/i."
  @spec same_epithet?(String.t(), String.t()) :: boolean()
  def same_epithet?(a, b) when is_binary(a) and is_binary(b), do: stem(a) == stem(b)

  defp stem(word) do
    word = if String.ends_with?(word, "ii"), do: String.slice(word, 0..-2//1), else: word

    Enum.find_value(@genders, gender_e(word), fn {suffix, stem} ->
      if String.ends_with?(word, suffix) and
           String.length(word) - String.length(suffix) >= @min_stem,
         do: String.replace_suffix(word, suffix, stem)
    end)
  end

  # A neuter -e (breve) shares the stem of -is (brevis); -ae and -oe do not.
  defp gender_e(word) do
    if String.ends_with?(word, "e") and not String.ends_with?(word, ["ae", "oe"]),
      do: String.replace_suffix(word, "e", "i"),
      else: word
  end

  @doc """
  The epithet of a scientific name: its words after the genus, rank markers
  left out, joined and normalized ("Cynips quercus cornigera" is
  "quercuscornigera"); nil for a one-word name.
  """
  @spec epithet(String.t()) :: String.t() | nil
  def epithet(name) when is_binary(name) do
    case name |> NameNormalizer.normalize() |> String.split() do
      [_genus | [_ | _] = rest] ->
        rest |> Enum.reject(&(&1 in @markers)) |> Enum.join() |> String.replace("-", "")

      _ ->
        nil
    end
  end

  @doc "`name` with the ligatures æ and œ spelled out, keeping the case."
  @spec spell_ligatures(String.t()) :: String.t()
  def spell_ligatures(name) when is_binary(name) do
    String.replace(name, ["æ", "Æ", "œ", "Œ"], fn
      "æ" -> "ae"
      "Æ" -> "AE"
      "œ" -> "oe"
      "Œ" -> "OE"
    end)
  end

  @doc "The genus of a scientific name: its first word, normalized."
  @spec genus(String.t()) :: String.t() | nil
  def genus(name) when is_binary(name),
    do: name |> NameNormalizer.normalize() |> String.split() |> List.first()

  @doc "The Levenshtein distance between `a` and `b`."
  @spec edit_distance(String.t(), String.t()) :: non_neg_integer()
  def edit_distance(a, b) when is_binary(a) and is_binary(b) do
    b = String.graphemes(b)
    first = Enum.to_list(0..length(b))

    a
    |> String.graphemes()
    |> Enum.with_index(1)
    |> Enum.reduce(first, fn {ca, i}, prev -> row(ca, i, b, prev) end)
    |> List.last()
  end

  defp row(ca, i, b, [diag | above] = _prev) do
    {row, _diag, _left} =
      b
      |> Enum.zip(above)
      |> Enum.reduce({[i], diag, i}, fn {cb, up}, {acc, diag, left} ->
        cost = if ca == cb, do: 0, else: 1
        cell = Enum.min([left + 1, up + 1, diag + cost])
        {[cell | acc], up, cell}
      end)

    Enum.reverse(row)
  end
end
