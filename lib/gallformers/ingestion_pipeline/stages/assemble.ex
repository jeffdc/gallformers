defmodule Gallformers.IngestionPipeline.Stages.Assemble do
  @moduledoc """
  Assembles extracted gall records and metadata into a review-ready markdown
  document.
  """

  @behaviour Gallformers.IngestionPipeline.StageWorker

  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.Stages.LLMSupport
  alias Gallformers.IngestionPipeline.Storage
  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.SourceIngestion
  alias Gallformers.Species

  @impl true
  def stage_name, do: :assemble

  @impl true
  def perform_stage(%SourceIngestion{} = ingestion) do
    with {:ok, records_json} <-
           Storage.download_artifact(ingestion.id, :data_extract, "output.json"),
         {:ok, metadata_json} <- Storage.download_artifact(ingestion.id, :metadata, "output.json"),
         {:ok, records} <- decode_records(records_json),
         {:ok, metadata} <- decode_metadata(metadata_json),
         document <- build_document(metadata, records),
         {:ok, _artifact_path} <-
           Storage.upload_artifact(
             ingestion.id,
             :assemble,
             "output.md",
             document,
             "text/markdown"
           ),
         {:ok, updated_ingestion} <-
           Ingestions.transition_source_ingestion_workflow(ingestion, :assemble_succeeded),
         :ok <- Broadcaster.broadcast_stage_complete(ingestion.id, :assemble) do
      {:ok, updated_ingestion}
    end
  end

  defp decode_records(json) do
    case json |> LLMSupport.strip_fenced_json() |> Jason.decode() do
      {:ok, records} when is_list(records) -> {:ok, records}
      {:ok, _other} -> {:error, :invalid_data_extract_payload}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_metadata(json) do
    case json |> LLMSupport.strip_fenced_json() |> Jason.decode() do
      {:ok, metadata} when is_map(metadata) -> {:ok, metadata}
      {:ok, _other} -> {:error, :invalid_metadata_payload}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_document(metadata, records) do
    resolutions = build_species_resolutions(records)
    frontmatter = render_frontmatter(metadata)
    body = Enum.map_join(records, "\n\n", &render_record(&1, resolutions))

    "---\n" <> frontmatter <> "---\n\n" <> String.trim(body) <> "\n"
  end

  defp render_frontmatter(metadata) do
    [
      render_yaml_field("title", Map.get(metadata, "title")),
      render_yaml_field("authors", Map.get(metadata, "authors", [])),
      render_yaml_field("year", Map.get(metadata, "year")),
      render_yaml_field("doi", Map.get(metadata, "doi"))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp render_yaml_field(_key, nil), do: nil

  defp render_yaml_field(key, values) when is_list(values) do
    case Enum.reject(values, &is_nil/1) do
      [] ->
        "#{key}: []"

      cleaned_values ->
        ["#{key}:" | Enum.map(cleaned_values, &"  - #{yaml_scalar(&1)}")]
        |> Enum.join("\n")
    end
  end

  defp render_yaml_field(key, value), do: "#{key}: #{yaml_scalar(value)}"

  defp render_record(record, resolutions) do
    gall_name = species_name(record, "gall_species")
    host_name = species_name(record, "host_species")
    gall_resolution = fetch_species_resolution(resolutions, gall_name, "gall")
    host_resolution = fetch_species_resolution(resolutions, host_name, "plant")

    [
      "## #{display_name(gall_name, "Unnamed gall species")}",
      "",
      description_block(Map.get(record, "description")),
      "",
      traits_block(Map.get(record, "traits", %{})),
      "",
      "Host species: #{display_name(host_name, "Unknown host species")}",
      "Gall species resolution: #{resolution_note(gall_resolution)}",
      unresolved_comment(gall_resolution, gall_name),
      "Host species resolution: #{resolution_note(host_resolution)}",
      unresolved_comment(host_resolution, host_name),
      "Confidence: #{format_confidence(Map.get(record, "confidence"))}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp build_species_resolutions(records) do
    records
    |> Enum.flat_map(fn record ->
      [
        {"gall", species_name(record, "gall_species")},
        {"plant", species_name(record, "host_species")}
      ]
    end)
    |> Enum.reject(fn {_taxoncode, name} -> is_nil(name) end)
    |> Enum.uniq()
    |> Map.new(fn {taxoncode, name} ->
      {{taxoncode, name}, resolve_species(name, taxoncode)}
    end)
  end

  defp species_name(record, key) do
    record
    |> Map.get(key, %{})
    |> Map.get("name")
    |> normalize_name()
  end

  defp normalize_name(nil), do: nil

  defp normalize_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp fetch_species_resolution(_resolutions, nil, _taxoncode),
    do: %{status: :unresolved, matches: []}

  defp fetch_species_resolution(resolutions, name, taxoncode) do
    Map.fetch!(resolutions, {taxoncode, name})
  end

  defp resolve_species(nil, _taxoncode), do: %{status: :unresolved, matches: []}

  defp resolve_species(name, taxoncode) do
    matches =
      (direct_matches(name, taxoncode) ++ alias_matches(name, taxoncode))
      |> Enum.uniq_by(& &1.species_id)

    case matches do
      [%{species_id: species_id, species_name: species_name}] ->
        %{
          status: :resolved,
          species_id: species_id,
          species_name: species_name,
          matches: matches
        }

      _ ->
        %{status: :unresolved, matches: matches}
    end
  end

  defp direct_matches(name, taxoncode) do
    name
    |> Species.search_species_by_name(taxoncode, 5)
    |> Enum.map(fn match ->
      %{
        species_id: match.id,
        species_name: match.name,
        taxoncode: match.taxoncode,
        match_type: :name
      }
    end)
  end

  defp alias_matches(name, taxoncode) do
    name
    |> Species.find_species_with_alias()
    |> Enum.filter(&(&1.taxoncode == taxoncode))
    |> Enum.map(fn match ->
      %{
        species_id: match.species_id,
        species_name: match.species_name,
        taxoncode: match.taxoncode,
        match_type: {:alias, match.alias_type}
      }
    end)
  end

  defp description_block(input) when input in [nil, ""],
    do: "Description:\n\nNo description provided."

  defp description_block(description) do
    "Description:\n\n" <> String.trim(description)
  end

  defp traits_block(traits) when is_map(traits) do
    [
      "Traits:",
      "",
      "| trait name | original text | suggested value |",
      "| --- | --- | --- |"
      | trait_rows(traits)
    ]
    |> Enum.join("\n")
  end

  defp traits_block(_traits) do
    traits_block(%{})
  end

  defp trait_rows(traits) do
    case Enum.sort_by(traits, fn {name, _value} -> name end) do
      [] ->
        ["| none |  |  |"]

      sorted_traits ->
        Enum.map(sorted_traits, &trait_row/1)
    end
  end

  defp trait_row({trait_name, %{"original" => original, "suggested" => suggested}}) do
    [
      "| ",
      escape_markdown_cell(trait_name),
      " | ",
      escape_markdown_cell(original),
      " | ",
      escape_markdown_cell(Enum.join(List.wrap(suggested), ", ")),
      " |"
    ]
    |> IO.iodata_to_binary()
  end

  defp trait_row({trait_name, value}) do
    [
      "| ",
      escape_markdown_cell(trait_name),
      " |  | ",
      escape_markdown_cell(value),
      " |"
    ]
    |> IO.iodata_to_binary()
  end

  defp resolution_note(%{status: :resolved, species_id: species_id, species_name: species_name}) do
    "resolved as #{species_name} (species_id: #{species_id})"
  end

  defp resolution_note(%{matches: matches}) do
    "unresolved (#{length(matches)} matches)"
  end

  defp unresolved_comment(%{status: :resolved}, _name), do: nil
  defp unresolved_comment(_resolution, nil), do: nil
  defp unresolved_comment(_resolution, name), do: "<!-- UNRESOLVED: #{name} -->"

  defp display_name(nil, fallback), do: fallback
  defp display_name(name, _fallback), do: name

  defp format_confidence(confidence) when is_float(confidence),
    do: :erlang.float_to_binary(confidence, decimals: 2)

  defp format_confidence(confidence) when is_integer(confidence),
    do: Integer.to_string(confidence)

  defp format_confidence(_confidence), do: "unknown"

  defp escape_markdown_cell(nil), do: ""

  defp escape_markdown_cell(value) do
    value
    |> to_string()
    |> String.replace("|", "\\|")
    |> String.replace("\n", " ")
    |> String.trim()
  end

  defp yaml_scalar(value) when is_binary(value), do: Jason.encode!(value)
  defp yaml_scalar(value) when is_integer(value), do: Integer.to_string(value)
  defp yaml_scalar(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp yaml_scalar(value), do: Jason.encode!(value)
end
