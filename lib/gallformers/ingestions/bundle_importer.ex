defmodule Gallformers.Ingestions.BundleImporter do
  @moduledoc """
  Imports an extracted Python-pipeline bundle directory into a persisted
  `Gallformers.Ingestions.SourceIngestion` plus per-record
  `SourceIngestionSpecies` rows, and uploads relevant artifacts to S3.

  The bundle directory is expected to contain at least:

    * `review_artifact.json` — the structured paper-level + per-gall extraction
      output produced by the Python pipeline.
    * `source.pdf` — the original PDF.

  Stage-1 behavior:

    * Skips dedup/normalization signal fields entirely.
    * Records `status="needs_review"`, `processing_stage="review"`.
    * Stores the full raw per-record map in `raw_extraction` for Stage-2 work.
    * Uploads the PDF and review artifact under the `:upload` stage. S3 upload
      failures are logged best-effort; the DB records are returned regardless.
  """

  require Logger

  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.SourceIngestion
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Species
  alias Gallformers.Storage.SourceArtifacts

  @review_artifact_filename "review_artifact.json"
  @source_pdf_filename "source.pdf"
  @artifact_stage :upload

  @doc """
  Imports a bundle directory and returns the created `SourceIngestion`.

  Options:

    * `:uploaded_by_id` (required) — user id to attribute as uploader.
  """
  @spec import_bundle(Path.t(), keyword()) ::
          {:ok, SourceIngestion.t()} | {:error, term()}
  def import_bundle(bundle_dir, opts \\ []) do
    uploaded_by_id = Keyword.get(opts, :uploaded_by_id)

    with {:ok, review_artifact} <- read_review_artifact(bundle_dir),
         {:ok, pdf_binary} <- read_source_pdf(bundle_dir),
         {:ok, ingestion} <- insert_records(review_artifact, uploaded_by_id) do
      upload_artifacts(ingestion.id, pdf_binary, review_artifact)
      {:ok, ingestion}
    end
  end

  @doc """
  Builds a `SourceIngestion` attrs map from the paper-level fields of a
  decoded `review_artifact.json` map.
  """
  @spec extract_paper_attrs(map()) :: map()
  def extract_paper_attrs(review_artifact) when is_map(review_artifact) do
    source = Map.get(review_artifact, "source", %{})
    metadata = Map.get(review_artifact, "document_metadata", %{})

    %{
      input_type: "pdf",
      status: "needs_review",
      processing_stage: "review",
      raw_input_sha256: Map.get(source, "pdf_sha256"),
      preprocessed_text_sha256: Map.get(source, "source_text_sha256"),
      title: unwrap_value(Map.get(metadata, "title")),
      authors: unwrap_authors(Map.get(metadata, "authors")),
      publication_year: parse_year(unwrap_value(Map.get(metadata, "year"))),
      doi: unwrap_value(Map.get(metadata, "doi"))
    }
  end

  @doc """
  Builds a `SourceIngestionSpecies` attrs map from a single `gall_records[]`
  entry plus its 0-based position.

  Schema-1.1.0 bundles include a top-level `generation` per record
  (`"agamic" | "sexgen" | "unspecified"`); the suffix is appended to
  `extracted_name` (`"X (agamic)"`, `"X (sexgen)"`) to match the gallformers
  species-name convention. Schema-1.0.0 / missing `generation` defaults to
  `"unspecified"` and the bare name is kept.
  """
  @spec extract_species_attrs(map(), non_neg_integer()) :: map()
  def extract_species_attrs(record, position) when is_map(record) and is_integer(position) do
    gall_maker = Map.get(record, "gall_maker", %{})
    scientific_name = unwrap_value(Map.get(gall_maker, "scientific_name"))
    authority = unwrap_value(Map.get(gall_maker, "authority"))
    generation = read_generation(record)
    extracted_name = apply_generation_suffix(scientific_name, generation)

    description_prose =
      case unwrap_value(Map.get(record, "description")) do
        nil -> ""
        value when is_binary(value) -> value
      end

    evidence_prose = build_evidence_prose(Map.get(record, "evidence_prose"))

    %{
      position: position,
      status: "pending",
      extracted_name: extracted_name,
      extracted_authority: authority,
      description_prose: description_prose,
      evidence_prose: evidence_prose,
      raw_extraction: record,
      extraction_payload: build_extraction_payload(record)
    }
  end

  defp read_generation(record) do
    case Map.get(record, "generation") do
      "agamic" -> "agamic"
      "sexgen" -> "sexgen"
      _ -> "unspecified"
    end
  end

  defp apply_generation_suffix(nil, _generation), do: nil
  defp apply_generation_suffix("", _generation), do: nil
  defp apply_generation_suffix(name, "agamic"), do: "#{name} (agamic)"
  defp apply_generation_suffix(name, "sexgen"), do: "#{name} (sexgen)"
  defp apply_generation_suffix(name, _), do: name

  # Schema-1.3.0 evidence_prose is a list of paragraph maps; normalize to a
  # plain list with string-keyed `span_id` / `page` / `text` fields.
  # Returns nil when the list is missing or empty so the DB column stays null.
  defp build_evidence_prose(paragraphs) when is_list(paragraphs) do
    cleaned =
      paragraphs
      |> Enum.map(&normalize_evidence_paragraph/1)
      |> Enum.reject(&is_nil/1)

    case cleaned do
      [] -> nil
      list -> list
    end
  end

  defp build_evidence_prose(_), do: nil

  defp normalize_evidence_paragraph(%{"text" => text} = paragraph)
       when is_binary(text) and text != "" do
    %{
      "span_id" => Map.get(paragraph, "span_id"),
      "page" => Map.get(paragraph, "page"),
      "text" => text
    }
  end

  defp normalize_evidence_paragraph(_), do: nil

  # --- Internals ---

  defp read_review_artifact(bundle_dir) do
    path = Path.join(bundle_dir, @review_artifact_filename)

    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, reason} -> {:error, {:invalid_json, reason}}
        end

      {:error, :enoent} ->
        {:error, {:missing_file, @review_artifact_filename}}

      {:error, reason} ->
        {:error, {:read_failed, @review_artifact_filename, reason}}
    end
  end

  defp read_source_pdf(bundle_dir) do
    path = Path.join(bundle_dir, @source_pdf_filename)

    case File.read(path) do
      {:ok, binary} -> {:ok, binary}
      {:error, :enoent} -> {:error, {:missing_file, @source_pdf_filename}}
      {:error, reason} -> {:error, {:read_failed, @source_pdf_filename, reason}}
    end
  end

  defp insert_records(review_artifact, uploaded_by_id) do
    paper_attrs =
      review_artifact
      |> extract_paper_attrs()
      |> Map.put(:uploaded_by_id, uploaded_by_id)
      |> maybe_attach_existing_source()

    gall_records = Map.get(review_artifact, "gall_records", [])

    Repo.transaction(fn ->
      case Ingestions.create_source_ingestion(paper_attrs) do
        {:ok, ingestion} ->
          insert_species_entries(ingestion, gall_records)
          ingestion

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp insert_species_entries(ingestion, gall_records) do
    gall_records
    |> Enum.with_index()
    |> Enum.each(fn {record, position} ->
      attrs =
        record
        |> extract_species_attrs(position)
        |> Map.put(:source_ingestion_id, ingestion.id)
        |> maybe_attach_existing_species()

      case Ingestions.create_source_ingestion_species(attrs) do
        {:ok, _entry} -> :ok
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp maybe_attach_existing_source(%{title: title} = attrs)
       when is_binary(title) and title != "" do
    case Sources.get_source_by_title(title) do
      nil -> attrs
      %{id: id} -> Map.put(attrs, :source_id, id)
    end
  end

  defp maybe_attach_existing_source(attrs), do: attrs

  defp maybe_attach_existing_species(%{extracted_name: name} = attrs)
       when is_binary(name) and name != "" do
    case find_exact_gall(name) do
      nil -> attrs
      match -> Map.merge(attrs, %{species_id: match.id, status: "mapped"})
    end
  end

  defp maybe_attach_existing_species(attrs), do: attrs

  # The bundle's `generation` field has already been baked into
  # `extracted_name` (e.g. "Druon fullawayi (agamic)"), matching the
  # gallformers species-name convention. Plain case-insensitive exact match
  # is sufficient — no ambiguity to resolve. For `unspecified` (bare) names,
  # only bare DB entries will match; anything else stays unresolved for the
  # reviewer to pick.
  defp find_exact_gall(name) do
    name_downcased = name |> String.trim() |> String.downcase()

    name
    |> Species.search_species_by_name("gall", 5)
    |> Enum.find(&(String.downcase(&1.name) == name_downcased))
  end

  defp upload_artifacts(ingestion_id, pdf_binary, review_artifact) do
    json_binary = Jason.encode!(review_artifact)

    upload_one(ingestion_id, @source_pdf_filename, pdf_binary, "application/pdf")
    upload_one(ingestion_id, @review_artifact_filename, json_binary, "application/json")
  end

  defp upload_one(ingestion_id, filename, content, content_type) do
    case SourceArtifacts.upload_private_artifact(
           ingestion_id,
           @artifact_stage,
           filename,
           content,
           content_type
         ) do
      {:ok, path} ->
        {:ok, path}

      {:error, reason} ->
        Logger.warning(
          "BundleImporter: failed to upload #{filename} for ingestion " <>
            "#{ingestion_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp build_extraction_payload(record) do
    gall_maker = Map.get(record, "gall_maker", %{})
    taxonomy = Map.get(gall_maker, "taxonomy", %{})
    hosts = Map.get(record, "hosts", []) || []
    traits = Map.get(record, "gall_traits", %{}) || %{}
    description = Map.get(record, "description")

    %{
      gall_species: %{
        name: unwrap_value(Map.get(gall_maker, "scientific_name")),
        authority: unwrap_value(Map.get(gall_maker, "authority")),
        family: unwrap_value(Map.get(taxonomy, "family")),
        order: unwrap_value(Map.get(taxonomy, "order"))
      },
      hosts: Enum.map(hosts, &build_host/1),
      aliases: build_aliases(Map.get(gall_maker, "aliases", [])),
      traits: build_traits(traits),
      description_evidence: build_description_evidence(description),
      location: unwrap_value(Map.get(record, "location"))
    }
  end

  defp build_host(host) when is_map(host) do
    taxonomy = Map.get(host, "taxonomy", %{}) || %{}

    %{
      name: unwrap_value(Map.get(host, "scientific_name")),
      authority: unwrap_value(Map.get(host, "authority")),
      family: unwrap_value(Map.get(taxonomy, "family")),
      order: unwrap_value(Map.get(taxonomy, "order"))
    }
  end

  @trait_fields ~w(shape color texture walls cells alignment plant_part form season)

  defp build_traits(traits) when is_map(traits) do
    base =
      @trait_fields
      |> Enum.map(fn name -> {String.to_atom(name), build_trait_value(Map.get(traits, name))} end)
      |> Map.new()

    Map.put(base, :detachable, unwrap_value(Map.get(traits, "detachable")))
  end

  defp build_traits(_), do: %{detachable: nil}

  defp build_trait_value(nil), do: %{original: nil, suggested: []}

  defp build_trait_value(value) when is_map(value) do
    %{
      original: Map.get(value, "original"),
      suggested: Map.get(value, "suggested", []) |> List.wrap()
    }
  end

  defp build_aliases(nil), do: []

  defp build_aliases(aliases) when is_list(aliases) do
    aliases
    |> Enum.map(&unwrap_value/1)
    |> Enum.reject(&is_nil/1)
  end

  defp build_description_evidence(nil), do: []

  defp build_description_evidence(description) when is_map(description) do
    description
    |> Map.get("evidence", [])
    |> List.wrap()
    |> Enum.map(fn entry -> %{text: Map.get(entry, "quote")} end)
  end

  # Unwraps a Python-pipeline "wrapped" field of shape %{"value" => X, ...} or
  # tolerates already-unwrapped scalars/nil.
  defp unwrap_value(nil), do: nil
  defp unwrap_value(%{"value" => value}), do: value
  defp unwrap_value(value) when is_binary(value), do: value
  defp unwrap_value(value) when is_number(value), do: value
  defp unwrap_value(value) when is_boolean(value), do: value
  defp unwrap_value(_), do: nil

  defp unwrap_authors(nil), do: []

  defp unwrap_authors(authors) when is_list(authors) do
    authors
    |> Enum.map(&unwrap_value/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_year(nil), do: nil

  defp parse_year(year) when is_integer(year), do: year

  defp parse_year(year) when is_binary(year) do
    case Integer.parse(year) do
      {value, _rest} -> value
      :error -> nil
    end
  end

  defp parse_year(_), do: nil
end
