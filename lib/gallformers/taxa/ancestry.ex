defmodule Gallformers.Taxa.Ancestry do
  @moduledoc """
  The `taxon_ancestry` closure table (`9449` §3): one row per ancestor and
  descendant, each taxon its own ancestor at depth 0. It is the read model
  for "all taxa under X" and "everything above Y" (ID tool, search, "all
  Galls under X", generation groups), and the tree validator's cycle check.

  It is derived from `taxa.parent_id` and kept in step inside the
  transaction that changes a parent; it is not audited.
  """
  use Ecto.Schema
  import Ecto.Query

  alias Gallformers.Repo

  @type t :: %__MODULE__{
          ancestor_id: integer() | nil,
          descendant_id: integer() | nil,
          depth: non_neg_integer() | nil
        }

  @primary_key false
  schema "taxon_ancestry" do
    field :ancestor_id, :id, primary_key: true
    field :descendant_id, :id, primary_key: true
    field :depth, :integer
  end

  @doc "Adds the rows for a new leaf taxon `taxon_id` under `parent_id` (or nil)."
  @spec add_leaf(integer(), integer() | nil) :: :ok
  def add_leaf(taxon_id, parent_id) do
    Repo.insert_all(__MODULE__, [%{ancestor_id: taxon_id, descendant_id: taxon_id, depth: 0}])
    attach(taxon_id, parent_id)
  end

  @doc """
  Rebuilds the rows of `taxon_id`'s subtree after it moves under
  `parent_id` (or becomes a root): the subtree's links to its old ancestors
  go, and links to every ancestor of the new parent are added. Rows within
  the subtree are unchanged.
  """
  @spec move_subtree(integer(), integer() | nil) :: :ok
  def move_subtree(taxon_id, parent_id) do
    subtree = from(a in __MODULE__, where: a.ancestor_id == ^taxon_id, select: a.descendant_id)

    from(a in __MODULE__,
      where: a.descendant_id in subquery(subtree) and a.ancestor_id not in subquery(subtree)
    )
    |> Repo.delete_all()

    attach(taxon_id, parent_id)
  end

  @doc "Whether `ancestor_id` is `taxon_id` or above it."
  @spec ancestor_or_self?(integer(), integer()) :: boolean()
  def ancestor_or_self?(ancestor_id, taxon_id) do
    Repo.exists?(
      from(a in __MODULE__, where: a.ancestor_id == ^ancestor_id and a.descendant_id == ^taxon_id)
    )
  end

  @doc "IDs of the taxa above `taxon_id`, nearest first."
  @spec ancestor_ids(integer()) :: [integer()]
  def ancestor_ids(taxon_id) do
    from(a in __MODULE__,
      where: a.descendant_id == ^taxon_id and a.depth > 0,
      order_by: a.depth,
      select: a.ancestor_id
    )
    |> Repo.all()
  end

  @doc "IDs of the taxa below `taxon_id`, nearest first."
  @spec descendant_ids(integer()) :: [integer()]
  def descendant_ids(taxon_id) do
    from(a in __MODULE__,
      where: a.ancestor_id == ^taxon_id and a.depth > 0,
      order_by: [a.depth, a.descendant_id],
      select: a.descendant_id
    )
    |> Repo.all()
  end

  # Links every taxon in `taxon_id`'s subtree to `parent_id` and its
  # ancestors.
  defp attach(_taxon_id, nil), do: :ok

  defp attach(taxon_id, parent_id) do
    Repo.query!(
      """
      INSERT INTO taxon_ancestry (ancestor_id, descendant_id, depth)
      SELECT up.ancestor_id, down.descendant_id, up.depth + down.depth + 1
      FROM taxon_ancestry up, taxon_ancestry down
      WHERE up.descendant_id = $1 AND down.ancestor_id = $2
      """,
      [parent_id, taxon_id]
    )

    :ok
  end
end
