defmodule Gallformers.Taxa.NameNormalizer do
  @moduledoc """
  The normalized form of a scientific name, under which import resolution
  matches names (`docs/import/producer-guide-background.md`, *What
  Gallformers does on import* step 2). Two names that normalize alike are the
  same name for resolution; nothing fuzzier (fuzzy matching joined different
  species).

    * Unicode compatibility forms are folded (NFKC: ligatures from OCR).
    * "æ" and "œ" are spelled out ("imbrecariæ" is "imbrecariae"), as old
      Sources print them; NFKC leaves them alone.
    * Case is ignored ("ANDRICUS RILEYI" from small caps).
    * Whitespace is collapsed.
    * The hybrid sign is dropped: "×", and a standalone "x" after the first
      word ("Quercus × bebbiana", "Quercus ×bebbiana", "Quercus x bebbiana").
    * "var" and "var." are one marker.
    * A subgenus in parentheses between the genus and the epithet is dropped
      ("Andricus (Callirhytis) foo" is "Andricus foo"). A name that is only
      "Genus (Subgenus)" keeps it.
  """

  @doc "Returns the normalized form of `name`."
  @spec normalize(String.t()) :: String.t()
  def normalize(name) when is_binary(name) do
    name
    |> String.normalize(:nfkc)
    |> String.replace("×", " ")
    |> String.downcase()
    |> String.replace(["æ", "œ"], fn
      "æ" -> "ae"
      "œ" -> "oe"
    end)
    |> String.split()
    |> drop_hybrid_markers()
    |> drop_subgenus()
    |> Enum.map_join(" ", &marker/1)
  end

  @doc """
  The normalized form of an authorship ("(Ashmead, 1881)"), under which two
  Sources' authorships of a name are the same (`f923`): case, spacing,
  punctuation other than parentheses, and "&" or "and" are ignored; the
  authors, the year and the parentheses (the name was first described in
  another genus) count. Nil or blank is `""`.
  """
  @spec normalize_authorship(String.t() | nil) :: String.t()
  def normalize_authorship(nil), do: ""

  def normalize_authorship(authorship) when is_binary(authorship) do
    authorship
    |> String.normalize(:nfkc)
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}()\s]+/u, " ")
    |> String.replace(~r/\(/u, " ( ")
    |> String.replace(~r/\)/u, " ) ")
    |> String.split()
    |> Enum.reject(&(&1 == "and"))
    |> Enum.join(" ")
    |> String.replace("( ", "(")
    |> String.replace(" )", ")")
  end

  defp drop_hybrid_markers([first | rest]), do: [first | Enum.reject(rest, &(&1 == "x"))]
  defp drop_hybrid_markers([]), do: []

  defp drop_subgenus([genus, "(" <> _ = subgenus, next | rest]) do
    if String.ends_with?(subgenus, ")"),
      do: [genus, next | rest],
      else: [genus, subgenus, next | rest]
  end

  defp drop_subgenus(words), do: words

  defp marker("var"), do: "var."
  defp marker(word), do: word
end
