defmodule Gallformers.Catalog.PendingTerms do
  @moduledoc """
  Terms waiting on a question (matter `d213`,
  `Gallformers.Catalog.PendingTraitTerm`): a Source's Trait term on a Gall
  with no Fact yet. The import stores one (`put/2`) when a term's use
  can't be placed on its own; a curator's decision settles it (`settle/5`),
  under a category (the caller then writes the Fact, attributed to the
  Source with the stored quotes) or as text. Reached through
  `Gallformers.Catalog`; every write is audited.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog.PendingTraitTerm
  alias Gallformers.Catalog.Vocab.TraitTermMapping
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Repo

  # What putting a waiting term again refreshes.
  @refreshed [:term, :package_id, :batch_id, :queue_item_id, :statement_ref, :evidence]

  @doc """
  Stores a term waiting on a question (`attrs` as
  `PendingTraitTerm.changeset/2` takes them). A Source's term on a Gall
  waits once: putting it again (a re-import) updates its origin, quotes
  and queue item, and leaves it settled if it was.
  """
  @spec put(Actor.t(), map()) :: {:ok, PendingTraitTerm.t()} | {:error, Changeset.t()}
  def put(%Actor{} = actor, attrs) when is_map(attrs) do
    Audit.transaction(actor, "catalog.put_pending_term", fn ->
      changeset = PendingTraitTerm.changeset(%PendingTraitTerm{}, attrs)

      result =
        with {:ok, valid} <- Changeset.apply_action(changeset, :insert) do
          case find(valid) do
            nil ->
              Repo.insert(changeset)

            existing ->
              existing
              |> PendingTraitTerm.changeset(Map.take(changeset.changes, @refreshed))
              |> Repo.update()
          end
        end

      ok_or_rollback(result)
    end)
  end

  defp find(%PendingTraitTerm{} = p) do
    Repo.one(
      from(t in PendingTraitTerm,
        where:
          t.gall_id == ^p.gall_id and t.source_id == ^p.source_id and t.trait == ^p.trait and
            t.normalized_term == ^p.normalized_term,
        lock: "FOR UPDATE"
      )
    )
  end

  @doc """
  The terms waiting on `gall_id`, by Trait then as stored. With
  `include_settled: true`, the settled ones too.
  """
  @spec list(integer(), keyword()) :: [PendingTraitTerm.t()]
  def list(gall_id, opts \\ []) when is_integer(gall_id) do
    query = from(t in PendingTraitTerm, where: t.gall_id == ^gall_id, order_by: [t.trait, t.id])

    query =
      if Keyword.get(opts, :include_settled, false),
        do: query,
        else: from(t in query, where: is_nil(t.settled_at))

    Repo.all(query)
  end

  @doc """
  Settles the waiting uses of `term` (compared normalized) for `trait`:
  under `categories` (a value of the Trait, or a list of them: each value
  the term names), or as text (`nil` or `[]`). Every
  Gall's and Source's by default (a term placed for every Source); narrowed
  by `:gall_ids`, `:source_id`, `:queue_item_id` or `:statement_refs` (the
  first Fact refs of the uses). Settled as text (`nil`), `:as` says why:
  `:no_fit` (the term fits no category) or `:kept` (a curator kept it as
  text for that Gall; the default). With `text: true`, the uses kept as
  text because the term fit no category are settled too (the term placed
  after all); a curator's `:kept` choice stands. `:at` is when (default
  now). Returns the uses settled, for the caller to write their Facts.
  """
  @spec settle(Actor.t(), String.t(), String.t(), String.t() | [String.t()] | nil, keyword()) ::
          {:ok, [PendingTraitTerm.t()]} | {:error, {:not_a_value, String.t(), String.t()}}
  def settle(%Actor{} = actor, trait, term, categories, opts \\ [])
      when is_binary(trait) and is_binary(term) do
    categories = categories |> List.wrap() |> Enum.uniq()

    Audit.transaction(actor, "catalog.settle_pending_terms", fn ->
      for category <- categories,
          !Repo.get_by(TraitValue, trait: trait, value: category),
          do: Repo.rollback({:not_a_value, trait, category})

      at = opts |> Keyword.get_lazy(:at, &DateTime.utc_now/0) |> DateTime.truncate(:second)
      settled_as = settled_as(categories, Keyword.get(opts, :as, :kept))

      {_count, settled} =
        from(t in PendingTraitTerm,
          where: t.trait == ^trait and t.normalized_term == ^TraitTermMapping.normalize(term),
          select: t
        )
        |> waiting(Keyword.get(opts, :text, false))
        |> narrow(opts)
        |> Repo.update_all(
          set: [
            settled_at: at,
            settled_categories: categories,
            settled_as: settled_as,
            updated_at: at
          ]
        )

      Enum.sort_by(settled, & &1.id)
    end)
  end

  @typedoc "A term that fits no category, with how many of its uses are kept as text."
  @type no_fit :: %{trait: String.t(), term: String.t(), uses: non_neg_integer()}

  @doc """
  The terms marked as fitting no category (`status` `:no_fit`), with how
  many uses are kept as text on a Gall for each (most first): for senior
  admins deciding whether a category is missing.
  """
  @spec list_no_fit() :: [no_fit()]
  def list_no_fit do
    from(m in TraitTermMapping,
      left_join: t in PendingTraitTerm,
      on:
        t.trait == m.trait and t.normalized_term == m.normalized_term and
          t.settled_as == "no_fit",
      where: m.status == :no_fit,
      group_by: [m.id, m.trait, m.term],
      order_by: [desc: count(t.id), asc: m.trait, asc: m.normalized_term],
      select: %{trait: m.trait, term: m.term, uses: count(t.id)}
    )
    |> Repo.all()
  end

  # The uses still waiting; with `text`, those kept as text because the term
  # fit no category too (never a curator's choice to keep one as text).
  defp waiting(query, false), do: from(t in query, where: is_nil(t.settled_at))

  defp waiting(query, true),
    do: from(t in query, where: is_nil(t.settled_at) or t.settled_as == "no_fit")

  defp settled_as([_ | _], _as), do: "category"
  defp settled_as([], as) when as in [:no_fit, :kept], do: Atom.to_string(as)

  defp narrow(query, opts) do
    Enum.reduce(opts, query, fn
      {:gall_ids, ids}, q -> from(t in q, where: t.gall_id in ^ids)
      {:source_id, id}, q -> from(t in q, where: t.source_id == ^id)
      {:queue_item_id, id}, q -> from(t in q, where: t.queue_item_id == ^id)
      {:statement_refs, refs}, q -> from(t in q, where: t.statement_ref in ^refs)
      {:at, _}, q -> q
      {:text, _}, q -> q
      {:as, _}, q -> q
    end)
  end

  defp ok_or_rollback({:ok, value}), do: value
  defp ok_or_rollback({:error, reason}), do: Repo.rollback(reason)
end
