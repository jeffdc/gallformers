defmodule Gallformers.Facts do
  @moduledoc """
  Facts, their attributions to Sources, and their standings (`9449` §2;
  reasons in `8567` *Sources–Facts design*).

  A Fact (`Gallformers.Facts.Fact`) stands on its own; Sources attach to it
  with a stance through attributions (`Gallformers.Facts.Attribution`), one
  per Fact and Source. A Fact's `standing` is precomputed from its
  attributions by the pure rules in `Gallformers.Facts.Standing`, and every
  function here that changes attributions recomputes, in the same
  transaction, the standings of the Facts it touched and of their slot
  siblings. Rules the standings cannot settle come back as
  `Gallformers.Facts.Standing.Conflict`s for the caller to queue.

  The typed details of each kind of Fact live in tables owned by `Catalog`
  and `Taxa`, keyed by `fact_id`; this context never depends on them, and
  depends only on `Sources` (Source dates, retractions, quote location) and
  `Audit`.

  Every write is audited (`Gallformers.Audit`) as the given actor. Calls can
  be nested inside an outer `Gallformers.Audit.transaction/3` with the same
  actor, e.g. by `Catalog` creating a Fact and its details and attributing
  it in one transaction.

  ## Concurrency

  Attribution writes lock the Facts they recompute (the Fact and its slot
  siblings, in ID order), so concurrent writes to one Fact or slot run one
  after the other and each sees the other's result. A Fact's slot never
  changes.
  """
  use Boundary,
    deps: [Gallformers.Audit, Gallformers.Repo, Gallformers.Sources],
    exports: [
      Attribution,
      AttributionName,
      AttributionObservation,
      Evidence,
      Fact,
      Standing,
      Standing.Conflict
    ]

  import Ecto.Query

  alias Ecto.Changeset
  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Facts.Attribution
  alias Gallformers.Facts.AttributionName
  alias Gallformers.Facts.AttributionObservation
  alias Gallformers.Facts.Evidence
  alias Gallformers.Facts.Fact
  alias Gallformers.Facts.Standing
  alias Gallformers.Facts.Standing.Conflict
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Sources.Source

  @children [
    evidence: Evidence,
    names: AttributionName,
    observations: AttributionObservation
  ]

  @type attribute_result :: %{attribution: Attribution.t(), conflicts: [Conflict.t()]}

  # -- Facts -------------------------------------------------------------------

  @doc """
  Creates a Fact of `kind`, in `slot` if it competes for a single value
  (e.g. `%{kind: "trait", slot: "gall:123:detachable"}`).

  A new Fact is `:unsupported` until something attributes it.
  """
  @spec create_fact(Actor.t(), map()) :: {:ok, Fact.t()} | {:error, Changeset.t()}
  def create_fact(%Actor{} = actor, attrs) when is_map(attrs) do
    Audit.transaction(actor, "facts.create_fact", fn ->
      case %Fact{} |> Fact.create_changeset(attrs) |> Repo.insert() do
        {:ok, fact} -> fact
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "Gets a Fact by ID, raising if there is none."
  @spec get_fact!(integer()) :: Fact.t()
  def get_fact!(id), do: Repo.get!(Fact, id)

  @doc """
  A Fact's attributions, oldest first, with their evidence, names and
  Observations.
  """
  @spec list_attributions(Fact.t() | integer()) :: [Attribution.t()]
  def list_attributions(%Fact{id: id}), do: list_attributions(id)

  def list_attributions(fact_id) when is_integer(fact_id) do
    from(a in Attribution,
      where: a.fact_id == ^fact_id,
      order_by: a.id,
      preload: ^Keyword.keys(@children)
    )
    |> Repo.all()
  end

  # -- Attributions ------------------------------------------------------------

  @doc """
  Records Source `source_id`'s stance on Fact `fact_id`, then recomputes the
  standings of the Fact and its slot siblings.

  There is one attribution per Fact and Source: if the Source already has
  one it is updated (a re-import, or a newer Gallformers statement replacing
  Gallformers' previous one), and audit keeps the values it replaced.

  `attrs` is a map with atom keys:

    * `:fact_id`, `:source_id`, `:stance` (`:confirm | :deny`) — required
    * `:stated` — a partial date (`"1897"`, `"1897-05"`, `"1897-05-14"`) or
      nil for an undated statement; when absent, the Source's authored date
    * `:value_as_written`, `:batch_id`, `:when_as_written`,
      `:stage_as_written`, `:status_as_written`, `:authorship_as_written`
    * `:statement_text` — required for the Gallformers Source
    * `:evidence` — a list of `%{document_item_id, quote}` or
      `%{document_item_id, whole_item: true}` (or a bare `quote` when the
      Source has no stored document), each with optional `page`, `url` and
      `cites_as_written`. A quote is located in its item and its span stored;
      a quote not in its item is an error.
    * `:names` — a list of `%{taxon_id, name_as_written, name_reading, role}`
    * `:observations` — a list of `%{provider, external_id, url}`

  The three lists state the attribution's whole evidence, names and
  Observations: on an update they replace what was there (a missing list is
  empty). Children equal to the stored ones are left untouched, so
  attributing the same content again writes nothing.

  Returns the stored attribution (with its children) and any conflicts the
  standing rules found among the Facts recomputed. On error nothing is
  written and the changeset says why (child errors are under `:evidence`,
  `:names`, `:observations`).
  """
  @spec attribute(Actor.t(), map()) :: {:ok, attribute_result()} | {:error, Changeset.t()}
  def attribute(%Actor{} = actor, %{fact_id: fact_id, source_id: source_id} = attrs)
      when is_integer(fact_id) and is_integer(source_id) do
    Audit.transaction(actor, "facts.attribute", fn ->
      lock_facts([fact_id])

      with {:ok, source} <- fetch_source(source_id),
           {:ok, attribution} <- upsert_attribution(source, attrs) do
        %{attribution: attribution, conflicts: recompute([fact_id])}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Removes Source `source_id`'s attribution of Fact `fact_id` (with its
  evidence, names and Observations), as when a re-import no longer states
  the Fact, then recomputes the standings of the Fact and its slot siblings.
  A Fact left with no attributions becomes `:unsupported`; audit keeps what
  was removed.

  Returns the conflicts found, or `{:error, :not_found}`.
  """
  @spec remove_attribution(Actor.t(), integer(), integer()) ::
          {:ok, [Conflict.t()]} | {:error, :not_found}
  def remove_attribution(%Actor{} = actor, fact_id, source_id)
      when is_integer(fact_id) and is_integer(source_id) do
    Audit.transaction(actor, "facts.remove_attribution", fn ->
      lock_facts([fact_id])

      case Repo.get_by(Attribution, fact_id: fact_id, source_id: source_id) do
        nil ->
          Repo.rollback(:not_found)

        attribution ->
          Repo.delete!(attribution)
          recompute([fact_id])
      end
    end)
  end

  @doc """
  Recomputes the standings of every Fact Source `source_id` attributes, and
  of their slot siblings. Call it after the Source is retracted (or its
  retraction is undone), since a retraction cancels all its stances.

  Returns the conflicts found.
  """
  @spec recompute_for_source(Actor.t(), integer()) :: {:ok, [Conflict.t()]}
  def recompute_for_source(%Actor{} = actor, source_id) when is_integer(source_id) do
    Audit.transaction(actor, "facts.recompute_for_source", fn ->
      from(a in Attribution, where: a.source_id == ^source_id, distinct: true, select: a.fact_id)
      |> Repo.all()
      |> recompute()
    end)
  end

  @doc """
  Source `source_id`'s attributions of Facts whose kind starts with
  `kind_prefix` (e.g. `"gall_"`, `"taxon_"`), with their evidence, names and
  Observations, by Fact ID. An import diffs a batch against these.
  """
  @spec list_source_attributions(integer(), String.t()) :: %{integer() => Attribution.t()}
  def list_source_attributions(source_id, kind_prefix)
      when is_integer(source_id) and is_binary(kind_prefix) do
    from(a in Attribution,
      join: f in assoc(a, :fact),
      where: a.source_id == ^source_id and like(f.kind, ^"#{kind_prefix}%"),
      preload: ^Keyword.keys(@children)
    )
    |> Repo.all()
    |> Map.new(&{&1.fact_id, &1})
  end

  @doc """
  Whether attributing `attrs` (as `attribute/2` takes them) would leave the
  stored `attribution` (with its children loaded) as it is, apart from
  `:batch_id`. An import uses it to leave restated attributions untouched,
  so they get no write and no audit rows.
  """
  @spec attribution_unchanged?(Attribution.t(), map()) :: boolean()
  def attribution_unchanged?(%Attribution{source_id: source_id} = attribution, attrs) do
    case fetch_source(source_id) do
      {:ok, source} ->
        changeset = attribution_changeset(attribution, source, attrs)
        changeset.valid? and map_size(Map.delete(changeset.changes, :batch_id)) == 0

      {:error, _changeset} ->
        false
    end
  end

  @doc """
  Whether another Fact in `fact`'s slot is current: a confirmation of
  `fact` would compete with it (an import counts it as replacing).
  """
  @spec other_current_in_slot?(Fact.t()) :: boolean()
  def other_current_in_slot?(%Fact{slot: nil}), do: false

  def other_current_in_slot?(%Fact{id: id, slot: slot}) do
    Repo.exists?(
      from(f in Fact, where: f.slot == ^slot and f.id != ^id and f.standing == :current)
    )
  end

  # -- upsert ------------------------------------------------------------------

  defp fetch_source(source_id) do
    case Sources.get_source(source_id) do
      %Source{} = source ->
        {:ok, source}

      nil ->
        changeset =
          %Attribution{}
          |> Changeset.change()
          |> Changeset.add_error(:source_id, "does not exist")

        {:error, %{changeset | action: :insert}}
    end
  end

  defp upsert_attribution(source, %{fact_id: fact_id} = attrs) do
    existing =
      from(a in Attribution,
        where: a.fact_id == ^fact_id and a.source_id == ^source.id,
        preload: ^Keyword.keys(@children)
      )
      |> Repo.one()

    existing
    |> attribution_changeset(source, attrs)
    |> Repo.insert_or_update()
  end

  # The changeset attributing `attrs` over `existing` (nil for a new one),
  # leaving children equal to the stored ones untouched.
  defp attribution_changeset(existing, source, attrs) do
    attrs = Enum.reduce(Keyword.keys(@children), attrs, &Map.put_new(&2, &1, []))

    (existing || %Attribution{})
    |> Attribution.changeset(attrs, source)
    |> Changeset.cast_assoc(:evidence,
      with: fn evidence, params ->
        Evidence.changeset(evidence, params, &Sources.locate_quote/2)
      end
    )
    |> Changeset.cast_assoc(:names, with: &AttributionName.changeset/2)
    |> Changeset.cast_assoc(:observations, with: &AttributionObservation.changeset/2)
    |> keep_unchanged_children(existing)
  end

  # Children equal to the stored ones are not rewritten, so restating an
  # attribution leaves no audit changes.
  defp keep_unchanged_children(changeset, nil), do: changeset

  defp keep_unchanged_children(changeset, %Attribution{} = existing) do
    Enum.reduce(@children, changeset, fn {assoc, schema}, acc ->
      with {:ok, children} <- Changeset.fetch_change(acc, assoc),
           true <- Enum.all?(children, & &1.valid?),
           new = for(c <- children, c.action != :replace, do: Changeset.apply_changes(c)),
           true <- contents(new, schema) == contents(Map.fetch!(existing, assoc), schema) do
        Changeset.delete_change(acc, assoc)
      else
        _ -> acc
      end
    end)
  end

  defp contents(children, schema) do
    fields = schema.content_fields()
    children |> Enum.map(&Map.take(&1, fields)) |> Enum.sort()
  end

  # -- standings -----------------------------------------------------------

  # Locks the Facts and their slot siblings, in ID order, and returns them.
  defp lock_facts([]), do: []

  defp lock_facts(fact_ids) do
    slots =
      from(f in Fact,
        where: f.id in ^fact_ids and not is_nil(f.slot),
        distinct: true,
        select: f.slot
      )
      |> Repo.all()

    from(f in Fact,
      where: f.id in ^fact_ids or f.slot in ^slots,
      order_by: f.id,
      lock: "FOR UPDATE"
    )
    |> Repo.all()
  end

  # Recomputes and stores the standings of `fact_ids` and their slot
  # siblings; returns the conflicts found.
  defp recompute(fact_ids) do
    facts = lock_facts(fact_ids)
    ids = Enum.map(facts, & &1.id)

    attributions =
      from(a in Attribution,
        where: a.fact_id in ^ids,
        select: map(a, [:id, :fact_id, :source_id, :stance, :stated_on, :stated_precision])
      )
      |> Repo.all()

    retracted =
      attributions
      |> Enum.map(& &1.source_id)
      |> Enum.uniq()
      |> Sources.retracted_source_ids()
      |> Map.new(&{&1, true})

    by_fact =
      Enum.group_by(attributions, & &1.fact_id, fn a ->
        Map.put(a, :retracted, Map.has_key?(retracted, a.source_id))
      end)

    {standings, conflicts} =
      facts
      |> Enum.map(fn fact ->
        %{
          id: fact.id,
          slot: fact.slot,
          previous: fact.standing,
          attributions: Map.get(by_fact, fact.id, [])
        }
      end)
      |> Enum.group_by(& &1.slot)
      |> Enum.flat_map(fn
        {nil, unslotted} -> Enum.map(unslotted, &Standing.resolve/1)
        {_slot, slotted} -> [Standing.resolve_slot(slotted)]
      end)
      |> Enum.reduce({%{}, []}, fn {standings, conflicts}, {all_standings, all_conflicts} ->
        {Map.merge(all_standings, standings), all_conflicts ++ conflicts}
      end)

    store_standings(facts, standings)
    conflicts
  end

  defp store_standings(facts, standings) do
    now = DateTime.utc_now(:second)

    facts
    |> Enum.reject(fn fact -> Map.fetch!(standings, fact.id) == fact.standing end)
    |> Enum.group_by(&Map.fetch!(standings, &1.id), & &1.id)
    |> Enum.each(fn {standing, ids} ->
      from(f in Fact, where: f.id in ^ids)
      |> Repo.update_all(set: [standing: standing, updated_at: now])
    end)
  end
end
