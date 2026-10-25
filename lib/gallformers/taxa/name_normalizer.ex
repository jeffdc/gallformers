defmodule Gallformers.Taxa.NameNormalizer do
  @moduledoc """
  The normalized form of a scientific name, under which import resolution
  matches names (`docs/import/producer-guide-background.md`, *What
  Gallformers does on import* step 2). Two names that normalize alike are the
  same name for resolution; nothing fuzzier (fuzzy matching joined different
  species).

    * Unicode compatibility forms are folded (NFKC: ligatures from OCR).
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
    |> String.split()
    |> drop_hybrid_markers()
    |> drop_subgenus()
    |> Enum.map_join(" ", &marker/1)
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
