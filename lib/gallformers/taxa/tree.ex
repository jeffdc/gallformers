defmodule Gallformers.Taxa.Tree do
  @moduledoc """
  The tree validator (`9449` §3), run on every parent change: a taxon may
  not sit under itself or its own descendant (a cycle), and a child ranks
  strictly below its parent (`Gallformers.Taxa.Rank`).

  Placement Facts settled one by one could form either fault (`8567`
  *Phases* 1), so the validator guards the tree whatever drives it.
  Errors go on `:parent_id` with `validation: :cycle` or
  `validation: :rank_inversion`; a cycle is reported first, as the deeper
  fault (while every edge respects rank order a cycle is also an inversion).

  Callers hold `lock/0` for the rest of the transaction, so two concurrent
  moves cannot together form a cycle that neither would alone.
  """
  import Ecto.Changeset

  alias Gallformers.Repo
  alias Gallformers.Taxa.Ancestry
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon

  # Arbitrary, fixed key for the tree's transaction-level advisory lock.
  @lock_key 8_567_009_449

  @doc "Takes the tree lock until the end of the current transaction."
  @spec lock() :: :ok
  def lock do
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [@lock_key])
    :ok
  end

  @doc """
  Validates the `parent_id` in `changeset` (a `Gallformers.Taxa.Taxon`
  changeset) against the tree. A taxon without an ID yet is a new leaf, so
  only rank order applies.
  """
  @spec validate_parent(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_parent(%Ecto.Changeset{} = changeset) do
    parent_id = get_field(changeset, :parent_id)

    if changeset.valid? and parent_id != nil do
      validate_against(changeset, parent_id)
    else
      changeset
    end
  end

  defp validate_against(changeset, parent_id) do
    taxon_id = get_field(changeset, :id)

    case Repo.get(Taxon, parent_id) do
      nil ->
        add_error(changeset, :parent_id, "does not exist")

      parent ->
        cond do
          taxon_id != nil and Ancestry.ancestor_or_self?(taxon_id, parent_id) ->
            add_error(changeset, :parent_id, "would place the taxon under itself",
              validation: :cycle
            )

          not Rank.below?(get_field(changeset, :rank), parent.rank) ->
            add_error(
              changeset,
              :parent_id,
              "must rank above the taxon (#{get_field(changeset, :rank)} is not below #{parent.rank})",
              validation: :rank_inversion
            )

          true ->
            changeset
        end
    end
  end
end
