defmodule Gallformers.Import.Preview do
  @moduledoc """
  The Facts preview (matter `f14c`, item 4): what approving a package would
  write, given the answers so far, grouped by Gall
  (`Gallformers.Import.FactsView`).

  `Gallformers.Import.preview_package/2` runs the apply the approval runs
  (taxonomy batch first, the package resolved again before the gall
  batch) inside one transaction that is always rolled back, whatever the
  batches' status: a gall batch held by a Host name is applied as far as
  it resolves. This module collects, inside that transaction, what each
  batch wrote and what it did not (`collect/2`), and after the rollback
  marks each Fact against what Gallformers holds (`finish/2`).

  ## Each statement

    * **written** — `:new` (Gallformers holds no such Fact), `:held`
      (Gallformers holds the same Fact, from any Source: a confirmation it
      holds current, or a denial of one it holds withdrawn) or `:conflict`
      (it holds the contrary: a confirmation of a Fact it holds withdrawn,
      a denial of one it holds current, a value other than the one current
      in a single-valued slot, another Inducer for the Gall; a taxonomic
      act the tree disagrees with), with `why`.
    * **waiting** — a question holds it (`question`): an open item about
      the statement itself (a dispute), or about a taxon or Gall it names
      (a Host name, an ambiguous name or Gall, a dispute), or its Trait
      term's question. A waiting Fact the apply could write still shows
      its value.
    * **dropped** — not written, with `why`: a decision (a dispute
      dropped, a Gall decision leaving it out), a curator's edit (its
      `edits`), a taxon or Gall left out, a term kept as text, or a
      reason the Fact cannot be written (an unknown place).

  IDs of what only the preview creates (taxa, Galls, Facts, the stored
  document's items) are nil after the rollback; such a taxon or Gall is
  marked `new: true` with the name it would get.
  """

  import Ecto.Query, only: [from: 2]

  alias Gallformers.Catalog.Facts.RelationshipFact
  alias Gallformers.Catalog.RelationshipTypes
  alias Gallformers.Facts.Fact
  alias Gallformers.Import.ApplyGall
  alias Gallformers.Import.Disputes
  alias Gallformers.Import.FactsView
  alias Gallformers.Import.Queue
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.StatementEdit
  alias Gallformers.Places
  alias Gallformers.Repo
  alias Gallformers.Taxa.Taxon

  # -- inside the transaction ----------------------------------------------------

  @doc """
  The trait plan the gall batch in `ctx` writes by
  (`Gallformers.Import.ApplyGall.trait_plan/1`), taken before it runs; nil
  for a taxonomy batch.
  """
  @spec plan(map()) :: map() | nil
  def plan(%{batch: %{batch_type: :gall}} = ctx), do: ApplyGall.trait_plan(ctx)
  def plan(_ctx), do: nil

  @doc """
  What applying the batch of `ctx` wrote (`result`, the runner's), read
  inside the preview's transaction. `opts`: `:plan` (`plan/1`, before the
  run), `:items` (the package's open queue items now), `:batches` (the
  package's batches), `:edits` (the batch's `StatementEdit`s).
  """
  @spec collect(map(), map(), keyword()) :: map()
  def collect(ctx, result, opts) do
    batch = ctx.batch
    content = batch.content || %{}
    rows = result.statements
    updates = Map.new(result.updates, &{&1.id, &1})

    taxon_ids = ids_by_ref(ctx.taxa, updates, :taxon_id)
    gall_ids = ids_by_ref(Map.get(ctx, :galls, %{}), updates, :gall_id)

    created = %{
      taxa: for(%{method: "created", taxon_id: id} <- result.updates, into: MapSet.new(), do: id),
      galls: for(%{method: "created", gall_id: id} <- result.updates, into: MapSet.new(), do: id),
      facts:
        for(%{resolution: :new, fact_id: id} <- rows, is_integer(id), into: MapSet.new(), do: id)
    }

    holding = holding(Keyword.get(opts, :items, []), Keyword.get(opts, :batches, []))
    edits = Keyword.get(opts, :edits, []) |> Enum.group_by(& &1.statement_ref)

    base = %{
      batch: batch,
      content: content,
      facts: Map.new(List.wrap(content["facts"]) ++ List.wrap(content["acts"]), &{&1["id"], &1}),
      declared: Map.new(List.wrap(content["taxa"]), &{&1["ref"], &1}),
      galls_content: Map.new(List.wrap(content["galls"]), &{&1["ref"], &1}),
      taxon_ids: taxon_ids,
      gall_ids: gall_ids,
      created: created,
      holding: holding,
      edits: edits,
      drop: ctx.drop,
      hosts: Map.get(ctx, :hosts, %{}),
      taxa_statements: ctx.taxa,
      gall_statements: Map.get(ctx, :galls, %{}),
      plan: Keyword.get(opts, :plan),
      items: Keyword.get(opts, :items, [])
    }

    case batch.batch_type do
      :gall -> collect_gall(base, ctx, result)
      :taxonomy -> collect_taxonomy(base, ctx, result)
    end
  end

  # Taxon or Gall IDs by ref: created by the run, or resolved.
  defp ids_by_ref(statements, updates, field) do
    for {ref, s} <- statements,
        "skipped" not in s.flags,
        id = statement_id(s, updates, field),
        is_integer(id),
        into: %{},
        do: {ref, id}
  end

  defp statement_id(s, updates, field) do
    case get_in(updates, [s.id, field]) do
      id when is_integer(id) -> id
      _ when s.resolution in [:resolved, :new] -> Map.get(s, field)
      _ -> held_valid(s, field)
    end
  end

  # A name the tree holds as a synonym while the Source treats it as valid
  # (`Gallformers.Import.ApplyTaxonomy`).
  defp held_valid(%{resolution: :unresolved, flags: flags, candidate_ids: [id | _]}, :taxon_id) do
    if "synonym_held_valid" in flags, do: id
  end

  defp held_valid(_s, _field), do: nil

  # The open items that hold a statement, by {batch ID, ref}: blocking
  # items about it or a name it names (wherever a shared name is queued),
  # disputes (a Trait one too).
  defp holding(items, batches) do
    types = Map.new(batches, &{&1.id, &1.batch_type})
    by_file = Map.new(batches, &{&1.file, &1.id})

    for item <- items,
        item.status == :open,
        Queue.blocking?(item, types[item.batch_id]) or Disputes.trait?(item),
        ref <- item_refs(item),
        key <- [{item.batch_id, ref} | also(item, by_file)],
        reduce: %{} do
      acc -> Map.put_new(acc, key, item)
    end
  end

  defp item_refs(%QueueItem{kind: :dispute} = item), do: Disputes.refs(item)
  defp item_refs(%QueueItem{statement_ref: ref}), do: [ref]

  defp also(%QueueItem{kind: kind, subject: subject}, by_file) when kind != :dispute do
    for %{"batch" => file, "ref" => ref} <- List.wrap((subject || %{})["also"]),
        id = by_file[file],
        do: {id, ref}
  end

  defp also(_item, _by_file), do: []

  # -- the gall batch ------------------------------------------------------------

  defp collect_gall(base, ctx, result) do
    rows = result.statements
    written = for %{fact_id: id} <- rows, is_integer(id), uniq: true, do: id
    entries = Map.new(FactsView.entries(ctx.source.id, written), &{&1.fact_id, &1})
    ref_of_fact = Map.new(rows, &{&1.fact_id, &1.ref})

    gall_names = FactsView.gall_names(Map.values(base.gall_ids))
    headers = headers(base, gall_names)
    key_by_ref = Map.new(headers, &{&1.ref, &1.key})
    key_of_id = gall_key_of_id(base, headers)

    taxon_names = FactsView.taxon_names(Map.values(base.taxon_ids) ++ Map.values(base.hosts))
    names = %{taxa: taxon_names, galls: gall_names}
    trait_waiting = trait_waiting(base)

    from_rows =
      for row <- rows do
        if is_integer(row.fact_id) do
          written_entry(base, entries[row.fact_id], row, key_of_id, ref_of_fact)
        else
          unwritten_entry(base, row.ref, row.detail["skipped"], key_by_ref, names, trait_waiting)
        end
      end

    # Facts no row speaks of: Trait Facts left out before the plan (dropped,
    # or waiting on their dispute).
    seen = MapSet.new(rows, &base_ref(&1.ref))

    from_content =
      for %{"id" => ref} = f <- List.wrap(base.content["facts"]),
          not MapSet.member?(seen, ref),
          do: unwritten_entry(base, ref, base.drop[ref] || "not stated", key_by_ref, names, f)

    %{
      batch: base.batch,
      kind: :gall,
      headers: headers,
      entries: Enum.reject(from_rows ++ from_content, &is_nil/1),
      created: base.created,
      new_taxa: new_taxa(base, result),
      queue: result.queue
    }
  end

  # One header per Gall of the batch, in batch order (one per Gall it
  # resolves to).
  defp headers(base, gall_names) do
    base.content["galls"]
    |> List.wrap()
    |> Enum.map(&header(base, gall_names, &1))
    |> Enum.uniq_by(& &1.key)
  end

  defp header(base, gall_names, %{"ref" => ref} = g) do
    id = base.gall_ids[ref]
    created? = is_integer(id) and MapSet.member?(base.created.galls, id)
    question = holding_item(base, [ref | waits_on(base, ref)])
    {key, status} = gall_status(ref, id, created?, question)

    %{
      key: key,
      ref: ref,
      gall_id: if(created?, do: nil, else: id),
      new: created?,
      name_as_written: g["name_as_written"],
      name: id && get_in(gall_names, [id, :name]),
      status: if(question, do: :waiting, else: status),
      question: question && question(question),
      why: if(status == :dropped, do: gall_why(base, ref))
    }
  end

  defp gall_status(ref, _id, true, _question), do: {"new:" <> ref, :new}
  defp gall_status(_ref, id, _created?, _question) when is_integer(id), do: {id, :resolved}
  defp gall_status(ref, _id, _created?, nil), do: {"ref:" <> ref, :dropped}
  defp gall_status(ref, _id, _created?, _question), do: {"ref:" <> ref, :waiting}

  # What a Gall not resolved waits on: the taxa it is identified by, the
  # Gall it is paired with.
  defp waits_on(base, ref) do
    case base.galls_content[ref] do
      %{} = g -> if base.gall_ids[ref], do: [], else: identified_by(g) ++ paired(base, ref)
      nil -> []
    end
  end

  # The Gall a Gall is paired with (`Gallformers.Import.GallMatcher`): one
  # of the two is the Gall both match, decided on the other's question.
  defp paired(base, ref) do
    case get_in(base.gall_statements, [ref, Access.key(:detail), "pair", "ref"]) do
      pair when is_binary(pair) -> [pair]
      _ -> []
    end
  end

  defp identified_by(g) do
    for role <- ["inducer", "host"],
        ref = get_in(g, ["identified_by", role]),
        is_binary(ref),
        do: ref
  end

  defp gall_why(base, ref) do
    case Enum.find(base.items, &(&1.statement_ref == ref and &1.batch_id == base.batch.id)) do
      nil -> "left out"
      item -> "left out (#{item.kind})"
    end
  end

  defp gall_key_of_id(base, headers) do
    by_ref = Map.new(headers, &{&1.ref, &1.key})
    for {ref, id} <- base.gall_ids, key = by_ref[ref], into: %{}, do: {id, key}
  end

  # The Trait Facts waiting on their term's question, ref to the question's ref.
  defp trait_waiting(%{plan: nil}), do: %{}

  defp trait_waiting(%{plan: plan}) do
    for %{use: use, text: false} <- plan.waiting,
        f <- use.facts,
        into: %{},
        do: {f.ref, use.item_ref}
  end

  defp written_entry(_base, nil, _row, _key_of_id, _ref_of_fact), do: nil

  defp written_entry(base, entry, row, key_of_id, ref_of_fact) do
    ref = row.ref
    fact = base.facts[base_ref(ref)]
    question = holding_item(base, [base_ref(ref) | named_refs(base, fact)])

    value =
      case entry.value do
        %{of_fact_id: of} = v -> %{v | of_ref: ref_of_fact[of]}
        v -> v
      end

    %{
      entry
      | ref: ref,
        batch_id: base.batch.id,
        gall: Map.get(key_of_id, entry.gall, entry.gall),
        value: value,
        status: if(question, do: :waiting),
        question: question && question(question),
        edits: edits_of(base, ref)
    }
    |> Map.merge(%{created: MapSet.member?(base.created.facts, entry.fact_id)})
  end

  # A statement not written: waiting on a question, or dropped and why.
  defp unwritten_entry(base, ref, reason, key_by_ref, names, trait_waiting)
       when is_map(trait_waiting) do
    fact = base.facts[base_ref(ref)]
    term_item = trait_waiting[ref] && term_item(base, trait_waiting[ref])
    unwritten(base, ref, fact, reason, key_by_ref, names, term_item)
  end

  defp unwritten_entry(base, ref, reason, key_by_ref, names, %{} = fact),
    do: unwritten(base, ref, fact, reason, key_by_ref, names, nil)

  defp unwritten(_base, _ref, nil, _reason, _key_by_ref, _names, _term_item), do: nil

  defp unwritten(base, ref, fact, reason, key_by_ref, names, term_item) do
    edits = edits_of(base, ref)
    dropped_by_edit = Enum.find(edits, &(&1.kind == :drop))
    question = term_item || holding_item(base, [base_ref(ref) | named_refs(base, fact)])

    {status, why} =
      cond do
        dropped_by_edit -> {:dropped, base.drop[base_ref(ref)]}
        question -> {:waiting, nil}
        true -> {:dropped, why(base, reason)}
      end

    kind = FactsView.kind(fact["kind"])

    %{
      ref: ref,
      batch_id: base.batch.id,
      fact_id: nil,
      kind: kind,
      category: content_category(base, fact),
      gall: Map.get(key_by_ref, fact_gall(base, fact)),
      value: content_value(base, fact, names),
      words: content_words(base, fact),
      stance: stance(fact["stance"]),
      status: status,
      standing: nil,
      slot: nil,
      question: question && question(question),
      why: why,
      edits: edits,
      created: false
    }
  end

  # Why a statement was not written: a curator's drop, or the taxon or
  # Gall it names left out or not resolved, and why.
  defp why(_base, "dropped by a curator: " <> why), do: why

  defp why(base, reason) when is_binary(reason) do
    with [_, what, ref] <- Regex.run(~r/\A(taxon|Gall) (\S+) is not resolved\z/, reason),
         %{} = s <-
           Map.get(if(what == "taxon", do: base.taxa_statements, else: base.gall_statements), ref) do
      cond do
        "skipped" in s.flags -> "#{what} #{ref} is left out"
        is_binary((s.detail || %{})["reason"]) -> "#{reason}: #{s.detail["reason"]}"
        true -> reason
      end
    else
      _ -> reason
    end
  end

  defp why(_base, reason), do: reason

  defp term_item(base, item_ref) do
    Enum.find(
      base.items,
      &(&1.kind == :trait_term and &1.batch_id == base.batch.id and &1.statement_ref == item_ref)
    )
  end

  # The first open item holding one of `refs` in this batch.
  defp holding_item(base, refs) do
    Enum.find_value(refs, &Map.get(base.holding, {base.batch.id, &1}))
  end

  defp question(%QueueItem{} = item) do
    %{
      id: item.id,
      kind: item.kind,
      statement_ref: item.statement_ref,
      batch_id: item.batch_id,
      blocking: not Disputes.trait?(item) and item.kind != :trait_term
    }
  end

  # The taxon and Gall refs a Fact names, then what its Galls not resolved wait on.
  defp named_refs(_base, nil), do: []

  defp named_refs(base, fact) do
    direct =
      for role <- ["subject", "object", "gall", "gall_context", "taxon", "parent", "accepted"],
          ref <-
            List.wrap(fact[role]) ++ if(role == "accepted", do: List.wrap(fact["into"]), else: []),
          is_binary(ref),
          do: ref

    of = if is_binary(fact["of"]), do: named_refs(base, base.facts[fact["of"]]), else: []

    galls = for ref <- direct, r <- waits_on(base, ref), do: r

    Enum.uniq(direct ++ of ++ galls)
  end

  defp base_ref(ref), do: ref |> String.split("+") |> hd()

  defp edits_of(base, ref) do
    for %StatementEdit{} = e <- Map.get(base.edits, base_ref(ref), []) do
      %{id: e.id, kind: e.kind, value: e.value, note: e.note, author_name: e.author_name}
    end
  end

  # -- a statement in the Source's terms -------------------------------------------

  defp content_category(base, %{"kind" => "qualifier", "of" => of}) do
    case base.facts[of] do
      %{} = f -> content_category(base, f)
      nil -> :other
    end
  end

  defp content_category(_base, %{"kind" => kind} = f), do: FactsView.category(kind, f["type"])

  # The Gall ref a Fact goes under.
  defp fact_gall(_base, %{"kind" => "relationship"} = f) do
    case RelationshipTypes.get(f["type"]) do
      %{endpoints: :gall_to_gall} -> f["subject"]
      %{endpoints: :taxon_to_taxon_in_gall} -> f["gall_context"]
      _ -> f["object"]
    end
  end

  defp fact_gall(base, %{"kind" => "qualifier", "of" => of}),
    do: base.facts[of] && fact_gall(base, base.facts[of])

  defp fact_gall(_base, f), do: f["gall"]

  defp content_value(base, %{"kind" => "relationship"} = f, names) do
    type = RelationshipTypes.get(f["type"])
    endpoints = type && type.endpoints

    {subject, object} =
      case endpoints do
        :gall_to_gall ->
          {gall_end(base, f["subject"], names), gall_end(base, f["object"], names)}

        :taxon_to_taxon_in_gall ->
          {taxon_end(base, f, "subject", names), taxon_end(base, f, "object", names)}

        _ ->
          {taxon_end(base, f, "subject", names), gall_end(base, f["object"], names)}
      end

    %{
      type: f["type"],
      label: type && type.label,
      subject: subject,
      object: object,
      gall_context: f["gall_context"] && gall_end(base, f["gall_context"], names)
    }
  end

  defp content_value(_base, %{"kind" => "trait"} = f, _names) do
    %{trait: f["trait"], value: nil, suggested: suggested(f)}
  end

  defp content_value(_base, %{"kind" => "range"} = f, _names),
    do: %{adjustment: adjustment(f["adjustment"]), place: place(get_in(f, ["place", "value"]))}

  defp content_value(_base, %{"kind" => "occurrence"} = f, _names),
    do: %{place: place(get_in(f, ["place", "value"]))}

  defp content_value(_base, %{"kind" => "alias"} = f, _names), do: %{name: f["name"], kind: nil}
  defp content_value(_base, %{"kind" => "description"}, _names), do: %{}

  defp content_value(_base, %{"kind" => "qualifier"} = f, _names),
    do: %{
      qualifier: f["qualifier"],
      value: get_in(f, ["value", "value"]),
      of_fact_id: nil,
      of_ref: f["of"]
    }

  defp content_value(_base, _f, _names), do: %{}

  defp suggested(%{"category" => %{"value" => v}}), do: v
  defp suggested(%{"term" => _}), do: nil
  defp suggested(f), do: get_in(f, ["value", "value"])

  defp adjustment("exclude"), do: :exclude
  defp adjustment("only"), do: :only
  defp adjustment(_other), do: nil

  defp place(code) when is_binary(code) do
    case Places.get_place_by_code(code) do
      %{id: id, name: name} -> %{id: id, code: code, name: name}
      nil -> %{id: nil, code: code, name: nil}
    end
  end

  defp place(_code), do: nil

  # The plant a curator chose for a Host statement wins (`ctx.hosts`).
  defp taxon_end(base, f, role, names) do
    id =
      if role == "subject" and f["type"] == "host_of",
        do: Map.get(base.hosts, f["id"]) || base.taxon_ids[f[role]],
        else: base.taxon_ids[f[role]]

    (id && names.taxa[id]) || %{taxon_id: id, name: nil, rank: nil}
  end

  defp gall_end(_base, nil, _names), do: nil

  defp gall_end(base, ref, names) do
    id = base.gall_ids[ref]
    (id && names.galls[id]) || %{gall_id: id, name: nil}
  end

  defp content_words(base, f) do
    names =
      for role <- ["subject", "object", "taxon", "parent", "name", "accepted"],
          ref = f[role],
          is_binary(ref),
          d = base.declared[ref],
          is_map(d),
          do: %{
            role: role,
            name_as_written: d["name_as_written"],
            name_reading: d["name_reading"]
          }

    %{
      FactsView.empty_words()
      | term: f["term"] || (f["kind"] == "trait" && get_in(f, ["value", "as_written"])) || nil,
        value_as_written:
          get_in(f, ["value", "as_written"]) || get_in(f, ["place", "as_written"]),
        names: names,
        evidence:
          for %{} = e <- List.wrap(f["evidence"]), not Map.has_key?(e, "statement") do
            %{
              quote: e["quote"],
              item: e["item"],
              whole_item: e["whole_item"] == true,
              page: e["page"]
            }
          end,
        when_as_written: f["when_as_written"],
        stage_as_written: f["stage_as_written"],
        statement_text:
          Enum.find_value(
            List.wrap(f["evidence"]),
            &(is_map(&1) && get_in(&1, ["statement", "text"]))
          )
    }
  end

  defp stance("deny"), do: :deny
  defp stance(_confirm), do: :confirm

  # -- the taxonomy batch --------------------------------------------------------

  defp collect_taxonomy(base, _ctx, result) do
    names = FactsView.taxon_names(Map.values(base.taxon_ids))

    disagreements =
      for %{kind: kind} = q <- result.queue,
          kind in [:taxonomy_disagreement, :taxonomy_acceptance],
          into: %{},
          do: {q.statement_ref, q.reason}

    facts =
      Repo.all(
        from(f in Fact,
          where: f.id in ^for(%{fact_id: id} <- result.statements, is_integer(id), do: id)
        )
      )

    slots = Map.new(facts, &{&1.id, &1.slot})

    acts =
      for row <- result.statements,
          act = base.facts[row.ref],
          is_map(act),
          do:
            act_entry(base, row, act, %{names: names, disagreements: disagreements, slots: slots})

    %{
      batch: base.batch,
      kind: :taxonomy,
      headers: [],
      entries: acts,
      created: base.created,
      new_taxa: new_taxa(base, result),
      queue: result.queue
    }
  end

  defp act_entry(base, row, act, found) do
    question = holding_item(base, [row.ref | named_refs(base, act)])
    {status, why} = act_status(base, row, question, found.disagreements[row.ref])

    %{
      ref: row.ref,
      batch_id: base.batch.id,
      fact_id: row.fact_id,
      kind: FactsView.kind(act["kind"]),
      category: :taxonomy,
      gall: nil,
      value: act_value(base, act, found.names),
      words:
        Map.merge(content_words(base, act), %{
          status_as_written: act["status_as_written"],
          authorship_as_written: get_in(act, ["authorship", "as_written"])
        }),
      stance: stance(act["stance"]),
      status: status,
      standing: nil,
      slot: found.slots[row.fact_id],
      question: question && question(question),
      why: why,
      edits: edits_of(base, row.ref),
      created: MapSet.member?(base.created.facts, row.fact_id)
    }
  end

  # A waiting act, one not written (history, or dropped), one the tree
  # disagrees with; the others are marked after the rollback.
  defp act_status(_base, _row, question, _disagreement) when question != nil, do: {:waiting, nil}

  defp act_status(base, %{fact_id: nil} = row, _question, _disagreement) do
    if "original_combination" in row.flags,
      do: {:dropped, row.detail["recorded"]},
      else: {:dropped, why(base, row.detail["skipped"])}
  end

  defp act_status(_base, _row, _question, nil), do: {nil, nil}
  defp act_status(_base, _row, _question, disagreement), do: {:conflict, disagreement}

  defp act_value(base, act, names) do
    taxon = fn ref ->
      ref &&
        ((base.taxon_ids[ref] && names[base.taxon_ids[ref]]) ||
           %{taxon_id: nil, name: declared_name(base, ref), rank: nil})
    end

    %{
      taxon: taxon.(act["taxon"]),
      parent: taxon.(act["parent"]),
      accepted: taxon.(act["accepted"]),
      name: act["name"] && declared_name(base, act["name"]),
      into: for(ref <- List.wrap(act["into"]), do: taxon.(ref)),
      common_name: act["common_name"]
    }
    |> Map.reject(fn {_k, v} -> v in [nil, []] end)
  end

  defp declared_name(base, ref) do
    d = base.declared[ref] || %{}
    d["name_reading"] || d["name_as_written"]
  end

  # The taxa the batch creates: ref, name, rank, parent, unplaced.
  defp new_taxa(base, result) do
    ref_of = Map.new(base.taxa_statements, fn {ref, s} -> {s.id, ref} end)
    created = for %{method: "created", taxon_id: id} = u <- result.updates, is_integer(id), do: u
    taxa = Repo.all(from(t in Taxon, where: t.id in ^Enum.map(created, & &1.taxon_id)))
    parents = Map.new(taxa, &{&1.id, &1.parent_id})

    names =
      FactsView.taxon_names(
        Enum.map(taxa, & &1.id) ++ Enum.reject(Map.values(parents), &is_nil/1)
      )

    for u <- created do
      ref = ref_of[u.id]
      parent_id = parents[u.taxon_id]

      %{
        ref: ref,
        batch_id: base.batch.id,
        name: get_in(names, [u.taxon_id, :name]),
        rank: get_in(names, [u.taxon_id, :rank]),
        name_as_written: get_in(base.declared, [ref, "name_as_written"]),
        parent:
          parent_id &&
            Map.put(names[parent_id], :new, MapSet.member?(base.created.taxa, parent_id)),
        unplaced: "unplaced" in (u.flags || [])
      }
    end
  end

  # -- after the rollback ----------------------------------------------------------

  @doc """
  The preview of the batches `collected` inside the rolled-back
  transaction (`collect/3`, in order), marked against what Gallformers
  holds now; `items` are the package's open queue items (what a question
  may name). Returns `%{galls, taxonomy: %{new_taxa, acts}, counts}`
  (`Gallformers.Import.preview_package/2`).
  """
  @spec finish([map()], [QueueItem.t()]) :: map()
  def finish(collected, items) do
    created =
      Enum.reduce(
        collected,
        %{taxa: MapSet.new(), galls: MapSet.new(), facts: MapSet.new()},
        fn c, acc ->
          Map.merge(acc, c.created, fn _k, a, b -> MapSet.union(a, b) end)
        end
      )

    open_ids = MapSet.new(items, & &1.id)
    entries = collected |> Enum.flat_map(& &1.entries) |> mark()
    sanitize = &sanitize(&1, created, open_ids)

    {acts, gall_entries} = Enum.split_with(entries, &(&1.category == :taxonomy))
    headers = collected |> Enum.flat_map(& &1.headers) |> Enum.map(&sanitize_header(&1, open_ids))

    %{
      galls: FactsView.group(headers, Enum.map(gall_entries, sanitize)),
      taxonomy: %{
        new_taxa:
          collected
          |> Enum.flat_map(& &1.new_taxa)
          |> Enum.map(&update_in(&1, [:parent], fn p -> p && endpoint(p, created) end)),
        acts: Enum.map(acts, sanitize)
      },
      counts:
        Map.merge(
          %{new: 0, held: 0, conflict: 0, waiting: 0, dropped: 0},
          Enum.frequencies_by(entries, & &1.status)
        )
    }
  end

  # Each written Fact not waiting: new, held or in conflict with what
  # Gallformers holds. A Fact Gallformers holds already has its standing
  # before the apply; one the preview created, none.
  defp mark(entries) do
    open = Enum.filter(entries, &(&1.status == nil))
    existing = for e <- entries, is_integer(e.fact_id), not e.created, uniq: true, do: e.fact_id

    standings =
      Repo.all(from(f in Fact, where: f.id in ^existing, select: {f.id, f.standing})) |> Map.new()

    slots = for e <- open, e.stance == :confirm, is_binary(e.slot), uniq: true, do: e.slot

    in_slot =
      from(f in Fact, where: f.slot in ^slots and f.standing == :current, select: {f.slot, f.id})
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    inducers = current_inducers(for e <- open, inducer?(e), uniq: true, do: e.gall)

    Enum.map(entries, fn
      %{status: nil} = e -> mark(e, standings[e.fact_id], in_slot, inducers)
      e -> %{e | standing: if(e.created, do: nil, else: standings[e.fact_id])}
    end)
  end

  defp inducer?(e),
    do:
      e.category == :inducer and e.kind == :relationship and e.stance == :confirm and
        is_integer(e.gall)

  # The current Inducers of `gall_ids`: gall ID to `[{taxon ID, name, Fact ID}]`.
  defp current_inducers([]), do: %{}

  defp current_inducers(gall_ids) do
    rows =
      from(r in RelationshipFact,
        join: f in Fact,
        on: f.id == r.fact_id,
        where:
          r.type == "inducer_of" and r.object_gall_id in ^gall_ids and f.standing == :current,
        select: {r.object_gall_id, r.subject_taxon_id, r.fact_id}
      )
      |> Repo.all()

    names = FactsView.taxon_names(for {_g, t, _f} <- rows, is_integer(t), uniq: true, do: t)

    Enum.group_by(rows, &elem(&1, 0), fn {_g, t, f} -> {t, get_in(names, [t, :name]), f} end)
  end

  defp mark(e, standing, in_slot, inducers) do
    existed? = not e.created
    others = for id <- Map.get(in_slot, e.slot, []), id != e.fact_id, do: id
    subject = get_in(e, [:value, :subject, :taxon_id])

    other_inducers =
      if inducer?(e),
        do:
          for(
            {t, name, f} <- Map.get(inducers, e.gall, []),
            f != e.fact_id,
            t != subject,
            do: name
          ),
        else: []

    {status, why} =
      if e.stance == :deny,
        do: deny_status(existed?, standing),
        else: confirm_status(e, existed?, standing, others, other_inducers)

    %{e | status: status, why: why, standing: standing}
  end

  defp deny_status(true, :current), do: {:conflict, "Gallformers holds it"}
  defp deny_status(true, :withdrawn), do: {:held, nil}
  defp deny_status(_existed?, _standing), do: {:new, nil}

  defp confirm_status(e, existed?, standing, others, other_inducers) do
    cond do
      existed? and standing == :withdrawn ->
        {:conflict, "Gallformers holds it denied"}

      e.category != :taxonomy and others != [] ->
        {:conflict, "Gallformers holds another value here"}

      other_inducers != [] ->
        {:conflict, "Gallformers holds another Inducer: #{Enum.join(other_inducers, ", ")}"}

      existed? and standing == :current ->
        {:held, nil}

      true ->
        {:new, nil}
    end
  end

  # IDs of what only the preview created are nil; such a taxon or Gall is `new`.
  defp sanitize(e, created, open_ids) do
    e
    |> Map.put(:fact_id, if(e.created, do: nil, else: e.fact_id))
    |> Map.update!(:value, &sanitize_value(&1, created))
    |> Map.update!(:question, &sanitize_question(&1, open_ids))
    |> Map.drop([:slot, :created])
  end

  defp sanitize_header(header, open_ids),
    do: Map.update!(header, :question, &sanitize_question(&1, open_ids))

  # A question only the preview's resolution asks has no ID yet.
  defp sanitize_question(nil, _open_ids), do: nil

  defp sanitize_question(%{id: id} = q, open_ids),
    do: if(MapSet.member?(open_ids, id), do: q, else: %{q | id: nil})

  defp sanitize_value(value, created) when is_map(value) do
    Map.new(value, fn
      {key, %{} = v} when key in [:subject, :object, :gall_context, :taxon, :parent, :accepted] ->
        {key, endpoint(v, created)}

      {:into, list} when is_list(list) ->
        {:into, Enum.map(list, &endpoint(&1, created))}

      {:of_fact_id, id} ->
        {:of_fact_id, if(MapSet.member?(created.facts, id), do: nil, else: id)}

      other ->
        other
    end)
  end

  defp sanitize_value(value, _created), do: value

  defp endpoint(%{taxon_id: id} = v, created) when is_integer(id) do
    if MapSet.member?(created.taxa, id),
      do: %{v | taxon_id: nil} |> Map.put(:new, true),
      else: Map.put_new(v, :new, false)
  end

  defp endpoint(%{gall_id: id} = v, created) when is_integer(id) do
    if MapSet.member?(created.galls, id),
      do: %{v | gall_id: nil} |> Map.put(:new, true),
      else: Map.put_new(v, :new, false)
  end

  defp endpoint(v, _created), do: Map.put_new(v, :new, false)
end
