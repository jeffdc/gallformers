defmodule Gallformers.Galls.Summary do
  @moduledoc """
  Generates human-readable summaries of gall characteristics.

  Used for:
  - ID results page cards (when gall has no image)
  - SEO meta descriptions on gall detail pages
  - Image alt text (future)
  """

  @type mode :: :short | :medium | :full

  # Form values that map to different nouns
  @non_gall_forms ["non-gall"]
  @erineum_forms ["erineum"]

  @doc """
  Generate a summary from gall filter data.

  ## Options
    - `:mode` - `:short` (ID cards, ~50 chars), `:medium` (~100 chars, default), `:full` (SEO, ~150 chars)

  ## Examples

      iex> Galls.Summary.generate(%{shapes: ["spherical"], colors: ["red"], plant_parts: ["leaf"]})
      "A spherical, red gall found on the leaf."

      iex> Galls.Summary.generate(%{forms: ["non-gall"], colors: ["red"]})
      "A red structure."
  """
  @spec generate(map() | nil, keyword()) :: String.t()
  def generate(filters, opts \\ [])
  def generate(nil, _opts), do: "A gall."

  def generate(filters, opts) when is_map(filters) do
    mode = Keyword.get(opts, :mode, :medium)
    form_noun = determine_form_noun(filters)

    descriptors = build_descriptors(filters, mode)
    location_phrase = build_location_phrase(filters)
    season_phrase = build_season_phrase(filters, mode)
    detachable_phrase = build_detachable_phrase(filters, mode)
    technical_phrase = build_technical_phrase(filters, mode)

    base = build_base_sentence(descriptors, form_noun, location_phrase, season_phrase, mode)

    [base, technical_phrase, detachable_phrase]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @doc """
  Generate summary suitable for SEO meta description.
  Includes species name prefix, stays under 160 chars.

  ## Examples

      iex> Galls.Summary.for_seo("Andricus quercuscalifornicus", %{shapes: ["spherical"]})
      "Andricus quercuscalifornicus - A spherical gall."
  """
  @spec for_seo(String.t(), map() | nil) :: String.t()
  def for_seo(species_name, nil) do
    "#{species_name} - A gall species documented on Gallformers."
  end

  def for_seo(species_name, filters) when map_size(filters) == 0 do
    "#{species_name} - A gall species documented on Gallformers."
  end

  def for_seo(species_name, filters) do
    prefix = "#{species_name} - "
    max_summary_length = 160 - String.length(prefix)

    summary = generate(filters, mode: :medium)

    if String.length(summary) <= max_summary_length do
      prefix <> summary
    else
      # Try short mode
      short_summary = generate(filters, mode: :short)

      if String.length(short_summary) <= max_summary_length do
        prefix <> short_summary
      else
        # Truncate with ellipsis
        truncated = String.slice(short_summary, 0, max_summary_length - 3) <> "..."
        prefix <> truncated
      end
    end
  end

  @doc """
  Converts database filter format to summary generator format.

  Database format (from Galls.get_gall_filter_values/1):
    %{colors: [%{id: 1, field: "red"}], shapes: [...], ...}

  Summary format:
    %{colors: ["red"], shapes: [...], detachable: "detachable", ...}

  ## Parameters
    - `db_filters` - Map from Galls.get_gall_filter_values/1
    - `detachable` - Integer from gall.detachable (0=unknown, 1=integral, 2=detachable, 3=both)
  """
  @spec from_db_filters(map() | nil, integer()) :: map()
  def from_db_filters(nil, _detachable), do: %{}

  def from_db_filters(db_filters, detachable) do
    %{
      shapes: extract_field_values(db_filters[:shapes]),
      colors: extract_field_values(db_filters[:colors]),
      textures: extract_field_values(db_filters[:textures]),
      plant_parts: extract_field_values(db_filters[:plant_parts]),
      seasons: extract_field_values(db_filters[:seasons]),
      alignments: extract_field_values(db_filters[:alignments]),
      walls: extract_field_values(db_filters[:walls]),
      cells: extract_field_values(db_filters[:cells]),
      forms: extract_field_values(db_filters[:forms]),
      detachable: detachable_to_string(detachable)
    }
  end

  # Private functions

  defp extract_field_values(nil), do: []
  defp extract_field_values(list), do: Enum.map(list, & &1.field)

  # Handle integers (legacy V1 data)
  defp detachable_to_string(0), do: nil
  defp detachable_to_string(1), do: "integral"
  defp detachable_to_string(2), do: "detachable"
  defp detachable_to_string(3), do: "both"
  # Handle strings (V2 data) - pass through unchanged
  defp detachable_to_string(s) when is_binary(s), do: s
  defp detachable_to_string(_), do: nil

  defp determine_form_noun(filters) do
    forms = get_values(filters, :forms)

    cond do
      Enum.any?(forms, &(&1 in @non_gall_forms)) -> "structure"
      Enum.any?(forms, &(&1 in @erineum_forms)) -> "erineum"
      true -> "gall"
    end
  end

  defp build_descriptors(filters, mode) do
    # Attributes to include based on mode
    attrs =
      case mode do
        :short -> [:shapes, :colors]
        :medium -> [:shapes, :colors, :textures]
        :full -> [:shapes, :colors, :textures, :alignments]
      end

    # Each attribute is formatted with "/" for multiple values,
    # then attributes are joined with ", "
    attrs
    |> Enum.map(fn attr -> format_multi_value(get_values(filters, attr)) end)
    |> Enum.reject(&is_nil/1)
  end

  defp build_location_phrase(filters) do
    case format_multi_value(get_values(filters, :plant_parts)) do
      nil -> nil
      location -> "found on the #{location}"
    end
  end

  defp build_season_phrase(_filters, :short), do: nil

  defp build_season_phrase(filters, _mode) do
    case format_multi_value(get_values(filters, :seasons)) do
      nil -> nil
      season -> "in #{season}"
    end
  end

  defp build_detachable_phrase(_filters, :short), do: nil

  defp build_detachable_phrase(filters, _mode) do
    case Map.get(filters, :detachable) do
      "detachable" -> "Detachable."
      "integral" -> "Integral to host."
      "both" -> "May be detachable or integral."
      _ -> nil
    end
  end

  defp build_technical_phrase(_filters, mode) when mode in [:short, :medium], do: nil

  defp build_technical_phrase(filters, :full) do
    cells = format_multi_value(get_values(filters, :cells))
    walls = format_multi_value(get_values(filters, :walls))

    case {cells, walls} do
      {nil, nil} -> nil
      {cells, nil} -> "#{String.capitalize(cells)}."
      {nil, walls} -> "With #{walls} walls."
      {cells, walls} -> "#{String.capitalize(cells)} with #{walls} walls."
    end
  end

  defp build_base_sentence(descriptors, form_noun, location_phrase, season_phrase, mode) do
    descriptor_str = format_descriptors(descriptors)

    parts =
      [descriptor_str, form_noun]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    # For short mode, simplify location phrase to "on the" instead of "found on the"
    location_part =
      if mode == :short && location_phrase do
        String.replace(location_phrase, "found on the", "on the")
      else
        location_phrase
      end

    sentence_parts =
      [parts, location_part, season_phrase]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    article = select_article(sentence_parts)
    "#{article} #{sentence_parts}."
  end

  defp format_descriptors([]), do: nil

  defp format_descriptors(descriptors) do
    descriptors
    |> Enum.join(", ")
  end

  defp select_article(text) do
    first_char = text |> String.trim() |> String.first() |> String.downcase()

    if first_char in ["a", "e", "i", "o", "u"] do
      "An"
    else
      "A"
    end
  end

  defp get_values(filters, key) do
    filters
    |> Map.get(key, [])
    |> List.wrap()
    |> Enum.reject(&(&1 == "" || is_nil(&1)))
  end

  defp format_multi_value([]), do: nil

  defp format_multi_value(values) when length(values) > 3 do
    values
    |> Enum.take(3)
    |> Enum.join("/")
    |> Kernel.<>("/...")
  end

  defp format_multi_value(values) do
    Enum.join(values, "/")
  end
end
