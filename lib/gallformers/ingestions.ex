defmodule Gallformers.Ingestions do
  @moduledoc """
  The ingestion context.

  Owns persisted source-ingestion records, duplicate-review workflow, and
  gall-level review items derived from ingested sources.
  """

  require Logger

  use Boundary,
    deps: [
      Gallformers.Repo,
      Gallformers.ChangesetHelpers,
      Gallformers.SchemaFields,
      Gallformers.Accounts,
      Gallformers.Sources,
      Gallformers.Storage,
      Gallformers.Species,
      Gallformers.IngestionPipeline.Storage,
      Gallformers.IngestionPipeline.Workflow
    ],
    exports: :all

  import Ecto.Changeset, only: [add_error: 3]
  import Ecto.Query

  alias Gallformers.IngestionPipeline.{Storage, Workflow}
  alias Gallformers.Ingestions.{DuplicateCandidate, SourceIngestion, SourceIngestionSpecies}
  alias Gallformers.Repo
  alias Gallformers.Sources.Source
  alias Gallformers.Species, as: SpeciesContext
  alias Gallformers.Storage.SourceArtifacts

  @ordered_duplicate_candidates_query from(duplicate_candidate in DuplicateCandidate,
                                        order_by: [
                                          asc:
                                            fragment(
                                              """
                                              CASE ?
                                                WHEN 'pending' THEN 0
                                                WHEN 'auto_confirmed' THEN 1
                                                WHEN 'confirmed' THEN 2
                                                WHEN 'rejected' THEN 3
                                                ELSE 4
                                              END
                                              """,
                                              duplicate_candidate.status
                                            ),
                                          asc: duplicate_candidate.inserted_at
                                        ]
                                      )

  @ordered_species_entries_query from(source_ingestion_species in SourceIngestionSpecies,
                                   order_by: source_ingestion_species.position
                                 )

  @source_ingestion_orchestration_lock_namespace 41_204

  @trait_option_keys %{
    "color" => :colors,
    "shape" => :shapes,
    "texture" => :textures,
    "walls" => :walls,
    "cells" => :cells,
    "alignment" => :alignments,
    "plant_part" => :plant_parts,
    "form" => :forms,
    "season" => :seasons,
    "detachable" => :detachable
  }

  @source_ingestion_detail_preloads [
    :source,
    :uploaded_by,
    :duplicate_of_source_ingestion,
    duplicate_candidates:
      {@ordered_duplicate_candidates_query, [:candidate_source_ingestion, :reviewed_by]},
    species_entries: {@ordered_species_entries_query, [:species, :reviewed_by]}
  ]

  @source_ingestion_species_workspace_preloads [:species, source_ingestion: [:source]]

  @doc """
  Returns ingestions ordered newest-first.
  """
  @spec list_source_ingestions(keyword()) :: [SourceIngestion.t()]
  def list_source_ingestions(opts \\ []) do
    SourceIngestion
    |> order_by([source_ingestion], desc: source_ingestion.inserted_at)
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> maybe_preload(Keyword.get(opts, :preload, false))
    |> Repo.all()
  end

  @doc """
  Gets a source ingestion by ID.
  """
  @spec get_source_ingestion(integer()) :: SourceIngestion.t() | nil
  def get_source_ingestion(id), do: Repo.get(SourceIngestion, id)

  @doc """
  Gets a source ingestion by ID, raising if it does not exist.
  """
  @spec get_source_ingestion!(integer()) :: SourceIngestion.t()
  def get_source_ingestion!(id), do: Repo.get!(SourceIngestion, id)

  @doc """
  Runs a function while holding a per-ingestion orchestration lock.
  """
  @spec with_source_ingestion_orchestration_lock(integer(), (-> result)) ::
          {:ok, result} | {:error, :already_processing}
        when result: var
  def with_source_ingestion_orchestration_lock(source_ingestion_id, fun)
      when is_integer(source_ingestion_id) and is_function(fun, 0) do
    Repo.checkout(
      fn ->
        if acquire_source_ingestion_orchestration_lock(source_ingestion_id) do
          try do
            {:ok, fun.()}
          after
            maybe_release_source_ingestion_orchestration_lock(source_ingestion_id)
          end
        else
          {:error, :already_processing}
        end
      end,
      timeout: orchestration_lock_timeout()
    )
  end

  @doc """
  Gets a source ingestion with the detail preloads needed by review workflows.
  """
  @spec get_source_ingestion_with_details!(integer()) :: SourceIngestion.t()
  def get_source_ingestion_with_details!(id) do
    id
    |> get_source_ingestion!()
    |> Repo.preload(@source_ingestion_detail_preloads)
  end

  @doc """
  Returns the persisted detail-page view model for an ingestion review.
  """
  @spec source_ingestion_review_view!(integer()) :: map()
  def source_ingestion_review_view!(id) do
    source_ingestion = get_source_ingestion_with_details!(id)

    duplicate_review_required? = duplicate_review_required?(source_ingestion)
    source_review_unlocked? = source_review_unlocked?(source_ingestion)
    species_review_unlocked? = species_review_unlocked?(source_ingestion)
    clearability = source_ingestion_clearability(source_ingestion)

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
  Returns a changeset for a source ingestion.
  """
  @spec change_source_ingestion(SourceIngestion.t(), map()) :: Ecto.Changeset.t()
  def change_source_ingestion(%SourceIngestion{} = source_ingestion, attrs \\ %{}) do
    SourceIngestion.changeset(source_ingestion, attrs)
  end

  @doc """
  Creates a source ingestion and assigns its canonical per-ingestion artifacts path.
  """
  @spec create_source_ingestion(map()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t()}
  def create_source_ingestion(attrs \\ %{}) do
    Repo.transaction(fn ->
      attrs = Map.new(attrs)

      source_ingestion =
        %SourceIngestion{}
        |> SourceIngestion.changeset(attrs)
        |> insert_or_rollback()

      if blank_artifacts_path?(source_ingestion.artifacts_path) do
        source_ingestion
        |> SourceIngestion.changeset(%{
          artifacts_path: SourceArtifacts.private_artifact_prefix(source_ingestion.id)
        })
        |> update_or_rollback()
      else
        source_ingestion
      end
    end)
  end

  @doc """
  Creates a persisted ingestion, uploads its initial input artifact, and
  enqueues the pipeline worker.
  """
  @spec submit_source_ingestion(map()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t() | term()}
  def submit_source_ingestion(attrs) do
    attrs = Map.new(attrs)

    with :ok <- validate_submission_attrs(attrs),
         {:ok, source_ingestion} <- create_submission_record(attrs),
         {:ok, _artifact_path} <- upload_submission_artifact(source_ingestion, attrs),
         {:ok, _job} <- enqueue_submission_worker(source_ingestion) do
      {:ok, source_ingestion}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}

      {:submission_error, source_ingestion, reason} ->
        cleanup_submission_artifacts(source_ingestion.id)
        {:error, reason}
    end
  end

  @doc """
  Returns queue rows for the persisted ingestion review workflow.
  """
  @spec list_source_ingestion_queue_rows(keyword()) :: [map()]
  def list_source_ingestion_queue_rows(opts \\ []) do
    duplicate_counts_query =
      from(duplicate_candidate in DuplicateCandidate,
        group_by: duplicate_candidate.source_ingestion_id,
        select: %{
          source_ingestion_id: duplicate_candidate.source_ingestion_id,
          pending_duplicate_candidates_count:
            sum(
              fragment(
                "CASE WHEN ? = 'pending' THEN 1 ELSE 0 END",
                duplicate_candidate.status
              )
            ),
          total_duplicate_candidates_count: count(duplicate_candidate.id)
        }
      )

    species_counts_query =
      from(source_ingestion_species in SourceIngestionSpecies,
        group_by: source_ingestion_species.source_ingestion_id,
        select: %{
          source_ingestion_id: source_ingestion_species.source_ingestion_id,
          total_species_entries_count: count(source_ingestion_species.id),
          pending_species_entries_count:
            sum(
              fragment(
                "CASE WHEN ? = 'pending' THEN 1 ELSE 0 END",
                source_ingestion_species.status
              )
            ),
          resolved_species_entries_count:
            sum(
              fragment(
                "CASE WHEN ? <> 'pending' THEN 1 ELSE 0 END",
                source_ingestion_species.status
              )
            )
        }
      )

    SourceIngestion
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> maybe_filter_uploaded_by(Keyword.get(opts, :uploaded_by_id))
    |> maybe_exclude_complete(Keyword.get(opts, :include_complete, false))
    |> join(:left, [source_ingestion], uploaded_by in assoc(source_ingestion, :uploaded_by))
    |> join(
      :left,
      [source_ingestion, _uploaded_by],
      duplicate_counts in subquery(duplicate_counts_query),
      on: duplicate_counts.source_ingestion_id == source_ingestion.id
    )
    |> join(
      :left,
      [source_ingestion, _uploaded_by, _duplicate_counts],
      species_counts in subquery(species_counts_query),
      on: species_counts.source_ingestion_id == source_ingestion.id
    )
    |> order_by([source_ingestion], desc: source_ingestion.inserted_at, desc: source_ingestion.id)
    |> select([source_ingestion, uploaded_by, duplicate_counts, species_counts], %{
      id: source_ingestion.id,
      title: source_ingestion.title,
      input_type: source_ingestion.input_type,
      status: source_ingestion.status,
      processing_stage: source_ingestion.processing_stage,
      error_stage: source_ingestion.error_stage,
      inserted_at: source_ingestion.inserted_at,
      uploaded_by_id: source_ingestion.uploaded_by_id,
      uploaded_by_name:
        fragment(
          "COALESCE(NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''), 'Unknown User')",
          uploaded_by.display_name,
          uploaded_by.nickname,
          uploaded_by.auth0_id
        ),
      source_id: source_ingestion.source_id,
      duplicate_of_source_ingestion_id: source_ingestion.duplicate_of_source_ingestion_id,
      pending_duplicate_candidates_count: duplicate_counts.pending_duplicate_candidates_count,
      total_duplicate_candidates_count: duplicate_counts.total_duplicate_candidates_count,
      total_species_entries_count: species_counts.total_species_entries_count,
      pending_species_entries_count: species_counts.pending_species_entries_count,
      resolved_species_entries_count: species_counts.resolved_species_entries_count
    })
    |> Repo.all()
    |> Enum.map(&normalize_queue_row/1)
  end

  @doc """
  Returns the UI-facing queue status label for an ingestion row.
  """
  @spec queue_status_label(map() | SourceIngestion.t()) :: String.t()
  def queue_status_label(queue_row) do
    status = attr_value(queue_row, :status)
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
    persisted_stage = attr_value(source_ingestion, :processing_stage) || "unknown"

    case Workflow.next_stage(source_ingestion) do
      {:run, stage} -> Atom.to_string(stage)
      _ -> persisted_stage
    end
  end

  @doc """
  Transitions an ingestion to a new status.
  """
  @spec transition_source_ingestion_status(SourceIngestion.t(), String.t() | atom(), map()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t()}
  def transition_source_ingestion_status(
        %SourceIngestion{} = source_ingestion,
        status,
        attrs \\ %{}
      ) do
    status = normalize_status(status)

    attrs =
      attrs
      |> Map.new()
      |> Map.put(:status, status)
      |> put_default_stage_for_status(source_ingestion)

    attrs = maybe_put_failed_at(attrs, status)

    source_ingestion
    |> SourceIngestion.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Persists a workflow event for an ingestion through the canonical workflow semantics.
  """
  @spec transition_source_ingestion_workflow(SourceIngestion.t(), Workflow.event(), map()) ::
          {:ok, SourceIngestion.t()}
          | {:error, :invalid_state | :invalid_transition | Ecto.Changeset.t()}
  def transition_source_ingestion_workflow(
        %SourceIngestion{} = source_ingestion,
        event,
        attrs \\ %{}
      ) do
    attrs = Map.new(attrs)

    with {:ok, workflow_attrs} <- Workflow.transition_attrs(source_ingestion, event) do
      status = Map.fetch!(workflow_attrs, :status)
      transition_attrs = Map.merge(attrs, Map.delete(workflow_attrs, :status))

      transition_source_ingestion_status(source_ingestion, status, transition_attrs)
    end
  end

  @doc """
  Updates the explicit duplicate signals and related normalized metadata on an ingestion.
  """
  @spec record_duplicate_signals(SourceIngestion.t(), map()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t()}
  def record_duplicate_signals(%SourceIngestion{} = source_ingestion, attrs) do
    attrs = Map.new(attrs)

    allowed_attrs =
      SourceIngestion.signal_fields()
      |> Enum.reduce(%{}, fn field, acc ->
        case attr_value(attrs, field) do
          nil -> acc
          value -> Map.put(acc, field, value)
        end
      end)

    source_ingestion
    |> SourceIngestion.changeset(allowed_attrs)
    |> Repo.update()
  end

  @doc """
  Associates an ingestion with a source from the ingestion side of the boundary.
  """
  @spec associate_source(SourceIngestion.t(), Source.t() | integer()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t()}
  def associate_source(%SourceIngestion{} = source_ingestion, %Source{id: source_id}) do
    associate_source(source_ingestion, source_id)
  end

  def associate_source(%SourceIngestion{} = source_ingestion, source_id)
      when is_integer(source_id) do
    source_ingestion
    |> SourceIngestion.changeset(%{source_id: source_id})
    |> Repo.update()
  end

  @doc """
  Clears the source association for an ingestion.
  """
  @spec clear_source_association(SourceIngestion.t()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t()}
  def clear_source_association(%SourceIngestion{} = source_ingestion) do
    source_ingestion
    |> SourceIngestion.changeset(%{source_id: nil})
    |> Repo.update()
  end

  @doc """
  Returns whether an ingestion is currently waiting on duplicate review.
  """
  @spec duplicate_review_required?(SourceIngestion.t()) :: boolean()
  def duplicate_review_required?(%SourceIngestion{status: "needs_duplicate_review"}), do: true
  def duplicate_review_required?(_), do: false

  @doc """
  Returns whether source-level review can proceed.
  """
  @spec source_review_unlocked?(SourceIngestion.t()) :: boolean()
  def source_review_unlocked?(%SourceIngestion{status: status})
      when status in ["needs_review", "complete"] do
    true
  end

  def source_review_unlocked?(_), do: false

  @doc """
  Returns whether per-gall review can proceed.
  """
  @spec species_review_unlocked?(SourceIngestion.t()) :: boolean()
  def species_review_unlocked?(%SourceIngestion{source_id: source_id} = source_ingestion)
      when not is_nil(source_id) do
    source_review_unlocked?(source_ingestion)
  end

  def species_review_unlocked?(_), do: false

  @doc """
  Returns whether all per-gall review items are in a resolved state.
  """
  @spec all_species_entries_resolved?(SourceIngestion.t() | integer()) :: boolean()
  def all_species_entries_resolved?(%SourceIngestion{id: source_ingestion_id}) do
    all_species_entries_resolved?(source_ingestion_id)
  end

  def all_species_entries_resolved?(source_ingestion_id) when is_integer(source_ingestion_id) do
    from(source_ingestion_species in SourceIngestionSpecies,
      where:
        source_ingestion_species.source_ingestion_id == ^source_ingestion_id and
          source_ingestion_species.status == "pending"
    )
    |> Repo.exists?()
    |> Kernel.not()
  end

  @doc """
  Completes an ingestion review when every species entry has been resolved.
  """
  @spec maybe_complete_source_ingestion_review(SourceIngestion.t() | integer()) ::
          {:ok, SourceIngestion.t()}
          | {:error, :invalid_state | :invalid_transition | Ecto.Changeset.t()}
  def maybe_complete_source_ingestion_review(%SourceIngestion{id: source_ingestion_id}) do
    maybe_complete_source_ingestion_review(source_ingestion_id)
  end

  def maybe_complete_source_ingestion_review(source_ingestion_id)
      when is_integer(source_ingestion_id) do
    source_ingestion = get_source_ingestion!(source_ingestion_id)

    if source_ingestion.status == "needs_review" and
         all_species_entries_resolved?(source_ingestion_id) do
      transition_source_ingestion_workflow(source_ingestion, :review_completed)
    else
      {:ok, source_ingestion}
    end
  end

  @doc """
  Deletes a clearable ingestion and its private artifacts.
  """
  @spec clear_source_ingestion(SourceIngestion.t() | integer()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t() | term()}
  def clear_source_ingestion(%SourceIngestion{} = source_ingestion) do
    do_clear_source_ingestion(source_ingestion)
  end

  def clear_source_ingestion(source_ingestion_id) when is_integer(source_ingestion_id) do
    source_ingestion_id
    |> get_source_ingestion!()
    |> do_clear_source_ingestion()
  end

  @doc """
  Returns whether an ingestion can be cleared from admin review UI.
  """
  @spec source_ingestion_clearability(SourceIngestion.t() | integer()) ::
          :failed | :abandoned | nil
  def source_ingestion_clearability(%SourceIngestion{} = source_ingestion) do
    cond do
      source_ingestion.status == "failed" ->
        :failed

      abandoned_source_ingestion?(source_ingestion) ->
        :abandoned

      true ->
        nil
    end
  end

  def source_ingestion_clearability(source_ingestion_id) when is_integer(source_ingestion_id) do
    source_ingestion_id
    |> get_source_ingestion!()
    |> source_ingestion_clearability()
  end

  @doc """
  Deletes a terminal failed ingestion and its private artifacts.
  """
  @spec delete_failed_source_ingestion(SourceIngestion.t() | integer()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t() | term()}
  def delete_failed_source_ingestion(source_ingestion) do
    case source_ingestion_clearability(source_ingestion) do
      :failed -> clear_source_ingestion(source_ingestion)
      _ -> {:error, clear_source_ingestion_changeset(source_ingestion)}
    end
  end

  @doc """
  Resets a failed ingestion to its last resumable checkpoint.

  This is used when retrying a discarded worker job for an ingestion that has
  already been marked failed.
  """
  @spec retry_failed_source_ingestion(SourceIngestion.t() | integer()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t()}
  def retry_failed_source_ingestion(%SourceIngestion{} = source_ingestion) do
    with {:ok, retry_stage} <- retry_stage_for_failed_ingestion(source_ingestion) do
      transition_source_ingestion_status(source_ingestion, :processing, %{
        processing_stage: retry_stage,
        error_stage: nil,
        error_message: nil,
        failed_at: nil
      })
    else
      {:error, :not_failed} ->
        {:error, retry_failed_source_ingestion_changeset(source_ingestion, "must be failed")}

      {:error, :missing_error_stage} ->
        {:error,
         retry_failed_source_ingestion_changeset(
           source_ingestion,
           "must record the failed stage before retrying"
         )}

      {:error, :unknown_error_stage} ->
        {:error,
         retry_failed_source_ingestion_changeset(
           source_ingestion,
           "has an unknown failed stage and cannot be retried"
         )}
    end
  end

  def retry_failed_source_ingestion(source_ingestion_id) when is_integer(source_ingestion_id) do
    source_ingestion_id
    |> get_source_ingestion!()
    |> retry_failed_source_ingestion()
  end

  @doc """
  Returns a changeset for a duplicate candidate.
  """
  @spec change_duplicate_candidate(DuplicateCandidate.t(), map()) :: Ecto.Changeset.t()
  def change_duplicate_candidate(%DuplicateCandidate{} = duplicate_candidate, attrs \\ %{}) do
    DuplicateCandidate.changeset(duplicate_candidate, attrs)
  end

  @doc """
  Lists duplicate candidates for an ingestion.
  """
  @spec list_duplicate_candidates(SourceIngestion.t() | integer()) :: [DuplicateCandidate.t()]
  def list_duplicate_candidates(%SourceIngestion{id: source_ingestion_id}) do
    list_duplicate_candidates(source_ingestion_id)
  end

  def list_duplicate_candidates(source_ingestion_id) when is_integer(source_ingestion_id) do
    @ordered_duplicate_candidates_query
    |> where(
      [duplicate_candidate],
      duplicate_candidate.source_ingestion_id == ^source_ingestion_id
    )
    |> Repo.all()
    |> Repo.preload([:reviewed_by, :candidate_source_ingestion])
  end

  @doc """
  Gets a duplicate candidate by ID, raising if it does not exist.
  """
  @spec get_duplicate_candidate!(integer()) :: DuplicateCandidate.t()
  def get_duplicate_candidate!(duplicate_candidate_id) when is_integer(duplicate_candidate_id) do
    DuplicateCandidate
    |> Repo.get!(duplicate_candidate_id)
    |> Repo.preload([:reviewed_by, :candidate_source_ingestion])
  end

  @doc """
  Creates a duplicate candidate for an ingestion pair.
  """
  @spec create_duplicate_candidate(SourceIngestion.t(), SourceIngestion.t(), map()) ::
          {:ok, DuplicateCandidate.t()} | {:error, Ecto.Changeset.t()}
  def create_duplicate_candidate(
        %SourceIngestion{id: source_ingestion_id},
        %SourceIngestion{id: candidate_source_ingestion_id},
        attrs \\ %{}
      ) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:source_ingestion_id, source_ingestion_id)
      |> Map.put(:candidate_source_ingestion_id, candidate_source_ingestion_id)

    create_duplicate_candidate(attrs)
  end

  def create_duplicate_candidate(attrs) do
    %DuplicateCandidate{}
    |> DuplicateCandidate.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Confirms a duplicate candidate and links the subject ingestion to its canonical ingestion.
  """
  @spec confirm_duplicate_candidate(DuplicateCandidate.t(), map()) ::
          {:ok, %{candidate: DuplicateCandidate.t(), source_ingestion: SourceIngestion.t()}}
          | {:error, Ecto.Changeset.t()}
  def confirm_duplicate_candidate(%DuplicateCandidate{} = duplicate_candidate, attrs \\ %{}) do
    attrs = Map.new(attrs)

    candidate_status =
      normalize_status(attr_value(attrs, :status) || "confirmed")

    case candidate_status do
      status when status in ["confirmed", "auto_confirmed"] ->
        do_confirm_duplicate_candidate(duplicate_candidate, attrs, candidate_status)

      _ ->
        {:error,
         duplicate_candidate
         |> DuplicateCandidate.changeset(%{})
         |> add_error(:status, "must be confirmed or auto_confirmed")}
    end
  end

  @doc """
  Rejects a duplicate candidate and resumes pipeline processing if no pending
  candidates remain.
  """
  @spec reject_duplicate_candidate(DuplicateCandidate.t(), map()) ::
          {:ok, %{candidate: DuplicateCandidate.t(), source_ingestion: SourceIngestion.t()}}
          | {:error, Ecto.Changeset.t()}
  def reject_duplicate_candidate(%DuplicateCandidate{} = duplicate_candidate, attrs \\ %{}) do
    attrs = Map.new(attrs)

    Repo.transaction(fn ->
      source_ingestion =
        duplicate_candidate.source_ingestion_id
        |> lock_source_ingestion_for_duplicate_review!()
        |> ensure_duplicate_review_open!()

      duplicate_candidate =
        duplicate_candidate.id
        |> lock_duplicate_candidate!()
        |> ensure_pending_duplicate_candidate!()

      updated_candidate =
        duplicate_candidate
        |> DuplicateCandidate.changeset(%{
          status: "rejected",
          reviewed_by_id: attr_value(attrs, :reviewed_by_id),
          reviewed_at: attr_value(attrs, :reviewed_at) || now()
        })
        |> update_or_rollback()

      updated_source_ingestion =
        if no_pending_duplicate_candidates?(source_ingestion.id) do
          source_ingestion
          |> transition_source_ingestion_workflow(:duplicate_rejected_resume)
          |> update_result_or_rollback()
        else
          source_ingestion
        end

      %{
        candidate: Repo.preload(updated_candidate, [:reviewed_by, :candidate_source_ingestion]),
        source_ingestion: updated_source_ingestion
      }
    end)
  end

  @doc """
  Returns a changeset for a gall-level ingestion review item.
  """
  @spec change_source_ingestion_species(SourceIngestionSpecies.t(), map()) :: Ecto.Changeset.t()
  def change_source_ingestion_species(
        %SourceIngestionSpecies{} = source_ingestion_species,
        attrs \\ %{}
      ) do
    SourceIngestionSpecies.changeset(source_ingestion_species, attrs)
  end

  @doc """
  Gets a gall-level ingestion review item by ID, raising if it does not exist.
  """
  @spec get_source_ingestion_species!(integer()) :: SourceIngestionSpecies.t()
  def get_source_ingestion_species!(id), do: Repo.get!(SourceIngestionSpecies, id)

  @doc """
  Lists gall-level review items for an ingestion.
  """
  @spec list_source_ingestion_species(SourceIngestion.t() | integer()) :: [
          SourceIngestionSpecies.t()
        ]
  def list_source_ingestion_species(%SourceIngestion{id: source_ingestion_id}) do
    list_source_ingestion_species(source_ingestion_id)
  end

  def list_source_ingestion_species(source_ingestion_id) when is_integer(source_ingestion_id) do
    @ordered_species_entries_query
    |> where(
      [source_ingestion_species],
      source_ingestion_species.source_ingestion_id == ^source_ingestion_id
    )
    |> Repo.all()
    |> Repo.preload([:species, :reviewed_by])
  end

  @doc """
  Creates a gall-level ingestion review item.
  """
  @spec create_source_ingestion_species(map() | Enumerable.t()) ::
          {:ok, SourceIngestionSpecies.t()} | {:error, Ecto.Changeset.t()}
  def create_source_ingestion_species(attrs) do
    attrs = Map.new(attrs)

    %SourceIngestionSpecies{}
    |> SourceIngestionSpecies.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Ensures gall-level review rows exist for extracted records.
  """
  @spec ensure_source_ingestion_species_entries(SourceIngestion.t() | integer(), [map()]) ::
          {:ok, [SourceIngestionSpecies.t()]} | {:error, Ecto.Changeset.t()}
  def ensure_source_ingestion_species_entries(%SourceIngestion{id: source_ingestion_id}, records)
      when is_list(records) do
    ensure_source_ingestion_species_entries(source_ingestion_id, records)
  end

  def ensure_source_ingestion_species_entries(source_ingestion_id, records)
      when is_integer(source_ingestion_id) and is_list(records) do
    existing_entries_by_position =
      source_ingestion_id
      |> list_source_ingestion_species()
      |> Map.new(&{&1.position, &1})

    records
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {record, position}, {:ok, acc} ->
      case Map.fetch(existing_entries_by_position, position) do
        {:ok, existing_entry} ->
          {:cont, {:ok, [existing_entry | acc]}}

        :error ->
          source_ingestion_id
          |> source_ingestion_species_attrs_from_record(record, position)
          |> create_source_ingestion_species()
          |> case do
            {:ok, species_entry} -> {:cont, {:ok, [species_entry | acc]}}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end
      end
    end)
    |> case do
      {:ok, species_entries} -> {:ok, Enum.reverse(species_entries)}
      error -> error
    end
  end

  @doc """
  Returns the persisted workspace view for a gall-level ingestion review item.
  """
  @spec source_ingestion_species_review_workspace!(integer()) :: map()
  def source_ingestion_species_review_workspace!(id) do
    source_ingestion_species =
      id
      |> get_source_ingestion_species!()
      |> Repo.preload(@source_ingestion_species_workspace_preloads)

    species_review = workspace_species_review(source_ingestion_species)
    host_reviews = workspace_host_reviews(source_ingestion_species)
    trait_reviews = workspace_trait_reviews(source_ingestion_species)

    %{
      id: source_ingestion_species.id,
      source_ingestion_id: source_ingestion_species.source_ingestion_id,
      position: source_ingestion_species.position,
      extracted_name: source_ingestion_species.extracted_name,
      extracted_authority: source_ingestion_species.extracted_authority,
      status: source_ingestion_species.status,
      description_prose: source_ingestion_species.description_prose,
      description_evidence: workspace_description_evidence(source_ingestion_species),
      species_review: species_review,
      host_reviews: host_reviews,
      trait_reviews: trait_reviews,
      description_review: workspace_description_review(source_ingestion_species)
    }
  end

  @doc """
  Persists a gall-review workspace decision for a source ingestion species row.
  """
  @spec update_source_ingestion_species_review(SourceIngestionSpecies.t(), map(), integer()) ::
          {:ok, SourceIngestionSpecies.t()} | {:error, Ecto.Changeset.t()}
  def update_source_ingestion_species_review(
        %SourceIngestionSpecies{} = source_ingestion_species,
        attrs,
        reviewed_by_id
      )
      when is_integer(reviewed_by_id) do
    source_ingestion_species =
      source_ingestion_species
      |> Repo.preload(@source_ingestion_species_workspace_preloads)

    with :ok <- ensure_source_associated_for_review(source_ingestion_species),
         {:ok, normalized_review} <-
           normalize_source_ingestion_species_review(source_ingestion_species, attrs),
         {:ok, status} <-
           review_status_for_update(source_ingestion_species, normalized_review) do
      transition_source_ingestion_species_status(source_ingestion_species, status, %{
        species_id: normalized_review.species_id,
        description_prose: normalized_review.description_prose,
        review_payload: normalized_review.review_payload,
        reviewed_by_id: reviewed_by_id
      })
    end
  end

  @doc """
  Transitions a gall-level ingestion review item to a new status.
  """
  @spec transition_source_ingestion_species_status(
          SourceIngestionSpecies.t(),
          String.t() | atom(),
          map()
        ) :: {:ok, SourceIngestionSpecies.t()} | {:error, Ecto.Changeset.t()}
  def transition_source_ingestion_species_status(
        %SourceIngestionSpecies{} = source_ingestion_species,
        status,
        attrs \\ %{}
      ) do
    attrs = Map.new(attrs)
    status = normalize_status(status)

    attrs =
      attrs
      |> Map.put(:status, status)
      |> maybe_put_reviewed_at(attr_value(attrs, :reviewed_by_id))

    source_ingestion_species
    |> SourceIngestionSpecies.changeset(attrs)
    |> Repo.update()
  end

  defp ensure_source_associated_for_review(%SourceIngestionSpecies{
         source_ingestion: %SourceIngestion{source_id: source_id}
       })
       when not is_nil(source_id),
       do: :ok

  defp ensure_source_associated_for_review(%SourceIngestionSpecies{} = source_ingestion_species) do
    {:error,
     source_ingestion_species
     |> SourceIngestionSpecies.changeset(%{})
     |> add_error(:source_ingestion_id, "must be associated with a source before gall review")}
  end

  defp normalize_source_ingestion_species_review(source_ingestion_species, attrs) do
    attrs = Map.new(attrs)

    with {:ok, species_review} <- normalize_workspace_species_review(attrs),
         {:ok, host_reviews} <- normalize_workspace_host_reviews(attrs),
         {:ok, trait_reviews} <-
           normalize_workspace_trait_reviews(source_ingestion_species, attrs),
         {:ok, action} <- normalize_workspace_action(attrs) do
      description_prose =
        attrs
        |> attr_value(:description_prose)
        |> normalize_optional_string(source_ingestion_species.description_prose)

      review_payload = %{
        "species_review" => species_review.payload,
        "host_reviews" => Enum.map(host_reviews, & &1.payload),
        "trait_reviews" => trait_reviews.payload,
        "description_review" => %{
          "edited" => description_prose != source_ingestion_species.description_prose
        }
      }

      {:ok,
       %{
         action: action,
         species_id: species_review.species_id,
         description_prose: description_prose,
         review_payload: review_payload
       }}
    end
  end

  defp normalize_workspace_species_review(attrs) do
    species_review_attrs = nested_value(attrs, :species_review, %{})
    decision = nested_value(species_review_attrs, :decision, nil)
    species_id = nested_integer(species_review_attrs, :species_id)
    notes = normalize_optional_string(nested_value(species_review_attrs, :notes, nil))

    cond do
      decision == "mapped" and is_nil(species_id) ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:species_id, "must be selected for a mapped review")}

      decision == "mapped" ->
        {:ok,
         %{
           species_id: species_id,
           payload: %{
             "decision" => "mapped",
             "species_id" => species_id,
             "notes" => notes
           }
         }}

      decision == "skip" ->
        {:ok,
         %{
           species_id: nil,
           payload: %{
             "decision" => "skip",
             "species_id" => nil,
             "notes" => notes
           }
         }}

      true ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:review_payload, "species review decision is required")}
    end
  end

  defp normalize_workspace_host_reviews(attrs) do
    attrs
    |> nested_value(:host_reviews, %{})
    |> normalize_indexed_values()
    |> Enum.reduce_while({:ok, []}, fn host_review_attrs, {:ok, acc} ->
      decision = nested_value(host_review_attrs, :decision, "unresolved")
      species_id = nested_integer(host_review_attrs, :species_id)

      payload = %{
        "extracted_name" => nested_value(host_review_attrs, :extracted_name, nil),
        "extracted_authority" => nested_value(host_review_attrs, :extracted_authority, nil)
      }

      case decision do
        "mapped" when is_nil(species_id) ->
          {:halt,
           {:error,
            %SourceIngestionSpecies{}
            |> SourceIngestionSpecies.changeset(%{})
            |> add_error(:review_payload, "mapped host reviews must select a host species")}}

        "mapped" ->
          {:cont,
           {:ok,
            [
              %{
                payload:
                  Map.merge(payload, %{
                    "decision" => "mapped",
                    "species_id" => species_id
                  })
              }
              | acc
            ]}}

        "skip" ->
          {:cont,
           {:ok,
            [
              %{
                payload:
                  Map.merge(payload, %{
                    "decision" => "skip",
                    "species_id" => nil
                  })
              }
              | acc
            ]}}

        "unresolved" ->
          {:cont,
           {:ok,
            [
              %{
                payload:
                  Map.merge(payload, %{
                    "decision" => "unresolved",
                    "species_id" => nil
                  })
              }
              | acc
            ]}}

        _ ->
          {:halt,
           {:error,
            %SourceIngestionSpecies{}
            |> SourceIngestionSpecies.changeset(%{})
            |> add_error(:review_payload, "host review decision is invalid")}}
      end
    end)
    |> case do
      {:ok, host_reviews} -> {:ok, Enum.reverse(host_reviews)}
      error -> error
    end
  end

  defp normalize_workspace_trait_reviews(source_ingestion_species, attrs) do
    extraction_traits = extraction_traits(source_ingestion_species.extraction_payload)

    payload =
      attrs
      |> nested_value(:trait_reviews, %{})
      |> normalize_trait_review_values()
      |> Enum.reduce(%{}, fn {name, trait_review_attrs}, acc ->
        selected_values =
          trait_review_attrs
          |> nested_value(:selected_values, [])
          |> normalize_string_list()

        Map.put(acc, name, %{
          "selected_values" => selected_values,
          "raw_evidence" => extract_trait_raw_evidence(Map.get(extraction_traits, name))
        })
      end)

    {:ok, %{payload: payload}}
  end

  defp normalize_workspace_action(attrs) do
    case attr_value(attrs, :action) do
      "save" ->
        {:ok, "save"}

      "complete" ->
        {:ok, "complete"}

      nil ->
        {:ok, "save"}

      _ ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:status, "review action is invalid")}
    end
  end

  defp review_status_for_update(
         %SourceIngestionSpecies{source_ingestion: %SourceIngestion{source_id: source_id}},
         %{action: "complete", species_id: species_id, review_payload: review_payload}
       ) do
    host_reviews = Map.get(review_payload, "host_reviews", [])
    species_review = Map.get(review_payload, "species_review", %{})
    description_review = Map.get(review_payload, "description_review", %{})

    cond do
      is_nil(source_id) ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:status, "cannot mark complete until a source is associated")}

      Map.get(species_review, "decision") != "mapped" or is_nil(species_id) ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:status, "cannot mark complete until the gall is mapped")}

      Enum.any?(host_reviews, &(Map.get(&1, "decision") == "unresolved")) ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:status, "cannot mark complete while host reviews are unresolved")}

      is_nil(Map.get(description_review, "edited")) ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:status, "cannot mark complete until the description is reviewed")}

      true ->
        {:ok, "complete"}
    end
  end

  defp review_status_for_update(_source_ingestion_species, %{review_payload: review_payload}) do
    case get_in(review_payload, ["species_review", "decision"]) do
      "mapped" ->
        {:ok, "mapped"}

      "skip" ->
        {:ok, "skipped"}

      _ ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:status, "review decision is invalid")}
    end
  end

  defp workspace_species_review(source_ingestion_species) do
    persisted_review = nested_value(source_ingestion_species.review_payload, :species_review, %{})

    decision =
      nested_value(
        persisted_review,
        :decision,
        if(source_ingestion_species.species_id, do: "mapped")
      )

    species_id =
      nested_integer(persisted_review, :species_id) || source_ingestion_species.species_id

    %{
      decision: decision,
      species_id: species_id,
      notes: nested_value(persisted_review, :notes, nil),
      selected_species: maybe_species_summary(species_id, source_ingestion_species.species)
    }
  end

  defp workspace_host_reviews(source_ingestion_species) do
    persisted_reviews =
      source_ingestion_species.review_payload
      |> nested_value(:host_reviews, [])
      |> normalize_indexed_values()

    selected_species =
      persisted_reviews
      |> Enum.map(&nested_integer(&1, :species_id))
      |> Enum.reject(&is_nil/1)
      |> load_species_summaries()

    source_ingestion_species.extraction_payload
    |> extraction_hosts()
    |> Enum.with_index()
    |> Enum.map(fn {host, index} ->
      persisted_review = matching_host_review(host, persisted_reviews)
      species_id = nested_integer(persisted_review, :species_id)

      %{
        index: index,
        extracted_name: nested_value(host, :name, nil),
        extracted_authority: nested_value(host, :authority, nil),
        decision: nested_value(persisted_review, :decision, "unresolved"),
        species_id: species_id,
        selected_species: Map.get(selected_species, species_id),
        search_query: "",
        search_results: []
      }
    end)
  end

  defp workspace_trait_reviews(source_ingestion_species) do
    persisted_trait_reviews =
      nested_value(source_ingestion_species.review_payload, :trait_reviews, %{})

    source_ingestion_species.extraction_payload
    |> extraction_traits()
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map(fn name ->
      persisted_trait_review = nested_value(persisted_trait_reviews, name, %{})
      extracted_trait = extraction_traits(source_ingestion_species.extraction_payload)[name]

      %{
        name: name,
        selected_values:
          persisted_trait_review
          |> nested_value(:selected_values, extracted_trait_suggested_values(extracted_trait))
          |> normalize_string_list(),
        suggested_values: extracted_trait_suggested_values(extracted_trait),
        raw_evidence:
          persisted_trait_review
          |> nested_value(:raw_evidence, extract_trait_raw_evidence(extracted_trait))
          |> normalize_string_list()
      }
    end)
  end

  defp workspace_description_review(source_ingestion_species) do
    persisted_review =
      nested_value(source_ingestion_species.review_payload, :description_review, %{})

    %{edited: nested_value(persisted_review, :edited, false)}
  end

  defp workspace_description_evidence(source_ingestion_species) do
    source_ingestion_species.extraction_payload
    |> nested_value(:description_evidence, [])
    |> normalize_indexed_values()
    |> Enum.flat_map(fn evidence ->
      case nested_value(evidence, :text, nil) do
        text when is_binary(text) and text != "" -> [text]
        _ -> []
      end
    end)
  end

  defp matching_host_review(host, persisted_reviews) do
    Enum.find(persisted_reviews, %{}, fn persisted_review ->
      nested_value(persisted_review, :extracted_name, nil) == nested_value(host, :name, nil) and
        nested_value(persisted_review, :extracted_authority, nil) ==
          nested_value(host, :authority, nil)
    end)
  end

  defp maybe_species_summary(nil, _species), do: nil

  defp maybe_species_summary(species_id, nil) do
    species_id
    |> SpeciesContext.get_species()
    |> species_summary()
  end

  defp maybe_species_summary(_species_id, species), do: species_summary(species)

  defp source_ingestion_species_attrs_from_record(source_ingestion_id, record, position) do
    gall_species = attr_value(record, :gall_species)
    host_species = attr_value(record, :host_species)
    description = string_or_nil(attr_value(record, :description))

    %{
      source_ingestion_id: source_ingestion_id,
      position: position,
      status: "pending",
      extracted_name: nested_value(gall_species, :name, nil),
      extracted_authority: nested_value(gall_species, :authority, nil),
      description_prose: description || "",
      extraction_payload: %{
        "gall_species" => normalize_extracted_record_map(gall_species),
        "host_species" => normalize_extracted_record_map(host_species),
        "hosts" => normalize_extracted_hosts(host_species),
        "traits" => normalize_extracted_traits(attr_value(record, :traits)),
        "description_evidence" => description_evidence_from_record(description),
        "location" => attr_value(record, :location),
        "confidence" => attr_value(record, :confidence)
      }
    }
  end

  defp normalize_extracted_record_map(value) when is_map(value), do: value
  defp normalize_extracted_record_map(_value), do: %{}

  defp normalize_extracted_hosts(host_species) when is_map(host_species) do
    case nested_value(host_species, :name, nil) do
      name when is_binary(name) and name != "" -> [host_species]
      _ -> []
    end
  end

  defp normalize_extracted_hosts(_host_species), do: []

  defp normalize_extracted_traits(traits) when is_map(traits), do: traits
  defp normalize_extracted_traits(_traits), do: %{}

  defp description_evidence_from_record(nil), do: []
  defp description_evidence_from_record(description), do: [%{"text" => description}]

  defp string_or_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp string_or_nil(_value), do: nil

  defp load_species_summaries([]), do: %{}

  defp load_species_summaries(species_ids) do
    species_ids
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn species_id, acc ->
      case SpeciesContext.get_species(species_id) do
        nil -> acc
        species -> Map.put(acc, species_id, species_summary(species))
      end
    end)
  end

  defp species_summary(nil), do: nil

  defp species_summary(species) do
    %{
      id: species.id,
      name: species.name,
      taxoncode: species.taxoncode
    }
  end

  defp extraction_hosts(extraction_payload) do
    case nested_value(extraction_payload, :hosts, []) do
      hosts when is_list(hosts) -> hosts
      _ -> []
    end
  end

  defp extraction_traits(extraction_payload) do
    case nested_value(extraction_payload, :traits, %{}) do
      traits when is_map(traits) -> traits
      _ -> %{}
    end
  end

  defp extracted_trait_suggested_values(nil), do: []

  defp extracted_trait_suggested_values(extracted_trait) do
    extracted_trait
    |> nested_value(:suggested, [])
    |> normalize_string_list()
  end

  defp extract_trait_raw_evidence(nil), do: []

  defp extract_trait_raw_evidence(extracted_trait) do
    extracted_trait
    |> case do
      trait when is_map(trait) ->
        originals = nested_value(trait, :originals, nil)

        cond do
          is_list(originals) -> normalize_string_list(originals)
          is_binary(nested_value(trait, :original, nil)) -> [nested_value(trait, :original, nil)]
          true -> []
        end

      _ ->
        []
    end
  end

  defp normalize_trait_review_values(trait_reviews) when is_map(trait_reviews) do
    trait_reviews
    |> Enum.map(fn {name, value} -> {to_string(name), value} end)
    |> Enum.filter(fn {name, _} -> Map.has_key?(@trait_option_keys, name) end)
    |> Map.new()
  end

  defp normalize_trait_review_values(_), do: %{}

  defp normalize_indexed_values(values) when is_list(values), do: values

  defp normalize_indexed_values(values) when is_map(values) do
    values
    |> Enum.map(fn {key, value} -> {parse_index_key(key), value} end)
    |> Enum.sort_by(fn {index, _value} -> index end)
    |> Enum.map(fn {_index, value} -> value end)
  end

  defp normalize_indexed_values(_), do: []

  defp parse_index_key(key) when is_integer(key), do: key
  defp parse_index_key(key) when is_binary(key), do: String.to_integer(key)

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.flat_map(fn
      value when is_binary(value) and value != "" -> [value]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp normalize_string_list(value) when is_binary(value) and value != "", do: [value]
  defp normalize_string_list(_), do: []

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value),
    do: normalize_optional_string(value, nil)

  defp normalize_optional_string(value, fallback) when is_binary(value) do
    if String.trim(value) == "" do
      fallback
    else
      String.trim(value)
    end
  end

  defp normalize_optional_string(_value, fallback), do: fallback

  defp nested_value(map, key, default) when is_map(map) do
    string_key =
      case key do
        value when is_atom(value) -> Atom.to_string(value)
        value when is_binary(value) -> value
      end

    case Map.get(map, key) do
      nil -> Map.get(map, string_key, default)
      value -> value
    end
  end

  defp nested_value(_map, _key, default), do: default

  defp nested_integer(map, key) do
    case nested_value(map, key, nil) do
      value when is_integer(value) -> value
      value when is_binary(value) and value != "" -> String.to_integer(value)
      _ -> nil
    end
  end

  defp validate_submission_attrs(attrs) do
    changeset =
      {%{}, submission_types()}
      |> Ecto.Changeset.cast(attrs, Map.keys(submission_types()))
      |> Ecto.Changeset.validate_required([:input_type, :uploaded_by_id])
      |> Ecto.Changeset.validate_inclusion(:input_type, ~w(pdf url text))
      |> validate_submission_fields()

    if changeset.valid? do
      :ok
    else
      {:error, changeset}
    end
  end

  defp validate_submission_fields(changeset) do
    case Ecto.Changeset.get_field(changeset, :input_type) do
      "pdf" ->
        changeset
        |> Ecto.Changeset.validate_required([:filename, :content])
        |> validate_non_blank(:filename)

      "url" ->
        changeset
        |> Ecto.Changeset.validate_required([:url])
        |> validate_non_blank(:url)

      "text" ->
        changeset
        |> Ecto.Changeset.validate_required([:text])
        |> validate_non_blank(:text)

      _ ->
        changeset
    end
  end

  defp validate_non_blank(changeset, field) do
    Ecto.Changeset.validate_change(changeset, field, fn ^field, value ->
      if is_binary(value) and String.trim(value) == "" do
        [{field, "can't be blank"}]
      else
        []
      end
    end)
  end

  defp create_submission_record(attrs) do
    create_source_ingestion(%{
      input_type: attr_value(attrs, :input_type),
      uploaded_by_id: attr_value(attrs, :uploaded_by_id)
    })
  end

  defp upload_submission_artifact(source_ingestion, attrs) do
    {filename, content, content_type} = submission_artifact_spec(attrs)

    case Storage.upload_artifact(source_ingestion.id, :input, filename, content, content_type) do
      {:ok, artifact_path} -> {:ok, artifact_path}
      {:error, reason} -> {:submission_error, source_ingestion, reason}
    end
  end

  defp enqueue_submission_worker(source_ingestion) do
    case worker_module().enqueue(source_ingestion.id) do
      {:ok, job} -> {:ok, job}
      {:error, reason} -> {:submission_error, source_ingestion, reason}
    end
  end

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) when is_atom(status) do
    maybe_filter_status(query, Atom.to_string(status))
  end

  defp maybe_filter_status(query, statuses) when is_list(statuses) do
    normalized_statuses = Enum.map(statuses, &normalize_status/1)
    from(source_ingestion in query, where: source_ingestion.status in ^normalized_statuses)
  end

  defp maybe_filter_status(query, status) when is_binary(status) do
    from(source_ingestion in query, where: source_ingestion.status == ^status)
  end

  defp maybe_filter_uploaded_by(query, nil), do: query

  defp maybe_filter_uploaded_by(query, uploaded_by_id) when is_integer(uploaded_by_id) do
    from(source_ingestion in query, where: source_ingestion.uploaded_by_id == ^uploaded_by_id)
  end

  defp maybe_exclude_complete(query, true), do: query

  defp maybe_exclude_complete(query, false) do
    from(source_ingestion in query,
      where: source_ingestion.status not in ["complete", "duplicate_confirmed"]
    )
  end

  defp maybe_preload(query, true), do: preload(query, ^@source_ingestion_detail_preloads)
  defp maybe_preload(query, false), do: query

  defp put_default_stage_for_status(attrs, %SourceIngestion{processing_stage: processing_stage}) do
    case attr_value(attrs, :processing_stage) do
      nil ->
        case attr_value(attrs, :status) do
          "needs_duplicate_review" -> Map.put(attrs, :processing_stage, "duplicate_review")
          "needs_review" -> Map.put(attrs, :processing_stage, "review")
          "duplicate_confirmed" -> Map.put(attrs, :processing_stage, "duplicate_review")
          "complete" -> Map.put(attrs, :processing_stage, "complete")
          "failed" -> Map.put(attrs, :processing_stage, "failed")
          _ -> Map.put(attrs, :processing_stage, processing_stage)
        end

      _ ->
        attrs
    end
  end

  defp maybe_put_failed_at(attrs, "failed") do
    case attr_value(attrs, :failed_at) do
      nil -> Map.put(attrs, :failed_at, now())
      _ -> attrs
    end
  end

  defp maybe_put_failed_at(attrs, _status), do: attrs

  defp maybe_put_reviewed_at(attrs, nil), do: attrs

  defp maybe_put_reviewed_at(attrs, _reviewed_by_id) do
    case attr_value(attrs, :reviewed_at) do
      nil -> Map.put(attrs, :reviewed_at, now())
      _ -> attrs
    end
  end

  defp acquire_source_ingestion_orchestration_lock(source_ingestion_id) do
    %{rows: [[locked?]]} =
      Repo.query!(
        "SELECT pg_try_advisory_lock($1, $2)",
        [@source_ingestion_orchestration_lock_namespace, source_ingestion_id]
      )

    locked?
  end

  defp release_source_ingestion_orchestration_lock(source_ingestion_id) do
    case Repo.query(
           "SELECT pg_advisory_unlock($1, $2)",
           [@source_ingestion_orchestration_lock_namespace, source_ingestion_id]
         ) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_release_source_ingestion_orchestration_lock(source_ingestion_id) do
    case release_source_ingestion_orchestration_lock(source_ingestion_id) do
      :ok ->
        :ok

      {:error, %DBConnection.ConnectionError{} = reason} ->
        Logger.warning(
          "Source ingestion orchestration lock release failed after checkout timeout; assuming connection teardown released the advisory lock",
          ingestion_id: source_ingestion_id,
          reason: Exception.message(reason)
        )

        :ok

      {:error, reason} ->
        raise reason
    end
  end

  defp orchestration_lock_timeout do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:orchestration_lock_timeout, :timer.minutes(5))
  end

  defp update_result_or_rollback({:ok, result}), do: result
  defp update_result_or_rollback({:error, reason}), do: Repo.rollback(reason)

  defp no_pending_duplicate_candidates?(source_ingestion_id) do
    # Lock pending candidates to prevent race conditions with concurrent insertions.
    # We select IDs with FOR UPDATE rather than using aggregate count (which doesn't support locking).
    pending_ids =
      from(duplicate_candidate in DuplicateCandidate,
        where:
          duplicate_candidate.source_ingestion_id == ^source_ingestion_id and
            duplicate_candidate.status == "pending",
        select: duplicate_candidate.id,
        lock: "FOR UPDATE"
      )
      |> Repo.all()

    Enum.empty?(pending_ids)
  end

  defp do_confirm_duplicate_candidate(duplicate_candidate, attrs, candidate_status) do
    Repo.transaction(fn ->
      source_ingestion =
        duplicate_candidate.source_ingestion_id
        |> lock_source_ingestion_for_duplicate_review!()
        |> ensure_duplicate_review_open!()

      duplicate_candidate =
        duplicate_candidate.id
        |> lock_duplicate_candidate!()
        |> ensure_pending_duplicate_candidate!()

      canonical_source_ingestion_id =
        attrs
        |> attr_value(:canonical_source_ingestion_id)
        |> case do
          nil -> duplicate_candidate.candidate_source_ingestion_id
          source_ingestion_id -> source_ingestion_id
        end
        |> resolve_canonical_source_ingestion_id()

      ensure_not_self_duplicate!(
        duplicate_candidate,
        source_ingestion,
        canonical_source_ingestion_id
      )

      updated_candidate =
        duplicate_candidate
        |> DuplicateCandidate.changeset(%{
          status: candidate_status,
          reviewed_by_id: attr_value(attrs, :reviewed_by_id),
          reviewed_at: attr_value(attrs, :reviewed_at) || now()
        })
        |> update_or_rollback()

      updated_source_ingestion =
        source_ingestion
        |> transition_source_ingestion_workflow(:duplicate_confirmed, %{
          duplicate_of_source_ingestion_id: canonical_source_ingestion_id
        })
        |> update_result_or_rollback()

      %{
        candidate: Repo.preload(updated_candidate, [:reviewed_by, :candidate_source_ingestion]),
        source_ingestion: updated_source_ingestion
      }
    end)
  end

  defp lock_source_ingestion_for_duplicate_review!(source_ingestion_id) do
    from(source_ingestion in SourceIngestion,
      where: source_ingestion.id == ^source_ingestion_id,
      lock: "FOR UPDATE"
    )
    |> Repo.one!()
  end

  defp lock_duplicate_candidate!(duplicate_candidate_id) do
    from(duplicate_candidate in DuplicateCandidate,
      where: duplicate_candidate.id == ^duplicate_candidate_id,
      lock: "FOR UPDATE"
    )
    |> Repo.one!()
  end

  defp ensure_duplicate_review_open!(
         %SourceIngestion{status: "needs_duplicate_review"} =
           source_ingestion
       ) do
    source_ingestion
  end

  defp ensure_duplicate_review_open!(%SourceIngestion{} = source_ingestion) do
    Repo.rollback(
      source_ingestion
      |> SourceIngestion.changeset(%{})
      |> add_error(:status, "duplicate review is no longer pending")
    )
  end

  defp ensure_pending_duplicate_candidate!(
         %DuplicateCandidate{status: "pending"} =
           duplicate_candidate
       ) do
    duplicate_candidate
  end

  defp ensure_pending_duplicate_candidate!(%DuplicateCandidate{} = duplicate_candidate) do
    Repo.rollback(
      duplicate_candidate
      |> DuplicateCandidate.changeset(%{})
      |> add_error(:status, "duplicate candidate is no longer pending")
    )
  end

  defp ensure_not_self_duplicate!(
         duplicate_candidate,
         source_ingestion,
         canonical_source_ingestion_id
       ) do
    if canonical_source_ingestion_id == source_ingestion.id do
      Repo.rollback(
        duplicate_candidate
        |> DuplicateCandidate.changeset(%{})
        |> add_error(
          :candidate_source_ingestion_id,
          "cannot confirm a source ingestion as a duplicate of itself"
        )
      )
    end
  end

  defp resolve_canonical_source_ingestion_id(source_ingestion_id) do
    do_resolve_canonical_source_ingestion_id(source_ingestion_id, [])
  end

  @spec do_resolve_canonical_source_ingestion_id(integer() | nil, [integer()]) :: integer() | nil
  defp do_resolve_canonical_source_ingestion_id(source_ingestion_id, visited_ids) do
    cond do
      is_nil(source_ingestion_id) ->
        nil

      source_ingestion_id in visited_ids ->
        source_ingestion_id

      true ->
        visited_ids = [source_ingestion_id | visited_ids]

        case Repo.get(SourceIngestion, source_ingestion_id) do
          %SourceIngestion{duplicate_of_source_ingestion_id: nil} ->
            source_ingestion_id

          %SourceIngestion{duplicate_of_source_ingestion_id: canonical_source_ingestion_id} ->
            do_resolve_canonical_source_ingestion_id(canonical_source_ingestion_id, visited_ids)

          nil ->
            source_ingestion_id
        end
    end
  end

  defp attr_value(attrs, key) do
    # Look up by atom key first, then fall back to string key.
    # Explicitly checks for nil to preserve false/0/"" values.
    case Map.get(attrs, key) do
      nil -> Map.get(attrs, Atom.to_string(key))
      value -> value
    end
  end

  defp normalize_status(status) when is_atom(status), do: Atom.to_string(status)
  defp normalize_status(status) when is_binary(status), do: status

  defp normalize_queue_row(queue_row) do
    queue_row
    |> Map.update(:pending_duplicate_candidates_count, 0, &(&1 || 0))
    |> Map.update(:total_duplicate_candidates_count, 0, &(&1 || 0))
    |> Map.update(:total_species_entries_count, 0, &(&1 || 0))
    |> Map.update(:pending_species_entries_count, 0, &(&1 || 0))
    |> Map.update(:resolved_species_entries_count, 0, &(&1 || 0))
    |> Map.put(:display_title, display_title(queue_row))
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

  defp submission_types do
    %{
      input_type: :string,
      uploaded_by_id: :integer,
      filename: :string,
      content: :binary,
      url: :string,
      text: :string
    }
  end

  defp submission_artifact_spec(attrs) do
    case attr_value(attrs, :input_type) do
      "pdf" -> {"source.pdf", attr_value(attrs, :content), "application/pdf"}
      "url" -> {"source.url", attr_value(attrs, :url), "text/plain"}
      "text" -> {"source.txt", attr_value(attrs, :text), "text/plain"}
    end
  end

  defp cleanup_submission_artifacts(ingestion_id) do
    case Storage.delete_artifacts_for_ingestion(ingestion_id) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Failed to clean up source ingestion artifacts after submission error",
          ingestion_id: ingestion_id,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp do_clear_source_ingestion(%SourceIngestion{} = source_ingestion) do
    case source_ingestion_clearability(source_ingestion) do
      clearability when clearability in [:failed, :abandoned] ->
        do_delete_source_ingestion(source_ingestion)

      nil ->
        {:error, clear_source_ingestion_changeset(source_ingestion)}
    end
  end

  defp do_delete_source_ingestion(%SourceIngestion{} = source_ingestion) do
    with :ok <- Storage.delete_artifacts_for_ingestion(source_ingestion.id) do
      Repo.delete(source_ingestion)
    end
  end

  defp clear_source_ingestion_changeset(%SourceIngestion{} = source_ingestion) do
    source_ingestion
    |> change_source_ingestion(%{})
    |> add_error(:status, "only failed or abandoned ingestions can be cleared")
  end

  defp retry_failed_source_ingestion_changeset(
         %SourceIngestion{} = source_ingestion,
         message
       ) do
    source_ingestion
    |> change_source_ingestion(%{})
    |> add_error(:status, message)
  end

  defp abandoned_source_ingestion?(%SourceIngestion{
         id: source_ingestion_id,
         status: "processing"
       }) do
    not active_worker_job_exists?(source_ingestion_id) and
      latest_worker_state_for_ingestion(source_ingestion_id) in ["discarded", "cancelled"]
  end

  defp abandoned_source_ingestion?(%SourceIngestion{}), do: false

  defp retry_stage_for_failed_ingestion(%SourceIngestion{status: "failed"} = source_ingestion) do
    case attr_value(source_ingestion, :error_stage) do
      nil ->
        {:error, :missing_error_stage}

      "extract" ->
        {:ok, "submitted"}

      "preprocess" ->
        {:ok, "extract"}

      "hash_and_dedup" ->
        {:ok, "preprocess"}

      "llm_clean" ->
        {:ok, llm_clean_retry_stage(source_ingestion)}

      "metadata" ->
        {:ok, "llm_clean"}

      "data_extract" ->
        {:ok, "metadata"}

      "assemble" ->
        {:ok, "data_extract"}

      "upload" ->
        {:ok, "assemble"}

      _other ->
        {:error, :unknown_error_stage}
    end
  end

  defp retry_stage_for_failed_ingestion(%SourceIngestion{}), do: {:error, :not_failed}

  defp llm_clean_retry_stage(%SourceIngestion{id: source_ingestion_id}) do
    if duplicate_candidates_exist?(source_ingestion_id) do
      "duplicate_review"
    else
      "hash_and_dedup"
    end
  end

  defp duplicate_candidates_exist?(source_ingestion_id) when is_integer(source_ingestion_id) do
    from(duplicate_candidate in DuplicateCandidate,
      where: duplicate_candidate.source_ingestion_id == ^source_ingestion_id
    )
    |> Repo.exists?()
  end

  defp active_worker_job_exists?(source_ingestion_id) do
    from(job in "oban_jobs",
      where:
        field(job, :worker) == ^"Gallformers.IngestionPipeline.Worker" and
          field(job, :state) in ^["available", "scheduled", "executing", "retryable"] and
          fragment(
            "?->>'ingestion_id' = ?",
            field(job, :args),
            ^Integer.to_string(source_ingestion_id)
          )
    )
    |> Repo.exists?()
  end

  defp latest_worker_state_for_ingestion(source_ingestion_id) do
    from(job in "oban_jobs",
      where:
        field(job, :worker) == ^"Gallformers.IngestionPipeline.Worker" and
          fragment(
            "?->>'ingestion_id' = ?",
            field(job, :args),
            ^Integer.to_string(source_ingestion_id)
          ),
      order_by: [desc: field(job, :inserted_at), desc: field(job, :id)],
      limit: 1,
      select: field(job, :state)
    )
    |> Repo.one()
  end

  defp queue_row_count(queue_row, field) do
    queue_row
    |> attr_value(field)
    |> Kernel.||(0)
  end

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

  defp species_entry_review_view(species_entry) do
    %{
      id: species_entry.id,
      position: species_entry.position,
      extracted_name: species_entry.extracted_name,
      extracted_authority: species_entry.extracted_authority,
      mapped_species_name: mapped_species_name(species_entry.species),
      host_count: host_count(species_entry.extraction_payload),
      status: species_entry.status
    }
  end

  defp associated_source_review_view(nil), do: nil

  defp associated_source_review_view(source) do
    %{
      id: source.id,
      title: source.title,
      author: source.author,
      pubyear: source.pubyear
    }
  end

  defp mapped_species_name(nil), do: nil
  defp mapped_species_name(species), do: species.name

  defp host_count(%{"hosts" => hosts}) when is_list(hosts), do: length(hosts)
  defp host_count(%{hosts: hosts}) when is_list(hosts), do: length(hosts)
  defp host_count(_), do: 0

  defp review_queue_status_label(queue_row) do
    total_species_entries_count = queue_row_count(queue_row, :total_species_entries_count)
    pending_species_entries_count = queue_row_count(queue_row, :pending_species_entries_count)

    if total_species_entries_count == 0 or is_nil(attr_value(queue_row, :source_id)) do
      "Needs source review"
    else
      "#{pending_species_entries_count} of #{total_species_entries_count} galls remaining"
    end
  end

  defp failed_queue_status_label(queue_row) do
    failed_stage =
      [attr_value(queue_row, :error_stage), processing_stage_label(queue_row)]
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

  defp worker_module do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:worker_module, default_worker_module())
  end

  defp default_worker_module do
    Module.concat([Gallformers.IngestionPipeline, Worker])
  end

  defp blank_artifacts_path?(artifacts_path), do: artifacts_path in [nil, ""]

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp insert_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp update_or_rollback(changeset) do
    case Repo.update(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end
end
