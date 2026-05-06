defmodule Gallformers.Ingestions.DuplicateReview do
  @moduledoc false

  import Ecto.Query

  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.{DuplicateCandidate, SourceIngestion}
  alias Gallformers.Repo
  alias Gallformers.Utils

  @ordered_candidates_query from(duplicate_candidate in DuplicateCandidate,
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

  @spec ordered_candidates_query() :: Ecto.Query.t()
  def ordered_candidates_query, do: @ordered_candidates_query

  @spec change_duplicate_candidate(DuplicateCandidate.t(), map()) :: Ecto.Changeset.t()
  def change_duplicate_candidate(%DuplicateCandidate{} = duplicate_candidate, attrs \\ %{}) do
    DuplicateCandidate.changeset(duplicate_candidate, attrs)
  end

  @spec list_duplicate_candidates(SourceIngestion.t() | integer()) :: [DuplicateCandidate.t()]
  def list_duplicate_candidates(%SourceIngestion{id: source_ingestion_id}) do
    list_duplicate_candidates(source_ingestion_id)
  end

  def list_duplicate_candidates(source_ingestion_id) when is_integer(source_ingestion_id) do
    @ordered_candidates_query
    |> where(
      [duplicate_candidate],
      duplicate_candidate.source_ingestion_id == ^source_ingestion_id
    )
    |> Repo.all()
    |> Repo.preload([:reviewed_by, :candidate_source_ingestion])
  end

  @spec get_duplicate_candidate!(integer()) :: DuplicateCandidate.t()
  def get_duplicate_candidate!(duplicate_candidate_id) when is_integer(duplicate_candidate_id) do
    DuplicateCandidate
    |> Repo.get!(duplicate_candidate_id)
    |> Repo.preload([:reviewed_by, :candidate_source_ingestion])
  end

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

  @spec confirm_duplicate_candidate(DuplicateCandidate.t(), map()) ::
          {:ok, %{candidate: DuplicateCandidate.t(), source_ingestion: SourceIngestion.t()}}
          | {:error, Ecto.Changeset.t()}
  def confirm_duplicate_candidate(%DuplicateCandidate{} = duplicate_candidate, attrs \\ %{}) do
    attrs = Map.new(attrs)

    candidate_status =
      Utils.normalize_atom(Utils.attr_value(attrs, :status) || "confirmed")

    case candidate_status do
      status when status in ["confirmed", "auto_confirmed"] ->
        do_confirm_duplicate_candidate(duplicate_candidate, attrs, candidate_status)

      _ ->
        {:error,
         duplicate_candidate
         |> DuplicateCandidate.changeset(%{})
         |> Ecto.Changeset.add_error(:status, "must be confirmed or auto_confirmed")}
    end
  end

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
          reviewed_by_id: Utils.attr_value(attrs, :reviewed_by_id),
          reviewed_at: Utils.attr_value(attrs, :reviewed_at) || DateTime.utc_now(:second)
        })
        |> update_or_rollback()

      updated_source_ingestion =
        if no_pending_duplicate_candidates?(source_ingestion.id) do
          source_ingestion
          |> Ingestions.transition_source_ingestion_workflow(:duplicate_rejected_resume)
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
        |> Utils.attr_value(:canonical_source_ingestion_id)
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
          reviewed_by_id: Utils.attr_value(attrs, :reviewed_by_id),
          reviewed_at: Utils.attr_value(attrs, :reviewed_at) || DateTime.utc_now(:second)
        })
        |> update_or_rollback()

      updated_source_ingestion =
        source_ingestion
        |> Ingestions.transition_source_ingestion_workflow(:duplicate_confirmed, %{
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
         %SourceIngestion{status: "needs_duplicate_review"} = source_ingestion
       ) do
    source_ingestion
  end

  defp ensure_duplicate_review_open!(%SourceIngestion{} = source_ingestion) do
    Repo.rollback(
      source_ingestion
      |> SourceIngestion.changeset(%{})
      |> Ecto.Changeset.add_error(:status, "duplicate review is no longer pending")
    )
  end

  defp ensure_pending_duplicate_candidate!(
         %DuplicateCandidate{status: "pending"} = duplicate_candidate
       ) do
    duplicate_candidate
  end

  defp ensure_pending_duplicate_candidate!(%DuplicateCandidate{} = duplicate_candidate) do
    Repo.rollback(
      duplicate_candidate
      |> DuplicateCandidate.changeset(%{})
      |> Ecto.Changeset.add_error(:status, "duplicate candidate is no longer pending")
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
        |> Ecto.Changeset.add_error(
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

  defp update_result_or_rollback({:ok, result}), do: result
  defp update_result_or_rollback({:error, reason}), do: Repo.rollback(reason)

  defp update_or_rollback(changeset) do
    case Repo.update(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end
end
