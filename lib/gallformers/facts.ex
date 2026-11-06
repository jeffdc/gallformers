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

  ## Events

  After storing recomputed standings, the write calls the registered
  "Facts changed" listeners with the Facts whose standing changed
  (`Gallformers.Facts.Events`), inside its transaction: how the Catalog's
  read models hear about changes without Facts depending on the Catalog.

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
      Events,
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
  alias Gallformers.Facts.Events
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

  @doc """
  The attributions of the Facts among `fact_ids`, by Fact ID, each oldest
  first with its evidence, names and Observations (as `list_attributions/1`).
  A Fact with none is absent from the map.
  """
  @spec list_attributions_for_facts([integer()]) :: %{integer() => [Attribution.t()]}
  def list_attributions_for_facts([]), do: %{}

  def list_attributions_for_facts(fact_ids) when is_list(fact_ids) do
    from(a in Attribution,
      where: a.fact_id in ^fact_ids,
      order_by: a.id,
      preload: ^Keyword.keys(@children)
    )
    |> Repo.all()
    |> Enum.group_by(& &1.fact_id)
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
    * `:value_as_written`, `:term` (a Trait's term), `:batch_id`, `:when_as_written`,
      `:stage_as_written`, `:status_as_written`, `:authorship_as_written`
    * `:statement_text` — required for the Gallformers Source
    * `:cites_as_written`, `:cited_source_id` — the Source a Gallformers
      statement follows, as named and as held
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
  Moves attribution `attribution_id` (with its evidence, names and
  Observations) onto Fact `to_fact_id`, as when a Source's Trait term is
  moved to another category (`d213`), then recomputes the standings of
  both Facts and their slot siblings. When the Source already attributes
  the target Fact, that attribution stands (its stance and date) and gains
  the moved one's evidence, names and Observations it lacks, so no quote is
  lost; the moved one is removed (one attribution per Fact and Source).

  Returns `%{moved: true | false, conflicts}` (`moved` false when the
  target's own attribution stood), or `{:error, :not_found}`.
  """
  @spec move_attribution(Actor.t(), integer(), integer()) ::
          {:ok, %{moved: boolean(), conflicts: [Conflict.t()]}} | {:error, :not_found}
  def move_attribution(%Actor{} = actor, attribution_id, to_fact_id)
      when is_integer(attribution_id) and is_integer(to_fact_id) do
    Audit.transaction(actor, "facts.move_attribution", fn ->
      with %Attribution{} = attribution <- Repo.get(Attribution, attribution_id),
           %Fact{} <- Repo.get(Fact, to_fact_id) do
        from_fact_id = attribution.fact_id
        lock_facts(Enum.uniq([from_fact_id, to_fact_id]))

        moved =
          cond do
            from_fact_id == to_fact_id ->
              false

            existing =
                Repo.one(
                  from(a in Attribution,
                    where: a.fact_id == ^to_fact_id and a.source_id == ^attribution.source_id,
                    select: a.id
                  )
                ) ->
              combine_children(attribution.id, existing)
              Repo.delete!(attribution)
              false

            true ->
              attribution |> Changeset.change(fact_id: to_fact_id) |> Repo.update!()
              true
          end

        %{moved: moved, conflicts: recompute(Enum.uniq([from_fact_id, to_fact_id]))}
      else
        nil -> Repo.rollback(:not_found)
      end
    end)
  end

  # Moves attribution `from_id`'s evidence, names and Observations to
  # attribution `to_id`, leaving out those it holds already, so a Source's
  # quotes are kept when its statements of two Facts become one.
  defp combine_children(from_id, to_id) do
    for {_assoc, module} <- @children do
      fields = module.content_fields()
      content = &Map.take(&1, fields)

      held =
        from(c in module, where: c.attribution_id == ^to_id)
        |> Repo.all()
        |> MapSet.new(content)

      ids =
        from(c in module, where: c.attribution_id == ^from_id)
        |> Repo.all()
        |> Enum.reject(&MapSet.member?(held, content.(&1)))
        |> Enum.uniq_by(content)
        |> Enum.map(& &1.id)

      Repo.update_all(from(c in module, where: c.id in ^ids), set: [attribution_id: to_id])
    end
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
  When each of `source_ids` last had an attribution written (made or
  changed: its `updated_at`), by Source ID; a Source with none is absent.
  A removed attribution leaves no time here.
  """
  @spec last_attribution_changes([integer()]) :: %{integer() => DateTime.t()}
  def last_attribution_changes([]), do: %{}

  def last_attribution_changes(source_ids) when is_list(source_ids) do
    from(a in Attribution,
      where: a.source_id in ^source_ids,
      group_by: a.source_id,
      select: {a.source_id, max(a.updated_at)}
    )
    |> Repo.all()
    |> Map.new()
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
  The Sources attributing each of `fact_ids`, by Fact ID, each list in
  Source ID order. A Fact nothing attributes is absent.
  """
  @spec source_ids_by_fact([integer()]) :: %{integer() => [integer()]}
  def source_ids_by_fact([]), do: %{}

  def source_ids_by_fact(fact_ids) when is_list(fact_ids) do
    from(a in Attribution,
      where: a.fact_id in ^fact_ids,
      order_by: [a.fact_id, a.source_id],
      select: {a.fact_id, a.source_id}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  # -- deleting and moving (matter `ec2c`, "Deletes") --------------------------

  @doc """
  Deletes Facts `fact_ids` with their attributions (and the attributions'
  evidence, names and Observations), as when the Gall or taxon they are
  about is deleted; then recomputes the standings of the slot siblings
  that remain. The typed details of each Fact (owned by `Catalog` and
  `Taxa`) must be deleted first; audit keeps what was removed.

  Returns the conflicts found among the siblings.
  """
  @spec delete_facts(Actor.t(), [integer()]) :: {:ok, [Conflict.t()]}
  def delete_facts(%Actor{} = actor, fact_ids) when is_list(fact_ids) do
    Audit.transaction(actor, "facts.delete_facts", fn ->
      ids = Enum.uniq(fact_ids)
      locked = lock_facts(ids)
      siblings = for f <- locked, f.id not in ids, do: f.id

      Repo.delete_all(from(a in Attribution, where: a.fact_id in ^ids))
      Repo.delete_all(from(f in Fact, where: f.id in ^ids))

      recompute(siblings)
    end)
  end

  @typedoc "An attribution's name of a taxon (`Gallformers.Facts.AttributionName`), with its Fact and Source."
  @type taxon_name_use :: %{
          id: integer(),
          attribution_id: integer(),
          fact_id: integer(),
          source_id: integer(),
          taxon_id: integer()
        }

  @doc "The attributions' names of the taxa among `taxon_ids` (a Source naming them as written)."
  @spec names_of_taxa([integer()]) :: [taxon_name_use()]
  def names_of_taxa([]), do: []

  def names_of_taxa(taxon_ids) when is_list(taxon_ids) do
    from(n in AttributionName,
      join: a in Attribution,
      on: a.id == n.attribution_id,
      where: n.taxon_id in ^taxon_ids,
      order_by: n.id,
      select: %{
        id: n.id,
        attribution_id: a.id,
        fact_id: a.fact_id,
        source_id: a.source_id,
        taxon_id: n.taxon_id
      }
    )
    |> Repo.all()
  end

  @doc """
  Deletes the attribution names `name_ids` (`names_of_taxa/1`): a Gall or
  taxon deleted takes the names its own Sources' statements gave it.
  Returns how many were deleted.
  """
  @spec delete_attribution_names(Actor.t(), [integer()]) :: {:ok, non_neg_integer()}
  def delete_attribution_names(%Actor{} = actor, name_ids) when is_list(name_ids) do
    Audit.transaction(actor, "facts.delete_attribution_names", fn ->
      {count, _} = Repo.delete_all(from(n in AttributionName, where: n.id in ^name_ids))
      count
    end)
  end

  @doc """
  Makes every attribution name of taxon `from_taxon_id` name `to_taxon_id`
  instead, as when one plant is merged into another. Returns how many
  changed.
  """
  @spec repoint_attribution_names(Actor.t(), integer(), integer()) :: {:ok, non_neg_integer()}
  def repoint_attribution_names(%Actor{} = actor, from_taxon_id, to_taxon_id)
      when is_integer(from_taxon_id) and is_integer(to_taxon_id) do
    Audit.transaction(actor, "facts.repoint_attribution_names", fn ->
      {count, _} =
        from(n in AttributionName, where: n.taxon_id == ^from_taxon_id)
        |> Repo.update_all(set: [taxon_id: to_taxon_id])

      count
    end)
  end

  @doc """
  Makes evidence quoting document item `from` quote `to` instead, by
  `%{from => to}` (two copies of one stored text, as when a merged Gall's
  note duplicates the survivor's). Returns how many changed.
  """
  @spec repoint_evidence_items(Actor.t(), %{integer() => integer()}) :: {:ok, non_neg_integer()}
  def repoint_evidence_items(%Actor{} = actor, item_map) when is_map(item_map) do
    Audit.transaction(actor, "facts.repoint_evidence_items", fn ->
      Enum.reduce(item_map, 0, fn {from, to}, count ->
        {n, _} =
          from(e in Evidence, where: e.document_item_id == ^from)
          |> Repo.update_all(set: [document_item_id: to])

        count + n
      end)
    end)
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

    case store_standings(facts, standings) do
      [] -> :ok
      changed -> Events.dispatch(changed)
    end

    conflicts
  end

  # Stores the standings that changed; returns those Facts' IDs.
  defp store_standings(facts, standings) do
    now = DateTime.utc_now(:second)

    changed = Enum.reject(facts, fn fact -> Map.fetch!(standings, fact.id) == fact.standing end)

    changed
    |> Enum.group_by(&Map.fetch!(standings, &1.id), & &1.id)
    |> Enum.each(fn {standing, ids} ->
      from(f in Fact, where: f.id in ^ids)
      |> Repo.update_all(set: [standing: standing, updated_at: now])
    end)

    Enum.map(changed, & &1.id)
  end
end
