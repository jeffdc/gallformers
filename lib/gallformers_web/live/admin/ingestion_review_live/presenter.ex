defmodule GallformersWeb.Admin.IngestionReviewLive.Presenter do
  alias Gallformers.IngestionPipeline.Workflow
  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.SourceIngestion
  alias Gallformers.Utils

  @doc """
  Returns the persisted detail-page view model for an ingestion review.
  """
  @spec source_ingestion_review_view!(integer()) :: map()
  def source_ingestion_review_view!(id) do
    source_ingestion = Ingestions.get_source_ingestion_with_details!(id)

    duplicate_review_required? = Ingestions.duplicate_review_required?(source_ingestion)
    source_review_unlocked? = Ingestions.source_review_unlocked?(source_ingestion)
    species_review_unlocked? = Ingestions.species_review_unlocked?(source_ingestion)
    clearability = Ingestions.source_ingestion_clearability(source_ingestion)

    duplicate_candidates =
      Enum.map(source_ingestion.duplicate_candidates, &duplicate_candidate_review_view/1)

    species_entries =
      Enum.map(source_ingestion.species_entries, &species_entry_review_view/1)

    %{
      id: source_ingestion.id,
      title: source_ingestion.title,
      display_title: display_title(source_ingestion),
      authors: source_ingestion.authors,
      publication_year: source_ingestion.publication_year,
      doi: source_ingestion.doi,
      input_type: source_ingestion.input_type,
      status: source_ingestion.status,
      processing_stage: source_ingestion.processing_stage,
      inserted_at: source_ingestion.inserted_at,
      uploaded_by_id: source_ingestion.uploaded_by_id,
      source_id: source_ingestion.source_id,
      associated_source: associated_source_review_view(source_ingestion.source),
      duplicate_of_source_ingestion_id: source_ingestion.duplicate_of_source_ingestion_id,
      clearability: clearability,
      clearable?: not is_nil(clearability),
      duplicate_review_required?: duplicate_review_required?,
      source_review_unlocked?: source_review_unlocked?,
      species_review_unlocked?: species_review_unlocked?,
      duplicate_candidates: duplicate_candidates,
      species_entries: species_entries,
      counts: %{
        duplicate_candidates_total: length(duplicate_candidates),
        duplicate_candidates_pending: Enum.count(duplicate_candidates, &(&1.status == "pending")),
        species_entries_total: length(species_entries),
        species_entries_pending: Enum.count(species_entries, &(&1.status == "pending")),
        species_entries_resolved: Enum.count(species_entries, &(&1.status != "pending"))
      }
    }
  end

  @doc """
  Returns the UI-facing queue status label for an ingestion row.
  """
  @spec queue_status_label(map() | SourceIngestion.t()) :: String.t()
  def queue_status_label(queue_row) do
    status = Utils.attr_value(queue_row, :status)
    processing_stage = processing_stage_label(queue_row)

    case status do
      "needs_duplicate_review" ->
        "Needs duplicate review"

      "needs_review" ->
        review_queue_status_label(queue_row)

      "complete" ->
        "Complete"

      "duplicate_confirmed" ->
        "Duplicate confirmed"

      "failed" ->
        failed_queue_status_label(queue_row)

      _ ->
        "Processing: #{processing_stage}"
    end
  end

  @doc """
  Returns the workflow stage label that best represents the current work.
  """
  @spec processing_stage_label(map() | SourceIngestion.t()) :: String.t()
  def processing_stage_label(source_ingestion) do
    persisted_stage = Utils.attr_value(source_ingestion, :processing_stage) || "unknown"

    case Workflow.next_stage(source_ingestion) do
      {:run, stage} -> Atom.to_string(stage)
      _ -> persisted_stage
    end
  end

  @doc """
  Returns queue rows for the persisted ingestion review workflow.
  """
  @spec list_source_ingestion_queue_rows(keyword()) :: [map()]
  def list_source_ingestion_queue_rows(opts \\ []) do
    opts
    |> Ingestions.list_source_ingestion_queue_rows()
    |> Enum.map(&queue_row/1)
  end

  defp queue_row(raw_row) do
    raw_row
    |> normalize_queue_counts()
    |> Map.put(:display_title, display_title(raw_row))
  end

  defp normalize_queue_counts(queue_row) do
    queue_row
    |> Map.update(:pending_duplicate_candidates_count, 0, &(&1 || 0))
    |> Map.update(:total_duplicate_candidates_count, 0, &(&1 || 0))
    |> Map.update(:total_species_entries_count, 0, &(&1 || 0))
    |> Map.update(:pending_species_entries_count, 0, &(&1 || 0))
    |> Map.update(:resolved_species_entries_count, 0, &(&1 || 0))
  end

  defp display_title(%{title: title, input_type: input_type}) when title in [nil, ""] do
    case input_type do
      "url" -> "Untitled URL submission"
      "text" -> "Untitled text submission"
      "pdf" -> "Untitled PDF submission"
      _ -> "Untitled submission"
    end
  end

  defp display_title(%{title: title, input_type: input_type}) when is_binary(title) do
    if String.trim(title) == "" do
      display_title(%{title: nil, input_type: input_type})
    else
      title
    end
  end

  defp review_queue_status_label(queue_row) do
    total_species_entries_count = queue_row_count(queue_row, :total_species_entries_count)
    pending_species_entries_count = queue_row_count(queue_row, :pending_species_entries_count)

    if total_species_entries_count == 0 or is_nil(Utils.attr_value(queue_row, :source_id)) do
      "Needs source review"
    else
      "#{pending_species_entries_count} of #{total_species_entries_count} galls remaining"
    end
  end

  defp failed_queue_status_label(queue_row) do
    failed_stage =
      [Utils.attr_value(queue_row, :error_stage), processing_stage_label(queue_row)]
      |> Enum.find(&meaningful_failed_stage?/1)

    if failed_stage do
      "Failed at #{failed_stage}"
    else
      "Failed"
    end
  end

  defp meaningful_failed_stage?(stage) when is_binary(stage) do
    trimmed_stage = String.trim(stage)
    trimmed_stage != "" and trimmed_stage != "failed"
  end

  defp meaningful_failed_stage?(_stage), do: false

  defp queue_row_count(queue_row, field) do
    queue_row
    |> Utils.attr_value(field)
    |> Kernel.||(0)
  end

  defp duplicate_candidate_evidence_rows(evidence) when is_map(evidence) do
    [
      {"normalized_doi", "DOI match"},
      {"preprocessed_text_sha256", "Exact normalized text match"},
      {"normalized_title", "Title match"},
      {"title_fingerprint", "Title fingerprint match"},
      {"author_fingerprint", "Author overlap"},
      {"publication_year", "Year match"},
      {"similarity", "Text similarity"}
    ]
    |> Enum.flat_map(fn {key, label} ->
      case Map.fetch(evidence, key) do
        {:ok, value} -> [%{key: key, label: label, value: value}]
        :error -> []
      end
    end)
  end

  defp duplicate_candidate_evidence_rows(_), do: []

  defp duplicate_candidate_review_view(duplicate_candidate) do
    candidate_source_ingestion = duplicate_candidate.candidate_source_ingestion

    %{
      id: duplicate_candidate.id,
      status: duplicate_candidate.status,
      evidence_rows: duplicate_candidate_evidence_rows(duplicate_candidate.evidence),
      candidate_source_ingestion_id: duplicate_candidate.candidate_source_ingestion_id,
      candidate_title: candidate_source_ingestion.title,
      candidate_display_title: display_title(candidate_source_ingestion),
      candidate_authors: candidate_source_ingestion.authors,
      candidate_year: candidate_source_ingestion.publication_year
    }
  end

  defp species_entry_review_view(species_entry) do
    payload = species_entry.extraction_payload || %{}

    %{
      id: species_entry.id,
      position: species_entry.position,
      extracted_name: species_entry.extracted_name,
      extracted_authority: species_entry.extracted_authority,
      mapped_species_name: mapped_species_name(species_entry.species),
      host_count: host_count(payload),
      status: species_entry.status,
      extracted_aliases: extraction_aliases(payload),
      extracted_hosts: extraction_hosts(payload),
      extracted_trait_names: extraction_trait_names(payload)
    }
  end

  defp extraction_aliases(%{aliases: aliases}) when is_list(aliases), do: aliases
  defp extraction_aliases(_), do: []

  defp extraction_hosts(%{hosts: hosts}) when is_list(hosts) do
    Enum.map(hosts, fn
      %{name: name} = host -> %{name: name, authority: Map.get(host, :authority)}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extraction_hosts(_), do: []

  @trait_fields ~w(shape color texture walls cells alignment plant_part form season detachable)a
  defp extraction_trait_names(%{traits: nil}), do: []

  defp extraction_trait_names(%{traits: traits}) do
    @trait_fields
    |> Enum.filter(fn field -> Map.get(traits, field) not in [nil, ""] end)
    |> Enum.map(&Atom.to_string/1)
  end

  defp extraction_trait_names(_), do: []

  defp mapped_species_name(nil), do: nil
  defp mapped_species_name(species), do: species.name

  defp host_count(%{"hosts" => hosts}) when is_list(hosts), do: length(hosts)
  defp host_count(%{hosts: hosts}) when is_list(hosts), do: length(hosts)
  defp host_count(_), do: 0

  defp associated_source_review_view(nil), do: nil

  defp associated_source_review_view(source) do
    %{
      id: source.id,
      title: source.title,
      author: source.author,
      pubyear: source.pubyear
    }
  end
end
