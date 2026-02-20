defmodule Gallformers.Wcvp.Matcher do
  @moduledoc """
  Three-pass name matching between gallformers species and WCVP data.

  Pass 1: Exact canonical name match ("Genus species")
  Pass 2: Fuzzy epithet matching (normalized Latin endings)
  Pass 3: Synonym lookup (gallformers name is a WCVP synonym)
  """

  @doc """
  Attempts to match a gallformers species name against WCVP data.

  Args:
    - gf_name: species name from gallformers (e.g., "Quercus alba")
    - accepted_by_name: %{"Quercus alba" => %Name{}, ...}
    - synonym_index: %{"old name" => "accepted_plant_name_id", ...}
    - accepted_by_id: %{"plant_name_id" => %Name{}, ...}

  Returns:
    - {:exact, %Name{}} — direct match
    - {:fuzzy, %Name{}} — matched via normalized epithet
    - {:synonym, %Name{}} — gallformers name is a WCVP synonym; returns the accepted name
    - {:no_match, closest_or_nil} — no match found
  """
  def match_name(gf_name, accepted_by_name, synonym_index, accepted_by_id) do
    with :no_match <- try_exact(gf_name, accepted_by_name),
         :no_match <- try_fuzzy(gf_name, accepted_by_name),
         :no_match <- try_synonym(gf_name, synonym_index, accepted_by_id) do
      closest = find_closest(gf_name, accepted_by_name)
      {:no_match, closest}
    end
  end

  @doc """
  Normalizes a Latin epithet for fuzzy comparison.
  Strips common ending variations so "wallichii" and "wallichianus" compare equal.
  """
  def normalize_epithet(epithet) do
    epithet
    |> String.downcase()
    |> strip_latin_endings()
  end

  # -- Pass 1: Exact --

  defp try_exact(name, accepted_by_name) do
    case Map.get(accepted_by_name, name) do
      nil -> :no_match
      wcvp_name -> {:exact, wcvp_name}
    end
  end

  # -- Pass 2: Fuzzy --

  defp try_fuzzy(name, accepted_by_name) do
    case split_canonical(name) do
      {genus, epithet} ->
        normalized = normalize_epithet(epithet)

        match =
          Enum.find(accepted_by_name, fn {_key, wcvp} ->
            wcvp.genus == genus and normalize_epithet(wcvp.species) == normalized
          end)

        case match do
          {_key, wcvp_name} -> {:fuzzy, wcvp_name}
          nil -> :no_match
        end

      :invalid ->
        :no_match
    end
  end

  # -- Pass 3: Synonym --

  defp try_synonym(name, synonym_index, accepted_by_id) do
    case Map.get(synonym_index, name) do
      nil ->
        :no_match

      accepted_id ->
        case Map.get(accepted_by_id, accepted_id) do
          nil -> :no_match
          accepted_name -> {:synonym, accepted_name}
        end
    end
  end

  # -- Closest match (for reporting) --

  defp find_closest(name, accepted_by_name) do
    with {genus, _epithet} <- split_canonical(name),
         {_key, wcvp_name} <-
           Enum.find(accepted_by_name, fn {_key, wcvp} -> wcvp.genus == genus end) do
      wcvp_name
    else
      _ -> nil
    end
  end

  # -- Helpers --

  defp split_canonical(name) do
    case String.split(name, " ", parts: 2) do
      [genus, epithet] when genus != "" and epithet != "" -> {genus, epithet}
      _ -> :invalid
    end
  end

  # Strips common Latin epithet ending variations to a shared root.
  # This handles the most common discrepancies between taxonomic authorities.
  @latin_endings ~w(ianus iana ianum ensis ense ii is e a um us)

  defp strip_latin_endings(epithet) do
    Enum.reduce_while(@latin_endings, epithet, fn ending, acc ->
      if String.ends_with?(acc, ending) and String.length(acc) > String.length(ending) + 2 do
        {:halt, String.trim_trailing(acc, ending)}
      else
        {:cont, acc}
      end
    end)
  end
end
