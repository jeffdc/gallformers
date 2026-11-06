defmodule Gallformers.Audit.ChangeLog do
  @moduledoc """
  What curators changed: their audited transactions (Carbonite's
  `transactions` and `changes`), grouped and described down to each Fact,
  for the admin dashboard and Changes page (matters bc0d, 15db).

  A change is one transaction by a `:user` actor. System work (packages
  received, checked, re-run) and a curator's re-check of an import (no Fact
  changes) are left out. Consecutive changes by the same curator, of the
  same operation, on the same Source, form one group, which lists:

    * the Source its import belongs to (through the package its changes
      name), if any;
    * each Fact it wrote, in words ("host: Quercus alba", "range exclude:
      Europe"), with its Gall (or taxon) and what happened to it: `:added`,
      or the standing it reached (`:current` is `:made_current`,
      `:superseded`, `:withdrawn`); a Fact added and made current in one
      group reads as added;
    * the Galls it touched (through their Facts or their own rows);
    * the taxon names it added, and the other taxa it touched, each with
      its rank and kingdom;
    * the questions it decided.

  Plain SQL over the audit trail and the tables it names, so it depends on
  nothing but the Repo.
  """
  alias Gallformers.Repo

  @left_out ["import.resolve_package"]

  # Operations counted in their title ("Decided 6 questions").
  @counted %{
    "import.decide_queue_item" => {"Decided", "a question", "questions"},
    "import.apply_batch" => {"Applied", "an import", "imports"},
    "import.approve_package" => {"Approved", "an import", "imports"},
    "import.deny_package" => {"Turned down", "an import", "imports"},
    "import.deny_batch" => {"Turned down", "a batch", "batches"}
  }

  # Every other operation a curator makes, in words.
  @worded %{
    "import.accept_proposals" => "Accepted proposed answers",
    "import.decide_group" => "Decided questions together",
    "import.apply_set_aside_decision" => "Decided a set-aside statement",
    "import.hold_package" => "Held an import",
    "import.edit_fact" => "Changed a Fact before approval",
    "import.remove_fact_edit" => "Undid a change to a Fact before approval",
    "import.add_note" => "Added a note to an import",
    "import.reject_proposal" => "Rejected a proposed answer",
    "import.restore_proposal" => "Restored a proposed answer",
    "import.place_term" => "Placed a trait term",
    "import.settle_placed_term" => "Placed a trait term",
    "import.decide_term_candidate" => "Placed a trait term",
    "import.record_term_edit" => "Edited a trait term",
    "import.record_trait_value_added" => "Added a trait category",
    "import.record_taxonomy_edit" => "Edited the taxonomy",
    "import.record_synonym_added" => "Added a synonym",
    "import.record_plant_added" => "Added a plant",
    "import.record_wcvp_edit" => "Edited a plant's WCVP record",
    "import.record_source_edit" => "Edited a Source",
    "catalog.create_gall" => "Created a Gall",
    "catalog.update_gall_editorial" => "Edited a Gall",
    "catalog.update_name_parts" => "Changed a Gall's name",
    "catalog.accept_gall_rename" => "Accepted a Gall rename",
    "catalog.add_trait_value" => "Added a trait category",
    "catalog.move_term_attributions" => "Moved a trait term",
    "taxa.create_taxon" => "Added a taxon",
    "taxa.rename" => "Renamed a taxon",
    "taxa.place" => "Moved a taxon",
    "taxa.add_synonym" => "Added a synonym",
    "taxa.remove_synonym" => "Removed a synonym",
    "taxa.add_common_name" => "Added a common name",
    "taxa.remove_common_name" => "Removed a common name",
    "taxa.update_editorial" => "Edited a taxon",
    "taxa.delete_taxon" => "Deleted a taxon",
    "ranges.update_taxon_places" => "Edited a host range",
    "sources.store_note" => "Edited a Gallformers note",
    "sources.update_source_details" => "Edited a Source",
    "sources.retract_source" => "Marked a Source retracted",
    "sources.unretract_source" => "Withdrew a Source's retraction"
  }

  @typedoc "A Gall a change names."
  @type subject :: %{id: integer(), name: String.t()}

  @typedoc "A taxon a change names, with what picks its public page."
  @type taxon :: %{
          id: integer(),
          name: String.t(),
          rank: String.t() | nil,
          kingdom: String.t() | nil
        }

  @type fact :: %{
          id: integer(),
          change: :added | :made_current | :superseded | :withdrawn | :unsupported,
          what: String.t() | nil,
          gall: subject() | nil,
          taxon: map() | nil
        }

  @type group :: %{
          key: String.t(),
          who: String.t(),
          operation: String.t(),
          title: String.t(),
          at: NaiveDateTime.t(),
          first_at: NaiveDateTime.t(),
          count: pos_integer(),
          source: %{id: integer(), title: String.t()} | nil,
          galls: [subject()],
          facts: [fact()],
          counts: %{atom() => pos_integer()},
          names: [taxon()],
          taxa: [taxon()],
          decided: non_neg_integer()
        }

  @doc """
  The curators' latest changes, grouped, newest first. Options: `:limit`,
  the transactions read (default 200); `:since`, a `NaiveDateTime` (UTC):
  only changes after it.
  """
  @spec groups(keyword()) :: [group()]
  def groups(opts \\ []) do
    txs = transactions(Keyword.get(opts, :limit, 200), opts[:since])
    fact_changes = txs |> Enum.map(& &1.id) |> fact_changes()
    described = fact_changes |> Enum.map(& &1.fact_id) |> Enum.uniq() |> describe()
    by_tx = Enum.group_by(fact_changes, & &1.tx)

    txs
    |> Enum.map(fn t ->
      facts =
        for f <- Map.get(by_tx, t.id, []),
            d = described[f.fact_id],
            do: Map.put(d, :change, f.change)

      Map.put(t, :facts, facts)
    end)
    |> Enum.chunk_while(nil, &chunk/2, fn
      nil -> {:cont, nil}
      group -> {:cont, group, nil}
    end)
    |> Enum.map(&finish/1)
  end

  defp chunk(t, nil), do: {:cont, start(t)}

  defp chunk(t, group) do
    if group.who == t.who and group.operation == t.operation and group.source == t.source,
      do: {:cont, merge(group, t)},
      else: {:cont, group, start(t)}
  end

  defp start(t) do
    %{
      key: "change-#{t.id}",
      who: t.who,
      operation: t.operation,
      at: t.at,
      first_at: t.at,
      count: 1,
      source: t.source,
      facts: t.facts,
      names: t.names,
      taxa: t.taxa,
      edited_galls: t.edited_galls,
      decided: t.decided
    }
  end

  defp merge(group, t) do
    %{
      group
      | first_at: t.at,
        count: group.count + 1,
        facts: group.facts ++ t.facts,
        names: group.names ++ t.names,
        taxa: group.taxa ++ t.taxa,
        edited_galls: group.edited_galls ++ t.edited_galls,
        decided: group.decided + t.decided
    }
  end

  defp finish(group) do
    facts =
      group.facts
      |> Enum.group_by(& &1.id)
      |> Enum.map(fn {_id, fs} -> Enum.find(fs, &(&1.change == :added)) || List.last(fs) end)
      |> Enum.sort_by(&{(&1.gall || &1.taxon || %{name: ""}).name, &1.what || ""})

    names = Enum.uniq_by(group.names, & &1.id)
    new_ids = MapSet.new(names, & &1.id)

    group
    |> Map.drop([:edited_galls])
    |> Map.merge(%{
      title: title(group),
      facts: facts,
      galls:
        (Enum.map(facts, & &1.gall) ++ group.edited_galls)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.id),
      counts: Enum.frequencies_by(facts, & &1.change),
      names: names,
      taxa: group.taxa |> Enum.reject(&MapSet.member?(new_ids, &1.id)) |> Enum.uniq_by(& &1.id)
    })
  end

  defp title(%{operation: op} = group) when is_map_key(@counted, op) do
    {verb, one, many} = @counted[op]

    n =
      if op == "import.decide_queue_item", do: max(group.decided, group.count), else: group.count

    "#{verb} #{if n == 1, do: one, else: "#{n} #{many}"}"
  end

  defp title(%{operation: op, count: n}) do
    words = Map.get(@worded, op, "Made a change")
    if n == 1, do: words, else: "#{words} (#{n} times)"
  end

  defp transactions(limit, since) do
    sql = """
    WITH t AS (
      SELECT id, meta, inserted_at FROM carbonite_default.transactions
      WHERE meta->'actor'->>'type' = 'user'
        AND NOT (meta->>'operation' = ANY($2))
        AND ($3::timestamp IS NULL OR inserted_at > $3)
        AND EXISTS (SELECT 1 FROM carbonite_default.changes c WHERE c.transaction_id = transactions.id)
      ORDER BY id DESC LIMIT $1
    ),
    pkg AS (
      SELECT t.id AS tid, max(coalesce(
        CASE WHEN c.table_name = 'import_packages' THEN (c.data->>'id')::bigint END,
        (c.data->>'package_id')::bigint)) AS package_id
      FROM t JOIN carbonite_default.changes c ON c.transaction_id = t.id
      WHERE c.table_name IN ('import_packages', 'import_batches', 'queue_items')
      GROUP BY t.id
    ),
    eff AS (
      SELECT t.id AS tid,
        coalesce(array_agg((c.data->>'taxon_id')::bigint)
          FILTER (WHERE c.table_name = 'taxon_names' AND c.op = 'insert'), '{}') AS name_taxa,
        coalesce(array_agg(c.data->>'name')
          FILTER (WHERE c.table_name = 'taxon_names' AND c.op = 'insert'), '{}') AS names,
        count(*) FILTER (WHERE c.table_name = 'queue_items' AND c.op = 'update') AS decided,
        coalesce(array_agg(DISTINCT (c.data->>'id')::bigint) FILTER (WHERE c.table_name = 'galls'), '{}') AS gall_ids,
        coalesce(array_agg(DISTINCT coalesce((c.data->>'taxon_id')::bigint, (c.data->>'id')::bigint))
          FILTER (WHERE c.table_name = 'taxa' OR (c.table_name = 'taxon_names' AND c.op <> 'insert')
                     OR c.table_name = 'host_range'), '{}') AS taxon_ids
      FROM t JOIN carbonite_default.changes c ON c.transaction_id = t.id
      GROUP BY t.id
    )
    SELECT t.id, t.meta->'actor'->>'name', t.meta->>'operation', t.inserted_at,
           s.id, s.title, eff.name_taxa, eff.names, coalesce(eff.decided, 0),
           eff.gall_ids, eff.taxon_ids
    FROM t
    LEFT JOIN pkg ON pkg.tid = t.id
    LEFT JOIN import_packages p ON p.id = pkg.package_id
    LEFT JOIN source s ON s.id = p.source_id
    LEFT JOIN eff ON eff.tid = t.id
    ORDER BY t.id DESC
    """

    %{rows: rows} = Repo.query!(sql, [limit, @left_out, since])
    taxa = rows |> Enum.flat_map(&((Enum.at(&1, 6) || []) ++ (Enum.at(&1, 10) || []))) |> taxa()
    galls = rows |> Enum.flat_map(&(Enum.at(&1, 9) || [])) |> galls()

    Enum.map(rows, &row(&1, taxa, galls))
  end

  defp row(
         [
           id,
           who,
           operation,
           at,
           source_id,
           title,
           name_taxa,
           names,
           decided,
           gall_ids,
           taxon_ids
         ],
         taxa,
         galls
       ) do
    %{
      id: id,
      who: who,
      operation: operation,
      at: at,
      source: source_id && %{id: source_id, title: title},
      names: Enum.zip_with(name_taxa || [], names || [], &new_name(&1, &2, taxa)),
      decided: decided,
      edited_galls: pick(gall_ids, galls),
      taxa: pick(taxon_ids, taxa)
    }
  end

  defp new_name(taxon_id, name, taxa) do
    %{rank: nil, kingdom: nil}
    |> Map.merge(Map.get(taxa, taxon_id, %{}))
    |> Map.merge(%{id: taxon_id, name: name})
  end

  defp pick(ids, found), do: for(id <- ids || [], Map.has_key?(found, id), do: found[id])

  defp galls([]), do: %{}

  defp galls(ids) do
    %{rows: rows} = Repo.query!("SELECT id, name FROM galls WHERE id = ANY($1)", [Enum.uniq(ids)])
    Map.new(rows, fn [id, name] -> {id, %{id: id, name: name}} end)
  end

  defp taxa([]), do: %{}

  defp taxa(ids) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT t.id, n.name, t.rank::text, t.kingdom::text FROM taxa t
        LEFT JOIN taxon_names n ON n.taxon_id = t.id AND n.status = 'accepted'
        WHERE t.id = ANY($1)
        """,
        [Enum.uniq(ids)]
      )

    Map.new(rows, fn [id, name, rank, kingdom] ->
      {id, %{id: id, name: name, rank: rank, kingdom: kingdom}}
    end)
  end

  defp fact_changes([]), do: []

  defp fact_changes(tx_ids) do
    sql = """
    SELECT c.transaction_id, (c.data->>'id')::bigint, c.op::text, c.data->>'standing'
    FROM carbonite_default.changes c
    WHERE c.transaction_id = ANY($1) AND c.table_name = 'facts' AND c.op IN ('insert', 'update')
    ORDER BY c.id
    """

    %{rows: rows} = Repo.query!(sql, [tx_ids])

    for [tx, fact_id, op, standing] <- rows do
      %{tx: tx, fact_id: fact_id, change: change(op, standing)}
    end
  end

  defp change("insert", _standing), do: :added
  defp change("update", "current"), do: :made_current
  defp change("update", "superseded"), do: :superseded
  defp change("update", "withdrawn"), do: :withdrawn
  defp change("update", _standing), do: :unsupported

  # Each Fact in words, with the Gall it is about, or the taxon (a common name).
  defp describe([]), do: %{}

  defp describe(fact_ids) do
    sql = """
    SELECT f.id,
      coalesce(tf.gall_id, rf.object_gall_id, rf.subject_gall_id, raf.gall_id, oc.gall_id, df.gall_id, af.gall_id),
      coalesce(tg.name, rg.name, rag.name, og.name, dg.name, ag.name),
      cf.taxon_id, cn.name, ct.rank::text, ct.kingdom::text,
      CASE f.kind
        WHEN 'gall_trait' THEN replace(tv.trait, '_', ' ') || ': ' || tv.value
        WHEN 'gall_relationship' THEN
          CASE rf.type::text
            WHEN 'host_of' THEN 'host: ' || coalesce(subj.name, '?')
            WHEN 'inducer_of' THEN 'inducer: ' || coalesce(subj.name, '?')
            ELSE replace(rf.type::text, '_', ' ') || ' ' || coalesce(obj.name, objg.name, '?')
          END
        WHEN 'gall_range' THEN 'range ' || raf.adjustment || ': ' || p1.name
        WHEN 'gall_occurrence' THEN 'recorded in ' || p2.name
        WHEN 'gall_description' THEN 'a description'
        WHEN 'gall_alias' THEN 'also known as ' || af.name
        WHEN 'taxon_common_name' THEN 'common name "' || cf.common_name || '"'
        ELSE f.kind::text
      END
    FROM facts f
    LEFT JOIN trait_facts tf ON tf.fact_id = f.id
    LEFT JOIN trait_values tv ON tv.id = tf.trait_value_id
    LEFT JOIN galls tg ON tg.id = tf.gall_id
    LEFT JOIN relationship_facts rf ON rf.fact_id = f.id
    LEFT JOIN galls rg ON rg.id = coalesce(rf.object_gall_id, rf.subject_gall_id)
    LEFT JOIN taxon_names subj ON subj.taxon_id = rf.subject_taxon_id AND subj.status = 'accepted'
    LEFT JOIN taxon_names obj ON obj.taxon_id = rf.object_taxon_id AND obj.status = 'accepted'
    LEFT JOIN galls objg ON objg.id = rf.object_gall_id
    LEFT JOIN range_facts raf ON raf.fact_id = f.id
    LEFT JOIN galls rag ON rag.id = raf.gall_id
    LEFT JOIN place p1 ON p1.id = raf.place_id
    LEFT JOIN occurrence_facts oc ON oc.fact_id = f.id
    LEFT JOIN galls og ON og.id = oc.gall_id
    LEFT JOIN place p2 ON p2.id = oc.place_id
    LEFT JOIN description_facts df ON df.fact_id = f.id
    LEFT JOIN galls dg ON dg.id = df.gall_id
    LEFT JOIN alias_facts af ON af.fact_id = f.id
    LEFT JOIN galls ag ON ag.id = af.gall_id
    LEFT JOIN common_name_facts cf ON cf.fact_id = f.id
    LEFT JOIN taxon_names cn ON cn.taxon_id = cf.taxon_id AND cn.status = 'accepted'
    LEFT JOIN taxa ct ON ct.id = cf.taxon_id
    WHERE f.id = ANY($1)
    """

    %{rows: rows} = Repo.query!(sql, [fact_ids])

    Map.new(rows, fn [id, gall_id, gall, taxon_id, taxon, rank, kingdom, what] ->
      {id,
       %{
         id: id,
         what: what,
         gall: gall_id && %{id: gall_id, name: gall},
         taxon: taxon_id && %{id: taxon_id, name: taxon, rank: rank, kingdom: kingdom}
       }}
    end)
  end
end
