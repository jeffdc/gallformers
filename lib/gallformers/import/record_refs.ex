defmodule Gallformers.Import.RecordRefs do
  @moduledoc """
  What in the import tables names a Gall, taxon or Fact being deleted or
  merged away (matter `ec2c`, "References held in JSON count"): the queue
  items' `subject`, `proposal` and `decision`, curators' edits on a
  package's Facts (`package_statement_edits.value`), and the batches'
  statements (`batch_statements`: their resolved taxon, Gall and Fact and
  their candidates).

  Galls and taxa share one ID sequence (`entity_id_seq`), so an entity ID
  names one record whichever it is; Fact IDs are a sequence of their own.
  JSON is read under the keys that hold them (`@entity_keys`,
  `@fact_keys`), at any depth.

  What is still being decided blocks a delete or merge: an open queue item
  (but a rename proposal for a Gall that goes, which is moot), an edit or
  statement of a batch not yet applied or denied, and — for a delete — a
  decided item of a package still under review (resolving it again would
  honour a decision naming what is gone). What is history is cleaned up
  with it (`clean_up/3`): a decided item keeps its decision with the IDs
  that go taken out (a rename proposal for a Gall that goes is deleted),
  an applied or denied batch's edits are deleted and its statements stop
  naming them. A merge re-points all of these to the survivor instead
  (`repoint/3`), decisions of packages under review included.
  """
  import Ecto.Query

  alias Gallformers.Import.Batch
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.Package
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.StatementEdit
  alias Gallformers.Repo
  alias Gallformers.Sources

  @entity_keys ~w(taxon_id host_taxon_id gall_id parent_id synonym_of chosen_parent_id
                  chosen_host_taxon_id inducer_id gallformers_gall_id gallformers_taxon_id
                  candidate_ids candidates proposed best accepted_taxon_id subject_taxon_id
                  object_taxon_id subject_gall_id object_gall_id merged_gall_id survivor_id
                  absorbed_id into_taxon_ids)
  @fact_keys ~w(fact_id fact_ids)

  @settled [:applied, :denied]

  @typedoc """
  The rows naming the records: `blocking` (still being decided) and
  `history` (cleaned up with them), each with its queue items, statement
  edits and batch statements.
  """
  @type found :: %{blocking: rows(), history: rows()}

  @typedoc "What `clean_up/3` reads: a `t:found/0`, or just its `history`."
  @type with_history :: %{required(:history) => rows(), optional(atom()) => term()}

  @typedoc "Queue items, statement edits and batch statements naming the records."
  @type rows :: %{
          items: [QueueItem.t()],
          edits: [StatementEdit.t()],
          statements: [BatchStatement.t()]
        }

  @doc """
  The import rows naming any of `entity_ids` (Galls and taxa) or
  `fact_ids`. `gall_ids` are the Galls that go: a rename proposal about
  one is history, not a blocker. Options: `for: :delete` (the default) or
  `:merge` — a merge re-points a decision of a package under review, so
  it does not block.
  """
  @spec find([integer()], [integer()], [integer()], keyword()) :: found()
  def find(entity_ids, fact_ids, gall_ids \\ [], opts \\ []) do
    entities = MapSet.new(entity_ids)
    facts = MapSet.new(fact_ids)

    items = queue_items(entities, facts)
    edits = statement_edits(entities)
    statements = batch_statements(entity_ids, fact_ids)
    open_batch? = fn batch_id -> batch_status(batch_id) not in @settled end
    merge? = Keyword.get(opts, :for, :delete) == :merge

    {moot, items} = Enum.split_with(items, &moot_rename?(&1, gall_ids))

    {blocking_items, decided} =
      Enum.split_with(items, fn item ->
        item.status == :open or (not merge? and in_review?(item.package_id))
      end)

    {open_edits, old_edits} = Enum.split_with(edits, &open_batch?.(&1.batch_id))
    {open_statements, old_statements} = Enum.split_with(statements, &open_batch?.(&1.batch_id))

    %{
      blocking: %{items: blocking_items, edits: open_edits, statements: open_statements},
      history: %{items: decided ++ moot, edits: old_edits, statements: old_statements}
    }
  end

  # A package still under review: a batch of it is neither applied nor denied.
  defp in_review?(nil), do: false

  defp in_review?(package_id) do
    Repo.exists?(
      from(b in Batch, where: b.package_id == ^package_id and b.status not in ^@settled)
    )
  end

  defp moot_rename?(%QueueItem{kind: :gall_rename, subject: %{"gall_id" => id}}, gall_ids),
    do: id in gall_ids

  defp moot_rename?(_item, _gall_ids), do: false

  defp queue_items(entities, facts) do
    ids = Enum.uniq(MapSet.to_list(entities) ++ MapSet.to_list(facts))

    ids
    |> Enum.chunk_every(400)
    |> Enum.flat_map(fn chunk ->
      pattern = "\\m(" <> Enum.map_join(chunk, "|", &Integer.to_string/1) <> ")\\M"

      from(q in QueueItem,
        where:
          fragment(
            "(?::text || ' ' || ?::text || ' ' || coalesce(?::text, '')) ~ ?",
            q.subject,
            q.proposal,
            q.decision,
            ^pattern
          ),
        order_by: q.id
      )
      |> Repo.all()
    end)
    |> Enum.uniq_by(& &1.id)
    |> Enum.filter(fn item ->
      Enum.any?([item.subject, item.proposal, item.decision], &mentions?(&1, entities, facts))
    end)
  end

  defp statement_edits(entities) do
    ids = MapSet.to_list(entities)

    from(e in StatementEdit,
      where: fragment("(?->>'host_taxon_id')::bigint = ANY(?)", e.value, ^ids),
      order_by: e.id
    )
    |> Repo.all()
  end

  defp batch_statements([], []), do: []

  defp batch_statements(entity_ids, fact_ids) do
    from(s in BatchStatement,
      where:
        s.taxon_id in ^entity_ids or s.gall_id in ^entity_ids or s.fact_id in ^fact_ids or
          fragment("? && ?", s.candidate_ids, type(^entity_ids, {:array, :integer})),
      order_by: s.id
    )
    |> Repo.all()
  end

  defp batch_status(batch_id),
    do: Repo.one!(from(b in Batch, where: b.id == ^batch_id, select: b.status))

  @doc "Whether `json` names one of `entities` or `facts` under the keys that hold them."
  @spec mentions?(term(), MapSet.t(), MapSet.t()) :: boolean()
  def mentions?(json, entities, facts) when is_map(json) do
    Enum.any?(json, fn
      {key, value} when key in @entity_keys -> holds?(value, entities, facts, entities)
      {key, value} when key in @fact_keys -> holds?(value, entities, facts, facts)
      {_key, value} -> mentions?(value, entities, facts)
    end)
  end

  def mentions?(json, entities, facts) when is_list(json),
    do: Enum.any?(json, &mentions?(&1, entities, facts))

  def mentions?(_json, _entities, _facts), do: false

  defp holds?(value, _entities, _facts, set) when is_integer(value),
    do: MapSet.member?(set, value)

  defp holds?(values, entities, facts, set) when is_list(values),
    do: Enum.any?(values, &holds?(&1, entities, facts, set))

  defp holds?(value, entities, facts, _set), do: mentions?(value, entities, facts)

  @doc """
  `json` with the entity IDs `entity_map` names replaced (`%{old => new}`)
  and the Fact IDs `fact_map` names (a Fact dropped maps to nil), under the
  keys that hold them. An ID replaced by nil is taken out of a list.
  """
  @spec replace(term(), map(), map()) :: term()
  def replace(json, entity_map, fact_map) when is_map(json) do
    Map.new(json, fn
      {key, value} when key in @entity_keys ->
        {key, swap(value, entity_map, fact_map, entity_map)}

      {key, value} when key in @fact_keys ->
        {key, swap(value, entity_map, fact_map, fact_map)}

      {key, value} ->
        {key, replace(value, entity_map, fact_map)}
    end)
  end

  def replace(json, entity_map, fact_map) when is_list(json),
    do: Enum.map(json, &replace(&1, entity_map, fact_map))

  def replace(json, _entity_map, _fact_map), do: json

  defp swap(value, _entities, _facts, map) when is_integer(value), do: Map.get(map, value, value)

  # An ID mapped to nil is taken out of a list.
  defp swap(values, entities, facts, map) when is_list(values) do
    for value <- values,
        swapped = swap(value, entities, facts, map),
        not (is_integer(value) and is_nil(swapped)),
        do: swapped
  end

  defp swap(value, entities, facts, _map), do: replace(value, entities, facts)

  # -- blockers and clean-up -----------------------------------------------------

  @doc """
  The blockers `found` holds, worded for `record_name`: review questions
  (open, or decided in a package under review) and packages under review
  naming it, one per package.
  """
  @spec blockers(found(), term(), String.t()) :: [map()]
  def blockers(%{blocking: blocking}, record, record_name) do
    questions =
      blocking.items
      |> Enum.group_by(& &1.package_id)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {package_id, items} ->
        where = package_label(package_id)
        n = length(items)
        verb = if n == 1, do: "names", else: "name"

        {what, action} =
          if Enum.all?(items, &(&1.status == :open)),
            do: {"open review question", "Decide #{if n == 1, do: "it", else: "them"} first."},
            else:
              {"review question", "Decide the open ones, and apply or deny the package, first."}

        %{
          kind: :open_question,
          record: record,
          record_name: record_name,
          source: package_source(package_id),
          count: n,
          text: "#{count(n, what)} #{where} #{verb} #{record_name}",
          action: action
        }
      end)

    packages =
      (blocking.edits ++ blocking.statements)
      |> Enum.group_by(& &1.batch_id)
      |> Enum.map(fn {batch_id, rows} -> {package_of_batch(batch_id), rows} end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {package_id, rows} ->
        %{
          kind: :package_under_review,
          record: record,
          record_name: record_name,
          source: package_source(package_id),
          count: rows |> List.flatten() |> length(),
          text: "A package under review #{package_label(package_id)} names #{record_name}",
          action: "Approve and apply it, or deny it, first."
        }
      end)

    questions ++ packages
  end

  @doc "What clean-up `found` means, by kind: `%{kind, count, text}`."
  @spec cleanup(found()) :: [map()]
  def cleanup(%{history: history}) do
    [
      {:queue_item, length(history.items), "decided review question"},
      {:statement_edit, length(history.edits), "edit on an applied or denied package's Fact"},
      {:batch_statement, length(history.statements), "statement of an applied or denied batch"}
    ]
    |> Enum.filter(fn {_kind, n, _what} -> n > 0 end)
    |> Enum.map(fn {kind, n, what} -> %{kind: kind, count: n, text: count(n, what)} end)
  end

  @doc """
  Cleans up the history `found` holds (only its `history` is read), for
  records that go: a decided
  item stops naming `entity_ids` and `fact_ids` (taken out of lists, nil
  where one stood alone), a rename proposal about a Gall that goes is
  deleted, edits are deleted, and statements stop naming them (their
  resolved IDs cleared, their candidates dropped).
  """
  @spec clean_up(with_history(), [integer()], [integer()]) :: :ok
  def clean_up(%{history: history}, entity_ids, fact_ids) do
    {renames, items} = Enum.split_with(history.items, &moot_rename?(&1, entity_ids))
    delete_rows(QueueItem, renames)
    gone_entities = Map.new(entity_ids, &{&1, nil})
    gone_facts = Map.new(fact_ids, &{&1, nil})

    for item <- items do
      item
      |> Ecto.Changeset.change(
        subject: replace(item.subject, gone_entities, gone_facts),
        proposal: replace(item.proposal, gone_entities, gone_facts),
        decision: replace(item.decision, gone_entities, gone_facts)
      )
      |> Repo.update!()
    end

    delete_rows(StatementEdit, history.edits)

    for s <- history.statements do
      s
      |> Ecto.Changeset.change(
        taxon_id: if(s.taxon_id in entity_ids, do: nil, else: s.taxon_id),
        gall_id: if(s.gall_id in entity_ids, do: nil, else: s.gall_id),
        fact_id: if(s.fact_id in fact_ids, do: nil, else: s.fact_id),
        candidate_ids: s.candidate_ids -- entity_ids
      )
      |> Repo.update!()
    end

    :ok
  end

  @doc """
  Re-points the history `found` holds to a merge's survivor: `entity_map`
  and `fact_map` (`%{old => new}`, a dropped Fact to nil) replace the IDs
  in decided items, edits and statements; a rename proposal about the
  absorbed Gall is deleted.
  """
  @spec repoint(found(), map(), map()) :: :ok
  def repoint(%{history: history}, entity_map, fact_map) do
    {moot, decided} = Enum.split_with(history.items, &moot_rename?(&1, Map.keys(entity_map)))
    delete_rows(QueueItem, moot)

    for item <- decided do
      item
      |> Ecto.Changeset.change(
        subject: replace(item.subject, entity_map, fact_map),
        proposal: replace(item.proposal, entity_map, fact_map),
        decision: replace(item.decision, entity_map, fact_map)
      )
      |> Repo.update!()
    end

    for edit <- history.edits do
      edit
      |> Ecto.Changeset.change(value: replace(edit.value, entity_map, fact_map))
      |> Repo.update!()
    end

    for s <- history.statements do
      s
      |> Ecto.Changeset.change(
        taxon_id: s.taxon_id && Map.get(entity_map, s.taxon_id, s.taxon_id),
        gall_id: s.gall_id && Map.get(entity_map, s.gall_id, s.gall_id),
        fact_id: s.fact_id && Map.get(fact_map, s.fact_id, s.fact_id),
        candidate_ids: s.candidate_ids |> Enum.map(&Map.get(entity_map, &1, &1)) |> Enum.uniq()
      )
      |> Repo.update!()
    end

    :ok
  end

  defp delete_rows(_schema, []), do: :ok

  defp delete_rows(schema, rows) do
    ids = Enum.map(rows, & &1.id)
    Repo.delete_all(from(r in schema, where: r.id in ^ids))
    :ok
  end

  defp package_of_batch(batch_id),
    do: Repo.one!(from(b in Batch, where: b.id == ^batch_id, select: b.package_id))

  defp package_label(nil), do: "outside any package"

  defp package_label(package_id) do
    package = Repo.get!(Package, package_id)

    case package_source(package_id) do
      %{name: name} -> "in #{name}'s package #{package.key}"
      nil -> "in package #{package.key}"
    end
  end

  defp package_source(nil), do: nil

  defp package_source(package_id) do
    with %Package{source_id: id} when is_integer(id) <- Repo.get(Package, package_id),
         %{} = source <- Sources.get_source(id) do
      %{id: source.id, title: source.title, name: Sources.short_name(source) || source.title}
    else
      _ -> nil
    end
  end

  defp count(1, what), do: "1 #{what}"
  defp count(n, what), do: "#{n} #{what}s"
end
