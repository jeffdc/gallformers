defmodule Gallformers.Import.GallMatcher do
  @moduledoc """
  Matches a gall batch's Galls to Gall entries (`9449` Task 12; producer
  guide background, *What Gallformers does on import* step 4). Every Gall
  resolves to one entry, is new, or goes to the admin queue; nothing
  ambiguous is resolved.

  ## Described Galls

  A Gall whose Inducer resolved at species rank or below is matched on
  `identified_by` against the Galls whose current Inducer is that taxon
  (`Gallformers.Catalog.list_gall_summaries_by_inducer/1`):

    * the generation identifies a Gall: with one named, the Galls of that
      generation, or failing those the Galls with none; without one, every
      Gall of the Inducer;
    * then, while several remain, the Host (`identified_by.host` and the
      batch's `host_of` Facts for the Gall) and the plant part break the tie
      (a filter that would leave none is skipped).

  One left is `:resolved` (method `"identified_by"`); several are
  `:ambiguous` with a reason (e.g. a generation the Source never names);
  none is `:new` when the Source presents the Gall as new, otherwise
  `:unresolved` — unless the Gall is `formerly_undescribed`, which is
  matched as undescribed.

  ## Undescribed Galls

  A Gall whose Inducer is only a genus or family, or which has only a Host
  (or is `formerly_undescribed`), is matched against undescribed entries:
  Galls on one of its Hosts (or their genus) whose current Inducer is above
  species rank or unknown and related to the Gall's genus. Candidates are
  ranked by the descriptive words of the entry's name ("Andricus
  q-lobata-spindle-gall" → *spindle*) shared with the Gall's
  `name_as_written` and its Traits in the batch. One candidate is
  proposed, several are offered — both `:ambiguous` (method
  `"undescribed"`), for an admin; none is `:new` when the Source presents
  the Gall as new, else `:unresolved`. Two of the batch's Galls cannot be
  one entry: a candidate proposed for both is offered to both instead.

  A supplied `gallformers_gall_id` that is not the match or among the
  candidates is flagged `"supplied_id_disagrees"`.
  """

  alias Gallformers.Catalog
  alias Gallformers.Import.Resolver
  alias Gallformers.Taxa

  @typedoc "A Gall statement's resolution, as `Gallformers.Import.BatchStatement` takes it."
  @type statement :: %{
          kind: :gall,
          ref: String.t(),
          resolution: :resolved | :ambiguous | :unresolved | :new,
          method: String.t() | nil,
          gall_id: integer() | nil,
          candidate_ids: [integer()],
          flags: [String.t()],
          detail: map()
        }

  @species_or_below ["species", "subspecies", "variety", "form"]
  @species_ranks [:species, :subspecies, :variety, :form]
  @stop_words ~w(gall galls the and of on in a an sp spp wasp unknown from with its this)

  @doc """
  Matches every Gall of `batch` (a decoded gall batch), given the batch's
  taxon statements (`Gallformers.Import.Resolver.resolve_taxa/2`).
  """
  @spec match_galls(map(), [Resolver.statement()]) :: [statement()]
  def match_galls(batch, taxon_statements) do
    taxa = Map.new(taxon_statements, &{&1.ref, &1})
    facts = List.wrap(batch["facts"])

    batch
    |> Map.get("galls", [])
    |> List.wrap()
    |> Enum.map(&match_gall(&1, taxa, facts))
    |> unshare_proposals()
  end

  defp match_gall(g, taxa, facts) do
    ident = g["identified_by"] || %{}
    inducer = taxa[ident["inducer"]]

    base = %{
      kind: :gall,
      ref: g["ref"],
      resolution: :unresolved,
      method: nil,
      gall_id: nil,
      candidate_ids: [],
      flags: [],
      detail:
        %{
          "name_as_written" => g["name_as_written"],
          "generation" => get_in(ident, ["generation", "value"]),
          "plant_part" => get_in(ident, ["plant_part", "value"]),
          "new" => g["new"] == true
        }
        |> Map.reject(fn {_k, v} -> is_nil(v) end)
    }

    hosts = host_ids(g, ident, taxa, facts)

    statement =
      if described?(inducer) do
        described(base, g, ident, inducer, hosts)
      else
        undescribed(base, g, inducer, hosts, facts)
      end

    check_supplied_id(statement, g["gallformers_gall_id"])
  end

  defp described?(%{resolution: :resolved, detail: %{"rank" => rank}}),
    do: rank in @species_or_below

  defp described?(_inducer), do: false

  # -- described Galls ---------------------------------------------------------

  defp described(base, g, ident, inducer, hosts) do
    generation = get_in(ident, ["generation", "value"])
    plant_part = get_in(ident, ["plant_part", "value"])

    candidates =
      [inducer.taxon_id]
      |> Catalog.list_gall_summaries_by_inducer()
      |> by_generation(generation)
      |> tie_break(&shares_host?(&1, host_lineage(hosts)))
      |> tie_break(&(plant_part in Map.get(&1.traits, "plant_part", [])))

    case candidates do
      [one] ->
        %{base | resolution: :resolved, method: "identified_by", gall_id: one.gall_id}

      [_ | _] = several ->
        reason =
          if generation,
            do: "#{length(several)} Galls of this Inducer match",
            else:
              "#{length(several)} Galls of this Inducer match and the Source names no generation"

        ambiguous(base, "identified_by", several, reason)

      [] ->
        cond do
          g["formerly_undescribed"] == true -> undescribed(base, g, inducer, hosts, [])
          g["new"] == true -> %{base | resolution: :new}
          true -> unresolved(base, "no Gall of this Inducer matches")
        end
    end
  end

  defp by_generation(candidates, nil), do: candidates

  defp by_generation(candidates, generation) do
    case Enum.filter(candidates, &(&1.generation == generation)) do
      [] -> Enum.filter(candidates, &is_nil(&1.generation))
      exact -> exact
    end
  end

  # Narrows several candidates with `keep?`, unless that would leave none.
  defp tie_break([_, _ | _] = candidates, keep?) do
    case Enum.filter(candidates, keep?) do
      [] -> candidates
      kept -> kept
    end
  end

  defp tie_break(candidates, _keep?), do: candidates

  defp shares_host?(summary, lineage),
    do: Enum.any?(summary.hosts, &MapSet.member?(lineage, &1.taxon_id))

  # -- undescribed Galls -------------------------------------------------------

  defp undescribed(base, g, inducer, hosts, facts) do
    case genus_scope(inducer) do
      :unresolved ->
        unresolved(base, "its Inducer is not resolved")

      scope ->
        lineage = host_lineage(hosts)

        candidates =
          lineage
          |> MapSet.to_list()
          |> Catalog.list_gall_summaries_by_host()
          |> Enum.filter(&undescribed_entry?(&1, scope))
          |> by_description(gall_words(g, facts))

        undescribed_outcome(base, g, candidates)
    end
  end

  defp undescribed_outcome(base, g, {[], _agree?}) do
    if g["new"] == true,
      do: %{base | resolution: :new},
      else: unresolved(base, "no undescribed Gall on its Host matches")
  end

  defp undescribed_outcome(base, _g, {[one], agree?}) do
    reason =
      if agree?,
        do: "one undescribed candidate (admin confirms)",
        else: "one undescribed candidate, its description differs (admin checks)"

    base
    |> ambiguous("undescribed", [one], reason)
    |> put_in([:detail, "proposed"], one.gall_id)
  end

  defp undescribed_outcome(base, _g, {several, _agree?}),
    do: ambiguous(base, "undescribed", several, "several undescribed candidates (admin picks)")

  # The taxa an undescribed entry's Inducer may be: the Gall's genus (or
  # family) with its ancestors; nil when the Gall has no Inducer.
  defp genus_scope(nil), do: nil

  defp genus_scope(%{resolution: :resolved, taxon_id: id, detail: %{"rank" => rank}}) do
    genus_id =
      if rank in @species_or_below do
        id |> Taxa.ancestors() |> Enum.find_value(&(&1.rank == :genus && &1.id))
      else
        id
      end

    genus_id && lineage([genus_id])
  end

  defp genus_scope(%{resolution: :new, detail: %{"name_as_written" => name} = detail}) do
    genus = (detail["name_reading"] || name) |> String.split() |> List.first()

    case genus && Taxa.resolve_name(genus, rank: :genus) do
      {:ok, taxon} -> lineage([taxon.id])
      _ -> nil
    end
  end

  defp genus_scope(_inducer), do: :unresolved

  # An undescribed entry: no Inducer, or only Inducers above species rank
  # that are related to the scope (the same taxon, an ancestor of it, or a
  # descendant).
  defp undescribed_entry?(summary, scope) do
    Enum.all?(summary.inducers, &(&1.rank not in @species_ranks)) and
      (scope == nil or summary.inducers == [] or
         Enum.any?(summary.inducers, &related?(&1.taxon_id, scope)))
  end

  defp related?(taxon_id, scope) do
    MapSet.member?(scope, taxon_id) or
      taxon_id |> Taxa.ancestors() |> Enum.any?(&MapSet.member?(scope, &1.id))
  end

  # Keeps the candidates sharing the most descriptive words with the Gall;
  # says whether the best shares any.
  defp by_description([], _words), do: {[], false}

  defp by_description(candidates, words) do
    scored = Enum.map(candidates, &{MapSet.size(MapSet.intersection(descriptor(&1), words)), &1})
    best = scored |> Enum.map(&elem(&1, 0)) |> Enum.max()
    {for({score, c} <- scored, score == best, do: c), best > 0}
  end

  # The descriptive words of an entry's name: its words less the names of
  # its Inducers and Hosts and the stop words.
  defp descriptor(summary) do
    names =
      Enum.flat_map(summary.inducers ++ summary.hosts, &String.split(String.downcase(&1.name)))

    summary.name |> words() |> MapSet.difference(MapSet.new(names))
  end

  defp gall_words(g, facts) do
    traits =
      for %{"kind" => "trait", "gall" => ref, "value" => %{"value" => value}} <- facts,
          ref == g["ref"],
          do: value

    words(Enum.join([g["name_as_written"] || "" | traits], " "))
  end

  defp words(text) do
    ~r/[a-z]{3,}/
    |> Regex.scan(String.downcase(text))
    |> List.flatten()
    |> MapSet.new()
    |> MapSet.difference(MapSet.new(@stop_words))
  end

  # -- Hosts -------------------------------------------------------------------

  # The resolved Hosts the batch gives the Gall.
  defp host_ids(g, ident, taxa, facts) do
    from_facts =
      for %{"kind" => "relationship", "type" => "host_of", "stance" => "confirm"} = f <- facts,
          f["object"] == g["ref"],
          do: f["subject"]

    for ref <- Enum.uniq([ident["host"] | from_facts]),
        %{resolution: :resolved, taxon_id: id} <- [taxa[ref]],
        do: id
  end

  # The Hosts and their ancestors (an entry may hold the genus as its Host).
  defp host_lineage(host_ids), do: lineage(host_ids)

  defp lineage(ids) do
    Enum.reduce(ids, MapSet.new(ids), fn id, acc ->
      id |> Taxa.ancestors() |> Enum.reduce(acc, &MapSet.put(&2, &1.id))
    end)
  end

  # -- outcomes ----------------------------------------------------------------

  defp ambiguous(base, method, candidates, reason) do
    %{
      base
      | resolution: :ambiguous,
        method: method,
        candidate_ids: Enum.map(candidates, & &1.gall_id),
        detail: Map.put(base.detail, "reason", reason)
    }
  end

  defp unresolved(base, reason),
    do: %{base | resolution: :unresolved, detail: Map.put(base.detail, "reason", reason)}

  defp check_supplied_id(statement, nil), do: statement

  defp check_supplied_id(statement, id) do
    if id == statement.gall_id or id in statement.candidate_ids,
      do: statement,
      else: %{statement | flags: statement.flags ++ ["supplied_id_disagrees"]}
  end

  # Two of the batch's Galls cannot be one entry: offer a shared proposal to
  # both instead of proposing it.
  defp unshare_proposals(statements) do
    shared =
      statements
      |> Enum.map(& &1.detail["proposed"])
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, n} -> n > 1 end)
      |> MapSet.new(&elem(&1, 0))

    Enum.map(statements, fn s ->
      if MapSet.member?(shared, s.detail["proposed"]) do
        detail =
          s.detail
          |> Map.delete("proposed")
          |> Map.put("reason", "the candidate is proposed for another of this batch's Galls too")

        %{s | detail: detail}
      else
        s
      end
    end)
  end

  # -- the admin queue ---------------------------------------------------------

  @doc """
  The queue items the Gall statements call for, as
  `%{kind, statement_ref, subject, proposal, reason}`: undescribed
  candidates are `:undescribed_gall` (with the proposed one, if any), other
  ambiguous matches `:ambiguous_match`, unresolved Galls
  `:unresolved_name`.
  """
  @spec queue_items([statement()]) :: [map()]
  def queue_items(statements) do
    for %{kind: :gall, resolution: resolution} = s <- statements,
        resolution in [:ambiguous, :unresolved] do
      %{
        kind: queue_kind(s),
        statement_ref: s.ref,
        subject: Map.take(s.detail, ["name_as_written", "generation", "plant_part", "new"]),
        proposal:
          %{"candidate_ids" => s.candidate_ids, "proposed" => s.detail["proposed"]}
          |> Map.reject(fn {_k, v} -> is_nil(v) end),
        reason: s.detail["reason"]
      }
    end
  end

  defp queue_kind(%{resolution: :unresolved}), do: :unresolved_name
  defp queue_kind(%{method: "undescribed"}), do: :undescribed_gall
  defp queue_kind(_statement), do: :ambiguous_match
end
