defmodule Gallformers.Wcvp.Tdwg do
  @moduledoc """
  Maps TDWG (WGSRPD) Level 3 botanical region codes to gallformers place codes.
  Loads from a static JSON mapping file.
  """

  @mapping_file "repo/data/tdwg_to_places.json"

  @doc """
  Loads the TDWG mapping from the default JSON file.
  Returns the parsed lookup map.
  """
  def load do
    Application.app_dir(:gallformers, Path.join("priv", @mapping_file))
    |> File.read!()
    |> Jason.decode!()
    |> build_lookup()
  end

  @doc """
  Builds a lookup map from a parsed JSON mapping list.
  Returns %{"TDWG_CODE" => [%{code: "XX-YY", precision: "exact"}, ...]}.
  """
  def build_lookup(mapping) when is_list(mapping) do
    Map.new(mapping, fn entry ->
      places =
        Enum.map(entry["places"], fn p ->
          %{code: p["code"], precision: p["precision"]}
        end)

      {entry["tdwg_code"], places}
    end)
  end

  @doc """
  Converts a list of TDWG L3 codes to gallformers place entries.
  Unknown TDWG codes are silently skipped.
  Returns a flat list of %{code, precision} maps.
  """
  def convert_tdwg_codes(tdwg_codes, lookup) do
    tdwg_codes
    |> Enum.flat_map(fn code -> Map.get(lookup, code, []) end)
    |> Enum.uniq_by(& &1.code)
  end

  @doc """
  Like convert_tdwg_codes/2 but also returns unknown TDWG codes.
  Returns {place_entries, unknown_codes}.
  """
  def convert_tdwg_codes_with_warnings(tdwg_codes, lookup) do
    {known, unknown} = Enum.split_with(tdwg_codes, &Map.has_key?(lookup, &1))

    places =
      known
      |> Enum.flat_map(fn code -> Map.get(lookup, code, []) end)
      |> Enum.uniq_by(& &1.code)

    {places, unknown}
  end

  @doc """
  Returns true if a place code is in the US or Canada.
  Used to split reports into US/CA priority vs rest-of-hemisphere.
  """
  def us_canada_code?(code) do
    String.starts_with?(code, "US-") or String.starts_with?(code, "CA-") or
      code in ["US", "CA"]
  end
end
