defmodule Gallformers.Import.TaxonomyCarryOver do
  @moduledoc """
  Phase 1's taxonomy decisions carried over at cutover (matter `f923`
  Task 9, "Phase 1 decisions carry over"): a curator's "the Source is
  right: change the tree" counts as that Source's taxonomic statements
  accepted, so it doesn't come back as a question and the tree, already
  changed, follows the Facts. Run after the replay
  (`Gallformers.Release.replay_log/1`), so the phase 1 tree edits and the
  Sources' batches are in.

  ## What is accepted

    * **Synonym decisions** (`Gallformers.Import.SynonymDecisions`): a
      split (the name a species of its own again) or a move (the name a
      synonym of another taxon), found in the replay log (`:queue_decision`
      entries, less those undone since: `:queue_decision_undone`) and
      among the decided queue items. The matching statements
      are those the same package's applied taxonomy batches recorded about
      the name (acts whose taxon, name or accepted taxon is a taxon the
      batch declares by that name).
    * **Acts a curator followed**: a taxonomic act that differed from the
      tree when its batch was applied (a `:taxonomy_disagreement` question
      on an act, or the `:taxonomy_acceptance` question the same import
      raises when the cutover replays it under phase 2), which phase 1
      left to a curator to apply editorially. Accepting it closes its
      question.

  Of those, each statement the tree now holds (a placement under the
  taxon's parent; a name, rank and sensu the taxon has, its authorship
  unless the tree has none; a synonym or common name it holds; a denial of
  what it doesn't hold) is accepted, through
  `Gallformers.Import.TaxonomicDecisions` (audited, in the replay log). A
  statement the tree doesn't hold, a split (curator work, `f923` Task 7),
  one declined since and Gallformers' own are left as they are.

  ## Reported for a curator

  A synonym decision is carried when, after the acceptances, the tree rows
  it changed follow the Facts (`Gallformers.Taxa.Sync.check/0`): the taxon
  it resolved the name to (for a split, every row; for a move, the name as
  its synonym) and the name as a synonym of any other taxon. A split whose
  Source states only the name and placement is carried: its dated name
  statement, accepted, outranks the older (legacy) statement making the
  name the old taxon's synonym (`Gallformers.Facts`, "A revalidated name
  outranks an older synonymy of it"). Otherwise it is reported with those
  differences: say, a Source that never names the split taxon, so nothing
  outranks that synonymy. A decision whose package, Source or taxon can't
  be found is reported with the reason.

  ## Idempotent

  An accepted statement stays accepted, so running it again accepts
  nothing new (`already` counts them).
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Audit.Actor
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Import.Batch
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.Package
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.ReplayEntry
  alias Gallformers.Import.StableRef
  alias Gallformers.Import.SynonymDecisions
  alias Gallformers.Import.TaxonomicDecisions
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Taxa
  alias Gallformers.Taxa.ActFacts.SynonymyFact
  alias Gallformers.Taxa.NameNormalizer
  alias Gallformers.Taxa.Sync

  @typedoc "A synonym decision the Source's statements did not carry, for a curator."
  @type unmatched :: %{
          source: String.t() | nil,
          name: String.t() | nil,
          decision: String.t(),
          differences: [String.t()],
          reason: String.t() | nil
        }

  @typedoc """
  What a run did: the phase 1 synonym decisions found (`decisions`), the
  statements accepted now (`accepted`, of which `followed` for acts a
  curator followed) and before (`already`), the decisions `unmatched`, and
  acceptances the tree refused (`problems`).
  """
  @type report :: %{
          decisions: non_neg_integer(),
          accepted: non_neg_integer(),
          followed: non_neg_integer(),
          already: non_neg_integer(),
          unmatched: [unmatched()],
          problems: [String.t()]
        }

  @doc """
  Carries phase 1's decisions over as `actor`: those in replay-log
  `entries` (the exported log just replayed: `ReplayEntry`s or their
  exported maps) and the decided queue items. Returns the report.
  """
  @spec run(Actor.t(), [ReplayEntry.t() | map()]) :: {:ok, report()}
  def run(%Actor{} = actor, entries) when is_list(entries) do
    decisions = decisions(entries)
    acc = %{seen: MapSet.new(), accepted: 0, followed: 0, already: 0, problems: []}

    {carried, acc} = Enum.map_reduce(decisions, acc, &carry(actor, &1, &2))
    acc = follow_acts(actor, acc)
    differences = if carried == [], do: [], else: Sync.check()

    {:ok,
     %{
       decisions: length(decisions),
       accepted: acc.accepted,
       followed: acc.followed,
       already: acc.already,
       unmatched: Enum.flat_map(carried, &unmatched(&1, differences)),
       problems: Enum.reverse(acc.problems)
     }}
  end

  # -- finding phase 1's decisions -----------------------------------------------

  # The tree-changing synonym decisions, by package key, batch and ref: the
  # decided items (with their subjects), then the log's others.
  defp decisions(entries) do
    items =
      from(q in QueueItem,
        where:
          q.kind == :taxonomy_disagreement and q.status == :decided and
            like(q.statement_ref, "t%") and not is_nil(q.package_id)
      )
      |> Repo.all()
      |> Enum.filter(&SynonymDecisions.changes_tree?(&1.decision))
      |> Enum.map(fn item ->
        package = Repo.get!(Package, item.package_id)
        batch = item.batch_id && Repo.get(Batch, item.batch_id)

        %{
          key: {package.key, batch && batch.producer_batch_id, item.statement_ref},
          decision: {:ok, item.decision},
          name: item.subject["name_reading"] || item.subject["name_as_written"]
        }
      end)

    logged =
      for e <- standing(entries),
          %{"kind" => "taxonomy_disagreement", "statement_ref" => "t" <> _} = key <- [e.key],
          decision = e.payload["decision"],
          is_map(decision) and SynonymDecisions.changes_tree?(decision) do
        %{
          key: {key["package"], key["batch_id"], key["statement_ref"]},
          decision: StableRef.decode_decision(decision),
          name: nil
        }
      end

    Enum.uniq_by(items ++ logged, & &1.key)
  end

  # The log's `:queue_decision` entries still standing: an undo
  # (`:queue_decision_undone`, keyed alike) takes the one before it back.
  defp standing(entries) do
    entries
    |> Enum.map(&normalize/1)
    |> Enum.reduce({[], %{}}, fn
      %{kind: :queue_decision, key: key} = e, {order, by_key} ->
        {[key | order], Map.put(by_key, key, e)}

      %{kind: :queue_decision_undone, key: key}, {order, by_key} ->
        {order, Map.delete(by_key, key)}

      _e, acc ->
        acc
    end)
    |> then(fn {order, by_key} ->
      order |> Enum.reverse() |> Enum.uniq() |> Enum.flat_map(&List.wrap(by_key[&1]))
    end)
  end

  defp normalize(%ReplayEntry{kind: kind, key: key, payload: payload}),
    do: %{kind: kind, key: key || %{}, payload: payload || %{}}

  defp normalize(entry) do
    kind = entry[:kind] || entry["kind"]

    %{
      kind: if(is_binary(kind), do: String.to_existing_atom(kind), else: kind),
      key: entry[:key] || entry["key"] || %{},
      payload: entry[:payload] || entry["payload"] || %{}
    }
  end

  # -- carrying a decision over --------------------------------------------------

  defp carry(actor, %{key: {package_key, batch_id, ref}} = d, acc) do
    package = package_key && Repo.get_by(Package, key: package_key)
    batches = if package, do: batches(package), else: []
    name = d.name || declared_name(batches, batch_id, ref)

    base = %{
      source: package && package.source_id && Sources.get_source(package.source_id),
      name: name,
      decision: decision_text(d.decision),
      taxon_id: nil,
      split: false,
      reason: nil
    }

    case resolve(package, d.decision) do
      {:ok, source_id, %{"taxon_id" => taxon_id} = decision} ->
        acc =
          batches
          |> statements_about(name)
          |> Enum.reduce(acc, &consider(actor, &1, source_id, &2))

        {%{base | taxon_id: taxon_id, split: decision["split"] == true}, acc}

      {:error, reason} ->
        {%{base | reason: reason}, acc}
    end
  end

  defp resolve(nil, _decision), do: {:error, "its package isn't here"}
  defp resolve(%Package{source_id: nil}, _decision), do: {:error, "its package has no Source"}
  defp resolve(_package, {:error, reason}), do: {:error, "its decision: #{inspect(reason)}"}

  defp resolve(%Package{source_id: source_id}, {:ok, %{"taxon_id" => id} = decision}) do
    if is_integer(id) and Taxa.get_taxon(id) != nil,
      do: {:ok, source_id, decision},
      else: {:error, "the taxon it resolved the name to is gone"}
  end

  defp resolve(_package, {:ok, _decision}), do: {:error, "its decision names no taxon"}

  defp batches(package),
    do: Repo.all(from(b in Batch, where: b.package_id == ^package.id, order_by: b.id))

  defp declared_name(batches, batch_id, ref) do
    with %Batch{content: content} <- Enum.find(batches, &(&1.producer_batch_id == batch_id)),
         %{} = declared <- Enum.find(List.wrap(content["taxa"]), &(&1["ref"] == ref)) do
      declared["name_reading"] || declared["name_as_written"]
    else
      _ -> nil
    end
  end

  defp decision_text({:ok, %{"split" => true}}), do: "split: a species of its own again"

  defp decision_text({:ok, %{"synonym_of" => id}}) when is_integer(id),
    do: "a synonym of #{Taxa.accepted_name(id)}"

  defp decision_text(_decision), do: "change the tree"

  # The Fact IDs of the acts the package's applied taxonomy batches recorded
  # about taxa they declare by `name`.
  defp statements_about(_batches, nil), do: []

  defp statements_about(batches, name) do
    key = NameNormalizer.normalize(name)

    for %Batch{batch_type: :taxonomy, status: :applied} = batch <- batches,
        refs = named_refs(batch.content, key),
        refs != [],
        act_ids = about(batch.content, refs),
        %BatchStatement{fact_id: fact_id} <- act_statements(batch, act_ids),
        uniq: true,
        do: fact_id
  end

  defp named_refs(content, key) do
    for t <- List.wrap(content["taxa"]),
        name = t["name_reading"] || t["name_as_written"],
        is_binary(name) and NameNormalizer.normalize(name) == key,
        do: t["ref"]
  end

  defp about(content, refs) do
    for a <- List.wrap(content["acts"]),
        Enum.any?(["taxon", "name", "accepted"], &(a[&1] in refs)),
        do: a["id"]
  end

  defp act_statements(batch, act_ids) do
    Repo.all(
      from(s in BatchStatement,
        where:
          s.batch_id == ^batch.id and s.kind == :act and s.ref in ^act_ids and
            not is_nil(s.fact_id),
        order_by: s.id
      )
    )
  end

  # -- acts a curator followed -------------------------------------------------------

  defp follow_acts(actor, acc) do
    from(q in QueueItem,
      join: b in Batch,
      on: b.id == q.batch_id,
      join: p in Package,
      on: p.id == b.package_id,
      join: s in BatchStatement,
      on: s.batch_id == b.id and s.kind == :act and s.ref == q.statement_ref,
      where:
        q.kind in [:taxonomy_disagreement, :taxonomy_acceptance] and
          like(q.statement_ref, "a%") and
          b.status == :applied and not is_nil(p.source_id) and not is_nil(s.fact_id),
      select: {s.fact_id, p.source_id},
      distinct: true
    )
    |> Repo.all()
    |> Enum.reduce(acc, fn {fact_id, source_id}, acc ->
      accepted = acc.accepted
      acc = consider(actor, fact_id, source_id, acc)
      if acc.accepted > accepted, do: %{acc | followed: acc.followed + 1}, else: acc
    end)
  end

  # -- accepting a statement -----------------------------------------------------------

  defp consider(actor, fact_id, source_id, acc) do
    case Facts.get_attribution(fact_id, source_id) do
      %Attribution{id: id} = attribution ->
        if MapSet.member?(acc.seen, id),
          do: acc,
          else: decide(actor, attribution, fact_id, %{acc | seen: MapSet.put(acc.seen, id)})

      nil ->
        acc
    end
  end

  defp decide(actor, attribution, fact_id, acc) do
    act = Taxa.act_fact(fact_id)

    cond do
      act == nil or not Facts.needs_acceptance?("taxon_#{elem(act, 0)}", attribution.source_id) ->
        acc

      attribution.accepted_at != nil ->
        %{acc | already: acc.already + 1}

      attribution.declined_at != nil or not holds?(act, attribution.stance) ->
        acc

      true ->
        accept(actor, attribution, act, acc)
    end
  end

  defp accept(actor, attribution, {kind, key}, acc) do
    case TaxonomicDecisions.decide(actor, :accept, attribution.id) do
      {:ok, _result} ->
        %{acc | accepted: acc.accepted + 1}

      {:error, reason} ->
        problem = "#{kind} #{inspect(key)}: the acceptance was refused: #{inspect(reason)}"
        %{acc | problems: [problem | acc.problems]}
    end
  end

  # Whether the tree holds what the statement says (a denial: doesn't).
  defp holds?({:split, _key}, _stance), do: false
  defp holds?(act, :confirm), do: tree_holds?(act)
  defp holds?(act, :deny), do: not tree_holds?(act)

  defp tree_holds?({:placement, %{taxon_id: id, parent_id: parent_id}}),
    do: match?(%{parent_id: ^parent_id}, Taxa.get_taxon(id))

  defp tree_holds?({:name, key}) do
    with %{} = taxon <- Taxa.get_taxon(key.taxon_id),
         %{} = accepted <- Enum.find(taxon.names, &(&1.status == :accepted)) do
      accepted.normalized_name == NameNormalizer.normalize(key.name) and
        to_string(taxon.rank) == to_string(key.rank) and accepted.sensu == key[:sensu] and
        (accepted.authorship == nil or
           NameNormalizer.normalize_authorship(accepted.authorship) ==
             NameNormalizer.normalize_authorship(key[:authorship]))
    else
      _ -> false
    end
  end

  defp tree_holds?({:synonymy, %{name: name, accepted_taxon_id: id}}) do
    normalized = NameNormalizer.normalize(name)

    case Taxa.get_taxon(id) do
      nil ->
        false

      taxon ->
        Enum.any?(taxon.names, &(&1.status == :synonym and &1.normalized_name == normalized))
    end
  end

  defp tree_holds?({:common_name, %{taxon_id: id, common_name: common}}),
    do:
      Enum.any?(
        Taxa.list_common_names(id),
        &(String.downcase(&1.name) == String.downcase(common))
      )

  # -- what is left for a curator ----------------------------------------------------

  defp unmatched(%{reason: reason} = c, _differences) when is_binary(reason),
    do: [report_entry(c, [])]

  defp unmatched(c, differences) do
    normalized = c.name && NameNormalizer.normalize(c.name)
    others = if normalized, do: synonymy_taxa(normalized), else: []

    left =
      Enum.filter(differences, fn d ->
        cond do
          d.taxon_id == c.taxon_id and c.split -> true
          d.taxon_id == c.taxon_id or d.taxon_id in others -> about_name?(d, normalized)
          true -> false
        end
      end)

    if left == [], do: [], else: [report_entry(c, left)]
  end

  defp about_name?(%{aspect: :synonym} = d, normalized) when is_binary(normalized),
    do:
      Enum.any?(
        [d.expected, d.actual],
        &(is_binary(&1) and NameNormalizer.normalize(&1) == normalized)
      )

  defp about_name?(_difference, _normalized), do: false

  defp synonymy_taxa(normalized),
    do:
      Repo.all(
        from(s in SynonymyFact,
          where: s.normalized_name == ^normalized,
          select: s.accepted_taxon_id,
          distinct: true
        )
      )

  defp report_entry(c, differences) do
    %{
      source: c.source && c.source.title,
      name: c.name,
      decision: c.decision,
      differences:
        if(differences == [],
          do: [],
          else: differences |> Sync.format() |> tl() |> Enum.map(&String.trim/1)
        ),
      reason: c.reason
    }
  end

  # -- the report as text ----------------------------------------------------------------

  @doc "The report as text, for the person running the cutover."
  @spec format(report()) :: String.t()
  def format(report) do
    [
      "Phase 1 taxonomy decisions carried over (f923)",
      "  Synonym decisions found: #{report.decisions}",
      "  Statements accepted: #{report.accepted} (acts a curator followed: #{report.followed})",
      "  Accepted already: #{report.already}",
      "",
      "For a curator: #{length(report.unmatched)}",
      Enum.map(report.unmatched, &unmatched_lines/1),
      if(report.problems == [],
        do: [],
        else: [
          "",
          "Acceptances refused: #{length(report.problems)}"
          | Enum.map(report.problems, &"  #{&1}")
        ]
      )
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp unmatched_lines(u) do
    head = "  #{u.name || "?"} (#{u.source || "no Source"}): #{u.decision}"

    [
      if(u.reason, do: "#{head}: #{u.reason}", else: head)
      | Enum.map(u.differences, &"    #{&1}")
    ]
  end
end
