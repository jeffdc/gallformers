defmodule GallformersWeb.Admin.IngestionReviewLive.Presenter do
  alias Gallformers.Galls
  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.SourceIngestion
  alias Gallformers.Sources
  alias Gallformers.Species, as: SpeciesContext
  alias Gallformers.Utils

  @doc """
  Returns the persisted detail-page view model for an ingestion review.
  """
  @spec source_ingestion_review_view!(integer()) :: map()
  def source_ingestion_review_view!(id) do
    source_ingestion = Ingestions.get_source_ingestion_with_details!(id)

    source_review_unlocked? = Ingestions.source_review_unlocked?(source_ingestion)
    species_review_unlocked? = Ingestions.species_review_unlocked?(source_ingestion)
    clearability = Ingestions.source_ingestion_clearability(source_ingestion)

    species_entries =
      source_ingestion.species_entries
      |> Enum.map(&species_entry_review_view/1)
      |> Enum.reject(&(&1.extracted_name in [nil, ""]))
      |> Enum.sort_by(& &1.extracted_name)

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
      error_stage: source_ingestion.error_stage,
      error_message: source_ingestion.error_message,
      source_review_unlocked?: source_review_unlocked?,
      species_review_unlocked?: species_review_unlocked?,
      species_entries: species_entries,
      normalized_text: source_ingestion.normalized_text,
      counts: %{
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
    Utils.attr_value(source_ingestion, :processing_stage) || "unknown"
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

  @doc """
  Assembles existing gall data for merge views in the review workspace.

  Returns hosts, aliases, trait filter values, and primary description for a
  catalog gall. Used when identity resolves to "existing" so section components
  can show current data alongside extracted data.
  """
  @spec load_existing_gall_data(integer() | nil) :: map() | nil
  def load_existing_gall_data(nil), do: nil

  def load_existing_gall_data(species_id) when is_integer(species_id) do
    %{
      hosts: Galls.get_hosts_for_gall(species_id),
      aliases: SpeciesContext.get_aliases_for_species(species_id),
      traits: Galls.get_gall_filter_values(species_id),
      description: load_existing_description(species_id)
    }
  end

  defp load_existing_description(species_id) do
    case Sources.get_sources_for_species(species_id) do
      [] -> nil
      [source | _] -> source.description
    end
  end

  defp queue_row(raw_row) do
    raw_row
    |> normalize_queue_counts()
    |> Map.put(:display_title, display_title(raw_row))
  end

  defp normalize_queue_counts(queue_row) do
    queue_row
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
    |> Enum.filter(&trait_present?(Map.get(traits, &1)))
    |> Enum.map(&(&1 |> Atom.to_string() |> String.replace("_", " ")))
  end

  defp extraction_trait_names(_), do: []

  defp trait_present?(%{original: original, suggested: suggested}),
    do: original not in [nil, ""] or suggested != []

  defp trait_present?(%{original: original}), do: original not in [nil, ""]
  defp trait_present?(value) when is_binary(value), do: value != ""
  defp trait_present?(_), do: false

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
