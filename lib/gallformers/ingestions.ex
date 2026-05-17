defmodule Gallformers.Ingestions do
  @moduledoc """
  The ingestion context.

  Owns persisted source-ingestion records and gall-level review items derived
  from ingested sources.
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
      Gallformers.Galls,
      Gallformers.Taxonomy,
      Gallformers.Utils
    ],
    exports: :all

  import Ecto.Query

  alias Gallformers.Ingestions.{
    BundleImporter,
    Lifecycle,
    SourceIngestion,
    SourceIngestionCreation,
    SourceIngestionSpecies,
    SourceIngestionSpeciesEntries,
    SourceIngestionSpeciesReview
  }

  alias Gallformers.Repo
  alias Gallformers.Sources.Source
  alias Gallformers.Utils

  @ordered_species_entries_query from(source_ingestion_species in SourceIngestionSpecies,
                                   order_by: source_ingestion_species.position
                                 )

  @source_ingestion_detail_preloads [
    :source,
    :uploaded_by,
    :duplicate_of_source_ingestion,
    species_entries: {@ordered_species_entries_query, [:species, :reviewed_by]}
  ]

  @doc """
  Returns queue rows for the persisted ingestion review workflow.
  """
  @spec list_source_ingestion_queue_rows(keyword()) :: [map()]
  def list_source_ingestion_queue_rows(opts \\ []) do
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
      species_counts in subquery(species_counts_query),
      on: species_counts.source_ingestion_id == source_ingestion.id
    )
    |> order_by([source_ingestion], desc: source_ingestion.inserted_at, desc: source_ingestion.id)
    |> select([source_ingestion, uploaded_by, species_counts], %{
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
      total_species_entries_count: species_counts.total_species_entries_count,
      pending_species_entries_count: species_counts.pending_species_entries_count,
      resolved_species_entries_count: species_counts.resolved_species_entries_count
    })
    |> Repo.all()
  end

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
  Gets a source ingestion with the detail preloads needed by review workflows.
  """
  @spec get_source_ingestion_with_details!(integer()) :: SourceIngestion.t()
  def get_source_ingestion_with_details!(id) do
    id
    |> get_source_ingestion!()
    |> Repo.preload(@source_ingestion_detail_preloads)
  end

  @doc """
  Creates a persisted source ingestion record with canonical workflow defaults.
  """
  @spec create_source_ingestion(map()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t()}
  def create_source_ingestion(attrs \\ %{}) do
    SourceIngestionCreation.create_source_ingestion(attrs)
  end

  @doc """
  Imports an extracted Python-pipeline bundle directory into a persisted
  `SourceIngestion` plus per-record `SourceIngestionSpecies` rows.
  """
  @spec import_bundle(Path.t(), keyword()) ::
          {:ok, SourceIngestion.t()} | {:error, term()}
  def import_bundle(bundle_dir, opts \\ []) do
    BundleImporter.import_bundle(bundle_dir, opts)
  end

  @doc """
  Returns a changeset for a source ingestion.
  """
  @spec change_source_ingestion(SourceIngestion.t(), map()) :: Ecto.Changeset.t()
  def change_source_ingestion(%SourceIngestion{} = source_ingestion, attrs \\ %{}) do
    SourceIngestion.changeset(source_ingestion, attrs)
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
    status = Utils.normalize_atom(status)

    source_ingestion
    |> SourceIngestion.transition_changeset(status, attrs)
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
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t()}
  def maybe_complete_source_ingestion_review(%SourceIngestion{id: source_ingestion_id}) do
    maybe_complete_source_ingestion_review(source_ingestion_id)
  end

  def maybe_complete_source_ingestion_review(source_ingestion_id)
      when is_integer(source_ingestion_id) do
    source_ingestion = get_source_ingestion!(source_ingestion_id)

    if source_ingestion.status == "needs_review" and
         all_species_entries_resolved?(source_ingestion_id) do
      transition_source_ingestion_status(source_ingestion, :complete)
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
    Lifecycle.clear_source_ingestion(source_ingestion)
  end

  def clear_source_ingestion(source_ingestion_id) when is_integer(source_ingestion_id) do
    Lifecycle.clear_source_ingestion(source_ingestion_id)
  end

  @doc """
  Returns whether an ingestion can be cleared from admin review UI.
  """
  @spec source_ingestion_clearability(SourceIngestion.t() | integer()) ::
          :failed | :abandoned | nil
  def source_ingestion_clearability(%SourceIngestion{} = source_ingestion) do
    Lifecycle.source_ingestion_clearability(source_ingestion)
  end

  def source_ingestion_clearability(source_ingestion_id) when is_integer(source_ingestion_id) do
    Lifecycle.source_ingestion_clearability(source_ingestion_id)
  end

  @doc """
  Deletes a terminal failed ingestion and its private artifacts.
  """
  @spec delete_failed_source_ingestion(SourceIngestion.t() | integer()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t() | term()}
  def delete_failed_source_ingestion(source_ingestion) do
    Lifecycle.delete_failed_source_ingestion(source_ingestion)
  end

  @doc """
  Deletes a source ingestion and its private artifacts regardless of status.
  """
  @spec delete_source_ingestion(SourceIngestion.t() | integer()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t() | term()}
  def delete_source_ingestion(source_ingestion) do
    Lifecycle.delete_source_ingestion(source_ingestion)
  end

  # --- Species entries ---

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
    SourceIngestionSpeciesEntries.ensure_entries(source_ingestion_id, records)
  end

  # --- Species review ---

  @doc """
  Returns the persisted workspace view for a gall-level ingestion review item.
  """
  @spec source_ingestion_species_review_workspace!(integer()) :: map()
  def source_ingestion_species_review_workspace!(id) do
    SourceIngestionSpeciesReview.workspace!(id)
  end

  @doc """
  Returns the best available full extracted text for an ingestion review.
  """
  @spec source_ingestion_full_text(SourceIngestion.t() | integer()) ::
          {:ok, String.t()} | {:error, term()}
  def source_ingestion_full_text(%SourceIngestion{id: source_ingestion_id}) do
    source_ingestion_full_text(source_ingestion_id)
  end

  def source_ingestion_full_text(source_ingestion_id) when is_integer(source_ingestion_id) do
    SourceIngestionSpeciesReview.full_text(source_ingestion_id)
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
    SourceIngestionSpeciesReview.update_review(source_ingestion_species, attrs, reviewed_by_id)
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
    status = Utils.normalize_atom(status)

    attrs =
      attrs
      |> Map.put(:status, status)
      |> maybe_put_reviewed_at(Utils.attr_value(attrs, :reviewed_by_id))

    source_ingestion_species
    |> SourceIngestionSpecies.changeset(attrs)
    |> Repo.update()
  end

  # --- Private helpers ---

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) when is_atom(status) do
    maybe_filter_status(query, Atom.to_string(status))
  end

  defp maybe_filter_status(query, statuses) when is_list(statuses) do
    normalized_statuses = Enum.map(statuses, &Utils.normalize_atom/1)
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

  defp maybe_put_reviewed_at(attrs, nil), do: attrs

  defp maybe_put_reviewed_at(attrs, _reviewed_by_id) do
    case Utils.attr_value(attrs, :reviewed_at) do
      nil -> Map.put(attrs, :reviewed_at, DateTime.utc_now(:second))
      _ -> attrs
    end
  end
end
