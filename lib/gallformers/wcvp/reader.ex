defmodule Gallformers.Wcvp.Reader do
  @moduledoc """
  Streams and parses WCVP CSV files (pipe-delimited).
  Provides filtered streams and index-building functions for reconciliation.
  """

  NimbleCSV.define(WcvpParser, separator: "|", escape: "\"")

  defmodule Name do
    @moduledoc false
    defstruct [
      :plant_name_id,
      :taxon_rank,
      :taxon_status,
      :family,
      :genus,
      :species,
      :species_hybrid,
      :infraspecific_rank,
      :infraspecies,
      :taxon_name,
      :taxon_authors,
      :accepted_plant_name_id,
      :parent_plant_name_id,
      :powo_id
    ]
  end

  defmodule Distribution do
    @moduledoc false
    defstruct [
      :plant_name_id,
      :continent_code_l1,
      :region_code_l2,
      :area_code_l3,
      :area,
      :introduced,
      :extinct,
      :location_doubtful
    ]
  end

  @name_fields %{
    "plant_name_id" => :plant_name_id,
    "taxon_rank" => :taxon_rank,
    "taxon_status" => :taxon_status,
    "family" => :family,
    "genus" => :genus,
    "species" => :species,
    "species_hybrid" => :species_hybrid,
    "infraspecific_rank" => :infraspecific_rank,
    "infraspecies" => :infraspecies,
    "taxon_name" => :taxon_name,
    "taxon_authors" => :taxon_authors,
    "accepted_plant_name_id" => :accepted_plant_name_id,
    "parent_plant_name_id" => :parent_plant_name_id,
    "powo_id" => :powo_id
  }

  @dist_fields %{
    "plant_name_id" => :plant_name_id,
    "continent_code_l1" => :continent_code_l1,
    "region_code_l2" => :region_code_l2,
    "area_code_l3" => :area_code_l3,
    "area" => :area,
    "introduced" => :introduced,
    "extinct" => :extinct,
    "location_doubtful" => :location_doubtful
  }

  @doc """
  Streams accepted names (Species, Variety, Subspecies, Form) from wcvp_names.csv.
  Skips Synonyms, Unplaced, and Invalid names.
  """
  def stream_accepted_names(path) do
    stream_names(path)
    |> Stream.filter(fn name -> name.taxon_status == "Accepted" end)
  end

  @doc """
  Streams synonym names for building a synonym lookup index.
  Returns names where taxon_status is "Synonym" and accepted_plant_name_id differs.
  """
  def stream_names_for_synonym_lookup(path) do
    stream_names(path)
    |> Stream.filter(fn name ->
      name.taxon_status == "Synonym" and
        name.accepted_plant_name_id not in [nil, "", name.plant_name_id]
    end)
  end

  @doc """
  Streams established (non-extinct, non-doubtful) distributions from wcvp_distributions.csv.
  Includes both native and introduced records. Use the `introduced` field on each
  struct to distinguish ("0" = native, "1" = introduced).
  """
  def stream_established_distributions(path) do
    stream_distributions(path)
    |> Stream.filter(fn dist ->
      dist.extinct == "0" and dist.location_doubtful == "0"
    end)
  end

  @doc """
  Builds a map of synonym canonical name -> accepted plant_name_id.
  Used for Pass 3 matching.
  """
  def build_synonym_index(path) do
    stream_names_for_synonym_lookup(path)
    |> Enum.reduce(%{}, fn name, acc ->
      Map.put(acc, name.taxon_name, name.accepted_plant_name_id)
    end)
  end

  @doc """
  Builds a map of accepted plant_name_id -> Name struct.
  Used to look up accepted names after synonym matching.
  """
  def build_accepted_name_lookup(path) do
    stream_accepted_names(path)
    |> Enum.reduce(%{}, fn name, acc ->
      Map.put(acc, name.plant_name_id, name)
    end)
  end

  @doc """
  Builds a map of plant_name_id -> list of TDWG L3 area codes.
  Only includes native, extant, non-doubtful distributions.
  """
  def build_distribution_index(distributions_path) do
    stream_distributions(distributions_path)
    |> Stream.filter(fn dist ->
      dist.introduced == "0" and dist.extinct == "0" and dist.location_doubtful == "0"
    end)
    |> Enum.reduce(%{}, fn dist, acc ->
      Map.update(acc, dist.plant_name_id, [dist.area_code_l3], fn codes ->
        [dist.area_code_l3 | codes]
      end)
    end)
  end

  # -- Private --

  defp stream_names(path) do
    {header, rows} = stream_csv(path)
    field_indices = build_field_indices(header, @name_fields)

    rows
    |> Stream.map(fn row -> row_to_struct(row, field_indices, %Name{}) end)
  end

  defp stream_distributions(path) do
    {header, rows} = stream_csv(path)
    field_indices = build_field_indices(header, @dist_fields)

    rows
    |> Stream.map(fn row -> row_to_struct(row, field_indices, %Distribution{}) end)
  end

  defp stream_csv(path) do
    [header_line | _] = File.stream!(path) |> Enum.take(1)
    header = header_line |> String.trim() |> String.split("|")

    rows =
      path
      |> File.stream!()
      |> Stream.drop(1)
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Stream.map(&String.split(&1, "|"))

    {header, rows}
  end

  defp build_field_indices(header, field_map) do
    header
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {col_name, idx}, acc ->
      case Map.get(field_map, col_name) do
        nil -> acc
        field -> Map.put(acc, field, idx)
      end
    end)
  end

  defp row_to_struct(row, field_indices, struct) do
    Enum.reduce(field_indices, struct, fn {field, idx}, acc ->
      value = Enum.at(row, idx, "")
      Map.put(acc, field, value)
    end)
  end
end
