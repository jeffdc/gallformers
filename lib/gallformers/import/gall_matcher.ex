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

  Each candidate is compared with what the batch says of the Gall
  (`Gallformers.Import.GallComparison`: Host, where on the plant,
  detachable, generation and season, form); candidates are ranked by how
  many fields agree, each with its comparison (`detail["comparisons"]`). A
  lone candidate that conflicts with the Source (a different coarse plant
  part or form) is not resolved or proposed: it is `:ambiguous`, only the
  best match (`detail["best"]`), with the fields it conflicts on
  (`detail["conflicts"]`), for an admin to check.

  One left is `:resolved` (method `"identified_by"`), unless another of the
  batch's Galls resolves to it too (their identifying fields are equal):
  then both are `:ambiguous`, offered that entry for an admin to decide.
  Two Galls of different generations (a fundatrix and its apterae) matching
  one entry that names no generation are a pair: one of them is the entry,
  the other is new. Both are `:ambiguous`, each with `detail["pair"]` (the
  other's ref, name and generation); the second is flagged
  `"paired_with_gall"` and has no queue item, the first's item decides both
  (`settle_pairs/1`). A lone Gall of a generation the Source never names,
  when the Inducer alternates generations (generation group `heterogony`),
  is only proposed: the Source may describe the other generation.

  Several are `:ambiguous` with a reason (e.g. a generation the Source never
  names); none is `:new` when the Source presents the Gall as new, otherwise
  `:unresolved` — unless the Gall is `formerly_undescribed`, which is
  matched as undescribed.

  ## Galls waiting on their Inducer

  A Gall whose Inducer is unresolved, ambiguous or a held-valid synonym is
  not matched: it is `:unresolved`, flagged `"waits_on_inducer"` with the
  Inducer's ref as `detail["waits_on"]`, and has no queue item of its own —
  the Inducer's item decides it. Once the Inducer is decided (taxon
  decisions are overlaid before matching) the Gall is matched as any other;
  once it is skipped the Gall is queued on its own.

  ## Undescribed Galls

  A Gall whose Inducer is only a genus or family, or which has only a Host
  (or is `formerly_undescribed`), is matched against undescribed entries:
  Galls on one of its Hosts (or their genus) whose current Inducer is above
  species rank or unknown and within the rank the Source states — that
  taxon (a species' genus), its descendants, or its ancestors up to its
  family ("Unknown (Cynipidae)"), never a taxon that only shares an
  ancestor. An entry whose plant parts are recorded must share the Gall's
  (the leaf's parts count as one, as do bud and stem). Candidates are ranked
  by the descriptive words of the entry's name ("Andricus
  q-lobata-spindle-gall" → *spindle*) shared with the Gall's
  `name_as_written` and its Traits in the batch, then by agreeing fields.
  An undescribed match is never firm: one candidate is only the best match
  (`detail["best"]`), several are offered — both `:ambiguous` (method
  `"undescribed"`), for an admin. Two of the batch's Galls cannot be one
  entry: a candidate picked (proposed or best) for both is offered to both
  instead, and a candidate picked for one is dropped from the others'
  candidates.

  With no candidate while one of its Hosts is not settled (unresolved or
  ambiguous, not left out), the Gall waits on that Host: it is
  `:unresolved`, flagged `"waits_on_host"` with the Host's ref as
  `detail["waits_on"]`, and has no queue item of its own; it is matched
  again once the Host is decided (Nastasi & Davis's "Horkelia stem gall",
  on a Host Gallformers had no name for, had been proposed as new).

  With no candidate, the Galls whose current Inducer is a taxon the batch
  says `emerged_from` the Gall are offered (method `"emerged_from"`; one is
  only the best match). With none of those, the undescribed entries of
  the Inducer's genus on other plants of its Hosts' genera are looked at
  (`c8c3`): a Source names an undescribed Gall by its Host's common name
  ("Toothed rosinweed cryptic stem gall"), while Gallformers codes it by
  the Host's epithet and may hold it on another taxon of that name
  (*Antistrophus s-dentatum-cryptic-stem-gall*, on Silphium asteriscus var.
  dentatum, for the Source's S. dentatum). Those whose code has an epithet
  of the Source's Host names are offered, else those sharing the most
  descriptive words, if any do (method `"undescribed"`, one only the best
  match). When the genera hold such entries but none matches, nothing is
  proposed. Otherwise the Gall is `:new` when the Source presents it as
  new, else `:unresolved` with new proposed (`detail["proposed"]` `"new"`,
  only a suggestion: `Gallformers.Import.Proposals`).

  A supplied `gallformers_gall_id` that is not the match or among the
  candidates is flagged `"supplied_id_disagrees"` — except in a batch
  reading a Gall's note (`source.note`), whose Gall with the note's ID is
  that Gall (method `"note"`), with no matching; and in a curator's own
  Gallformers batch (no note, `Gallformers.Curation`), whose Gall with an ID
  Gallformers holds is that Gall (method `"gallformers_gall_id"`).
  """

  alias Gallformers.Catalog
  alias Gallformers.Import.GallComparison
  alias Gallformers.Import.Resolver
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank

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
  @rank_words ~w(var subsp ssp forma)
  @open [:unresolved, :ambiguous]
  @not_queued ["waits_on_inducer", "waits_on_host", "paired_with_gall"]
  @supplied "gallformers_gall_id"

  @doc """
  Matches every Gall of `batch` (a decoded gall batch), given the batch's
  taxon statements (`Gallformers.Import.Resolver.resolve_taxa/2`) with the
  admin's decisions on them overlaid.
  """
  @spec match_galls(map(), [Resolver.statement()]) :: [statement()]
  def match_galls(batch, taxon_statements) do
    taxa = Map.new(taxon_statements, &{&1.ref, &1})
    facts = List.wrap(batch["facts"])
    noted = noted_gall_id(batch["source"])
    curated? = curated?(batch["source"])

    batch
    |> Map.get("galls", [])
    |> List.wrap()
    |> Enum.map(fn g ->
      id = g["gallformers_gall_id"]

      cond do
        noted && id == noted -> note_gall(g, noted, "note")
        curated? and is_integer(id) and Catalog.get_gall(id) != nil -> note_gall(g, id, @supplied)
        true -> match_gall(g, taxa, facts)
      end
    end)
    |> unshare_resolutions()
    |> unshare_proposals()
    |> drop_sibling_proposals()
    |> unshare_proposals()
  end

  # A batch reading a Gall's note (`source.note`) is about that Gall by
  # construction: the Gall it names with the note's ID is that Gall, when
  # Gallformers holds it (a missing one is the Source step's queue item).
  defp noted_gall_id(%{"gallformers" => true, "note" => %{"gallformers_gall_id" => id}})
       when is_integer(id),
       do: if(Catalog.get_gall(id), do: id)

  defp noted_gall_id(_source), do: nil

  # A curator's own statement (Gallformers, no note), written from the
  # Gall's page, or a curator's reading fix of a Source (matter 87a1): the
  # Gall it names by ID is that Gall.
  defp curated?(%{"gallformers" => true} = source), do: not Map.has_key?(source, "note")
  defp curated?(%{"reading_of" => %{}}), do: true
  defp curated?(_source), do: false

  defp note_gall(g, gall_id, method) do
    %{
      kind: :gall,
      ref: g["ref"],
      resolution: :resolved,
      method: method,
      gall_id: gall_id,
      candidate_ids: [],
      flags: [],
      detail: %{"name_as_written" => g["name_as_written"], "new" => false}
    }
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

    m = %{
      g: g,
      ident: ident,
      inducer: inducer,
      hosts: hosts,
      host_statements: host_statements(g, ident, taxa, facts),
      facts: facts,
      emerged: emerged_from(g, taxa, facts),
      source: GallComparison.source_side(g, facts, hosts)
    }

    statement =
      cond do
        described?(inducer) -> described(base, m)
        open?(inducer) and "skipped" in inducer.flags -> skipped_inducer(base)
        open?(inducer) -> waits_on_inducer(base, ident["inducer"])
        true -> undescribed(base, m)
      end

    check_supplied_id(statement, g["gallformers_gall_id"])
  end

  defp described?(%{resolution: :resolved, detail: %{"rank" => rank}}),
    do: rank in @species_or_below

  defp described?(_inducer), do: false

  defp open?(%{resolution: resolution}), do: resolution in @open
  defp open?(_inducer), do: false

  # -- waiting on the Inducer --------------------------------------------------

  defp waits_on_inducer(base, ref) do
    %{
      base
      | flags: ["waits_on_inducer"],
        detail:
          Map.merge(base.detail, %{
            "waits_on" => ref,
            "reason" => "waits on its Inducer (#{ref})"
          })
    }
  end

  defp skipped_inducer(base),
    do: unresolved(base, "its Inducer was skipped: the Gall is new, or skipped too")

  # -- described Galls ---------------------------------------------------------

  defp described(base, %{g: g, ident: ident, inducer: inducer, hosts: hosts} = m) do
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
        lone_candidate(base, one, generation, inducer, m.source)

      [_ | _] = several ->
        reason =
          if generation,
            do: "#{length(several)} Galls of this Inducer match",
            else:
              "#{length(several)} Galls of this Inducer match and the Source names no generation"

        ranked(base, "identified_by", several, m.source, reason)

      [] ->
        cond do
          g["formerly_undescribed"] == true -> undescribed(base, m)
          g["new"] == true -> %{base | resolution: :new}
          true -> unresolved(base, "no Gall of this Inducer matches")
        end
    end
  end

  # One Gall left resolves it, unless what the Source says conflicts with
  # it (a different plant part or form: only the best match, for an admin
  # to check), or the Source names no generation, the Gall has one and the
  # Inducer alternates generations: the Source may describe the other
  # generation, so it is only proposed.
  defp lone_candidate(base, one, generation, inducer, source) do
    comparison = GallComparison.compare(source, one)

    cond do
      comparison.conflicts != [] ->
        reason =
          "one Gall of this Inducer, which conflicts with the Source on " <>
            "#{conflict_labels(comparison.conflicts)} (admin checks)"

        base
        |> ambiguous("identified_by", [one], reason)
        |> with_comparisons([{one, comparison}])
        |> pick("best", one.gall_id)

      generation == nil and one.generation != nil and heterogony?(inducer.taxon_id) ->
        reason =
          "one Gall of this Inducer, of the #{one.generation} generation, which the Source " <>
            "does not name (admin confirms)"

        base
        |> ambiguous("identified_by", [one], reason)
        |> with_comparisons([{one, comparison}])
        |> pick("proposed", one.gall_id)

      true ->
        %{base | resolution: :resolved, method: "identified_by", gall_id: one.gall_id}
    end
  end

  defp conflict_labels(fields), do: Enum.map_join(fields, " and ", &GallComparison.label/1)

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

  # Whether the generation groups that apply to the taxon (those of its
  # nearest mapped ancestor, itself included) include heterogony.
  defp heterogony?(taxon_id) do
    mapped =
      for group <- Catalog.list_generation_groups(), t <- group.taxa, reduce: %{} do
        acc -> Map.update(acc, t.taxon_id, [group.name], &[group.name | &1])
      end

    groups =
      [taxon_id | Enum.map(Taxa.ancestors(taxon_id), & &1.id)]
      |> Enum.find_value([], &Map.get(mapped, &1))

    "heterogony" in groups
  end

  # -- undescribed Galls -------------------------------------------------------

  defp undescribed(base, %{g: g, inducer: inducer, hosts: hosts, facts: facts} = m) do
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
          |> by_organ(organs(g, facts))
          |> by_description(gall_words(g, facts))

        case {candidates, open_host(m)} do
          {{[], _agree?}, ref} when is_binary(ref) -> waits_on_host(base, ref)
          _ -> undescribed_outcome(base, Map.put(m, :scope, scope), candidates)
        end
    end
  end

  # A Host of the Gall's not settled yet (unresolved or ambiguous, and not
  # left out): nothing can match on it until it is.
  defp open_host(m) do
    Enum.find_value(m.host_statements, fn {ref, s} ->
      if open?(s) and "skipped" not in s.flags, do: ref
    end)
  end

  defp waits_on_host(base, ref) do
    %{
      base
      | flags: ["waits_on_host"],
        detail:
          Map.merge(base.detail, %{
            "waits_on" => ref,
            "reason" => "waits on its Host (#{ref})"
          })
    }
  end

  defp undescribed_outcome(base, m, {[], _agree?}) do
    case emerged_candidates(m) do
      [] ->
        if m.g["new"] == true,
          do: %{base | resolution: :new},
          else: on_host_genus(base, m, near_entries(m))

      candidates ->
        refs = Enum.map_join(m.emerged, ", ", &elem(&1, 0))

        reason =
          "no undescribed Gall on its Host matches; the Galls of #{refs}, which emerged from it"

        statement = ranked(base, "emerged_from", candidates, m.source, reason)

        case candidates do
          [one] -> pick(statement, "best", one.gall_id)
          _several -> statement
        end
    end
  end

  # An undescribed match is never firm: one candidate is only the best
  # match, for an admin to confirm.
  defp undescribed_outcome(base, m, {[one], agree?}) do
    reason =
      if agree?,
        do: "one undescribed candidate (admin confirms)",
        else: "one undescribed candidate, its description differs (admin checks)"

    base
    |> ranked("undescribed", [one], m.source, reason)
    |> pick("best", one.gall_id)
  end

  defp undescribed_outcome(base, m, {several, _agree?}),
    do:
      ranked(
        base,
        "undescribed",
        several,
        m.source,
        "several undescribed candidates (admin picks)"
      )

  # Nothing on the Gall's own Hosts: the undescribed entries on other
  # plants of their genera that match (a Host's epithet the Source uses in
  # the entry's code, else its descriptive words) are offered, never firm.
  # While the genera hold undescribed Galls of the Inducer's genus but none
  # matches, nothing is proposed; with none, new is.
  defp on_host_genus(base, m, %{offered: [], count: count, genera: genera})
       when count > 0 and m.scope != nil do
    unresolved(
      base,
      "no undescribed Gall on its Host matches; Gallformers holds #{count} undescribed " <>
        "#{plural(count, "Gall", "Galls")} of its Inducer's genus on other " <>
        "#{genera} plants: one of them, or a new Gall"
    )
  end

  defp on_host_genus(base, _m, %{offered: []}) do
    base
    |> unresolved("no undescribed Gall on its Host matches: new proposed")
    |> put_in([:detail, "proposed"], "new")
  end

  defp on_host_genus(base, m, %{offered: offered, genera: genera}) do
    summaries = Enum.map(offered, &Catalog.gall_summary(&1.id))

    case summaries do
      [one] ->
        base
        |> ranked(
          "undescribed",
          [one],
          m.source,
          "no undescribed Gall on its Host; one on other #{genera} plants matches (admin confirms)"
        )
        |> pick("best", one.gall_id)

      several ->
        ranked(
          base,
          "undescribed",
          several,
          m.source,
          "no undescribed Gall on its Host; #{length(several)} on other #{genera} plants match " <>
            "(admin picks)"
        )
    end
  end

  defp plural(1, one, _many), do: one
  defp plural(_n, _one, many), do: many

  # The undescribed entries of the Inducer's genus (any, with no Inducer)
  # on plants of the Gall's Hosts' genera, on one of its organs (the ID
  # tool's index, `Gallformers.Catalog.identify/1`): how many, the genera's
  # names, and those offered.
  defp near_entries(m) do
    genera = host_genera(m.hosts)
    organs = organs(m.g, m.facts)

    rows =
      for genus <- genera,
          row <-
            Catalog.identify(%{
              host_group_id: genus.id,
              undescribed: true,
              inducer_family_id: m.scope && m.scope.id
            }),
          uniq: true,
          do: row

    rows = by_organ(rows, organs)

    %{
      count: length(rows),
      genera: Enum.map_join(genera, " and ", &Taxa.accepted_name/1),
      offered: offered(rows, host_epithets(m.host_statements), gall_words(m.g, m.facts))
    }
  end

  # The entries whose code has an epithet of the Source's Host names
  # ("Antistrophus s-dentatum-cryptic-stem-gall" for "S. dentatum"), the
  # best by descriptive words among them; else those sharing the most
  # descriptive words with the Gall, if any do.
  defp offered(rows, epithets, words) do
    case Enum.filter(rows, &(code_epithet(&1.name) in epithets)) do
      [] ->
        case by_description_with(rows, words, &code_words/1) do
          {best, true} -> best
          {_best, false} -> []
        end

      hits ->
        hits |> by_description_with(words, &code_words/1) |> elem(0)
    end
  end

  # The genera of the Hosts (a genus Host itself).
  defp host_genera(host_ids) do
    host_ids
    |> Enum.map(fn id ->
      taxon = Taxa.get_taxon!(id)

      if taxon.rank == :genus,
        do: taxon,
        else: id |> Taxa.ancestors() |> Enum.find(&(&1.rank == :genus))
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  # The epithets of the names the Source and the tree give the Gall's
  # Hosts ("S. dentatum", "Silphium dentatum": dentatum).
  defp host_epithets(host_statements) do
    for {_ref, s} <- host_statements,
        name <- [s.detail["name_as_written"], s.detail["name_reading"], s.detail["matched"]],
        is_binary(name),
        [_genus | rest] = String.split(name),
        word <- words(Enum.join(rest, " ")),
        word not in @rank_words,
        into: MapSet.new(),
        do: word
  end

  # An undescribed entry's code is its Host's genus initial and epithet,
  # then what it is ("s-dentatum-cryptic-stem-gall").
  defp code(name), do: name |> String.split() |> List.last("") |> String.downcase()

  defp code_epithet(name) do
    case Regex.run(~r/^[a-z]-([a-z]+)-/, code(name)) do
      [_, epithet] -> epithet
      nil -> nil
    end
  end

  defp code_words(row),
    do: row.name |> code() |> words() |> MapSet.delete(code_epithet(row.name))

  defp best_undescribed(base, gall_id, reason) do
    base
    |> ambiguous("undescribed", [%{gall_id: gall_id}], reason)
    |> pick("best", gall_id)
  end

  # The taxa an undescribed entry's Inducer may be, around the rank the
  # Source states (a species' genus): nil when the Gall has no Inducer.
  defp genus_scope(nil), do: nil

  defp genus_scope(%{resolution: :resolved, taxon_id: id, detail: %{"rank" => rank}}) do
    genus_id =
      if rank in @species_or_below do
        id |> Taxa.ancestors() |> Enum.find_value(&(&1.rank == :genus && &1.id))
      else
        id
      end

    genus_id && scope(genus_id)
  end

  defp genus_scope(%{resolution: :new, detail: %{"name_as_written" => name} = detail}) do
    genus = (detail["name_reading"] || name) |> String.split() |> List.first()

    case genus && Taxa.resolve_name(genus, rank: :genus) do
      {:ok, taxon} -> scope(taxon.id)
      _ -> nil
    end
  end

  defp genus_scope(_inducer), do: :unresolved

  # The stated taxon, and it with its ancestors up to its family (an entry
  # known only to the family may be this Gall; one of a sibling tribe not).
  defp scope(id) do
    up =
      id
      |> Taxa.ancestors()
      |> Enum.take_while(&(&1.rank == :family or Rank.below?(&1.rank, :family)))

    %{id: id, up: MapSet.new([id | Enum.map(up, & &1.id)])}
  end

  # An undescribed entry: no Inducer, or only Inducers above species rank
  # that are within the scope.
  defp undescribed_entry?(summary, scope) do
    Enum.all?(summary.inducers, &(&1.rank not in @species_ranks)) and
      (scope == nil or summary.inducers == [] or
         Enum.any?(summary.inducers, &related?(&1.taxon_id, scope)))
  end

  # The stated taxon, one of its ancestors up to the family, or a descendant.
  defp related?(taxon_id, scope) do
    MapSet.member?(scope.up, taxon_id) or
      taxon_id |> Taxa.ancestors() |> Enum.any?(&(&1.id == scope.id))
  end

  # The organs of the Gall's plant parts (`identified_by` and its Traits in
  # the batch).
  defp organs(g, facts) do
    from_traits =
      for %{"kind" => "trait", "trait" => "plant_part", "gall" => ref} = f <- facts,
          ref == g["ref"],
          value = trait_value(f),
          is_binary(value),
          do: value

    [get_in(g, ["identified_by", "plant_part", "value"]) | from_traits]
    |> Enum.filter(&is_binary/1)
    |> MapSet.new(&organ/1)
  end

  # Plant parts a Source and an entry may record differently for one Gall.
  defp organ(part) do
    cond do
      part == "petiole" or String.contains?(part, "leaf") -> "leaf"
      part in ["bud", "stem"] -> "stem"
      true -> part
    end
  end

  # Keeps the entries on one of the organs, or with no plant part recorded.
  defp by_organ(candidates, organs) do
    if MapSet.size(organs) == 0,
      do: candidates,
      else: Enum.filter(candidates, &(plant_parts(&1) == [] or on_organ?(&1, organs)))
  end

  defp plant_parts(summary), do: Map.get(summary.traits, "plant_part", [])

  defp on_organ?(summary, organs),
    do: Enum.any?(plant_parts(summary), &MapSet.member?(organs, organ(&1)))

  # Keeps the candidates sharing the most descriptive words with the Gall;
  # says whether the best shares any.
  defp by_description(candidates, words),
    do: by_description_with(candidates, words, &descriptor/1)

  defp by_description_with([], _words, _descriptor), do: {[], false}

  defp by_description_with(candidates, words, descriptor) do
    scored = Enum.map(candidates, &{MapSet.size(MapSet.intersection(descriptor.(&1), words)), &1})
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
      for %{"kind" => "trait", "gall" => ref} = f <- facts,
          ref == g["ref"],
          word <- [trait_value(f), f["term"]],
          is_binary(word),
          do: word

    words(Enum.join([g["name_as_written"] || "" | traits], " "))
  end

  # A trait Fact's category: format 4's suggestion, format 3's value.
  defp trait_value(f), do: get_in(f, ["category", "value"]) || get_in(f, ["value", "value"])

  defp words(text) do
    ~r/[a-z]{3,}/
    |> Regex.scan(String.downcase(text))
    |> List.flatten()
    |> MapSet.new()
    |> MapSet.difference(MapSet.new(@stop_words))
  end

  # -- emerged from ------------------------------------------------------------

  # The taxa the batch says emerged from the Gall, as {ref, taxon_id}: the
  # resolved ones, and a held-valid synonym's taxon (only offered).
  defp emerged_from(g, taxa, facts) do
    refs =
      for %{"kind" => "relationship", "type" => "emerged_from", "stance" => "confirm"} = f <-
            facts,
          f["object"] == g["ref"],
          uniq: true,
          do: f["subject"]

    for ref <- refs, id = emerged_taxon(taxa[ref]), is_integer(id), do: {ref, id}
  end

  defp emerged_taxon(%{resolution: :resolved, taxon_id: id}), do: id

  defp emerged_taxon(%{flags: flags, candidate_ids: [id]}),
    do: if("synonym_held_valid" in flags, do: id)

  defp emerged_taxon(_statement), do: nil

  defp emerged_candidates(%{emerged: []}), do: []

  defp emerged_candidates(%{emerged: emerged, hosts: hosts, g: g, facts: facts}) do
    organs = organs(g, facts)

    emerged
    |> Enum.map(&elem(&1, 1))
    |> Catalog.list_gall_summaries_by_inducer()
    |> tie_break(&shares_host?(&1, host_lineage(hosts)))
    |> tie_break(&on_organ?(&1, organs))
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

  # The Gall's Host statements by ref, resolved or not.
  defp host_statements(g, ident, taxa, facts) do
    from_facts =
      for %{"kind" => "relationship", "type" => "host_of", "stance" => "confirm"} = f <- facts,
          f["object"] == g["ref"],
          do: f["subject"]

    for ref <- Enum.uniq([ident["host"] | from_facts]),
        %{} = s <- [taxa[ref]],
        do: {ref, s}
  end

  # The Hosts and their ancestors (an entry may hold the genus as its Host).
  defp host_lineage(host_ids), do: lineage(host_ids)

  defp lineage(ids) do
    Enum.reduce(ids, MapSet.new(ids), fn id, acc ->
      id |> Taxa.ancestors() |> Enum.reduce(acc, &MapSet.put(&2, &1.id))
    end)
  end

  # -- outcomes ----------------------------------------------------------------

  # Ambiguous between `candidates`, ranked by how many fields agree with
  # what the Source says, each with its comparison (`detail["comparisons"]`).
  defp ranked(base, method, candidates, source, reason) do
    ranked = GallComparison.rank(candidates, source)

    base
    |> ambiguous(method, Enum.map(ranked, &elem(&1, 0)), reason)
    |> with_comparisons(ranked)
  end

  defp with_comparisons(statement, ranked),
    do:
      put_in(
        statement,
        [:detail, "comparisons"],
        Enum.map(ranked, &GallComparison.to_proposal(elem(&1, 1)))
      )

  # Picks `gall_id` as the `"proposed"` (firm) or `"best"` (only a
  # suggestion) candidate, with its conflicts, if any.
  defp pick(statement, key, gall_id) do
    conflicts =
      statement.detail
      |> Map.get("comparisons", [])
      |> Enum.find_value([], &(&1["gall_id"] == gall_id && &1["conflicts"]))

    detail =
      statement.detail
      |> Map.drop(["proposed", "best", "conflicts"])
      |> Map.put(key, gall_id)

    detail = if conflicts == [], do: detail, else: Map.put(detail, "conflicts", conflicts)
    %{statement | detail: detail}
  end

  # The candidate an item picks, firm or not.
  defp picked(%{detail: detail}) do
    case detail["proposed"] || detail["best"] do
      id when is_integer(id) -> id
      _ -> nil
    end
  end

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

  # -- the batch's Galls together ----------------------------------------------

  # Two of the batch's Galls cannot be one entry: an entry resolved for
  # several (their identifying fields are equal) is offered to each of them,
  # for an admin to decide (no silent merges); two of different generations
  # resolved to an entry with none are a pair.
  defp unshare_resolutions(statements) do
    replacements =
      statements
      |> Enum.filter(&(&1.resolution == :resolved))
      |> Enum.group_by(& &1.gall_id)
      |> Enum.flat_map(fn
        {_id, [_one]} -> []
        {id, [a, b]} -> if pair?(a, b), do: pair(a, b, id), else: unshare([a, b], id)
        {id, several} -> unshare(several, id)
      end)
      |> Map.new(&{&1.ref, &1})

    Enum.map(statements, &Map.get(replacements, &1.ref, &1))
  end

  defp unshare(statements, gall_id) do
    reason = "the entry matches another of this batch's Galls too"

    for s <- statements,
        do: ambiguous(%{s | gall_id: nil}, s.method, [%{gall_id: gall_id}], reason)
  end

  # Two Galls of different generations: the entry they share names none
  # (`by_generation/2` fell back to the Galls without one for both).
  defp pair?(a, b) do
    a.method == "identified_by" and b.method == "identified_by" and
      is_binary(a.detail["generation"]) and is_binary(b.detail["generation"]) and
      a.detail["generation"] != b.detail["generation"]
  end

  defp pair(a, b, gall_id) do
    reason =
      "#{a.ref} (#{a.detail["generation"]}) and #{b.ref} (#{b.detail["generation"]}) both " <>
        "match this entry, which names no generation: one of them is it, the other is new"

    [
      a |> paired(b, gall_id, reason),
      b |> paired(a, gall_id, reason) |> Map.update!(:flags, &(&1 ++ ["paired_with_gall"]))
    ]
  end

  defp paired(s, mate, gall_id, reason) do
    s = ambiguous(%{s | gall_id: nil}, s.method, [%{gall_id: gall_id}], reason)
    pair = Map.take(mate.detail, ["name_as_written", "generation"]) |> Map.put("ref", mate.ref)
    put_in(s, [:detail, "pair"], pair)
  end

  # Two of the batch's Galls cannot be one entry: offer a shared proposal to
  # both instead of proposing it.
  defp unshare_proposals(statements) do
    shared =
      statements
      |> Enum.map(&picked/1)
      |> Enum.filter(&is_integer/1)
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, n} -> n > 1 end)
      |> MapSet.new(&elem(&1, 0))

    Enum.map(statements, fn s ->
      if MapSet.member?(shared, picked(s)) do
        detail =
          s.detail
          |> Map.drop(["proposed", "best", "conflicts"])
          |> Map.put("reason", "the candidate is proposed for another of this batch's Galls too")

        %{s | detail: detail}
      else
        s
      end
    end)
  end

  # Two of the batch's Galls cannot be one entry: a candidate proposed for
  # one is not a candidate of the others' undescribed matches.
  defp drop_sibling_proposals(statements) do
    proposed =
      for s <- statements,
          id = picked(s),
          is_integer(id),
          into: %{},
          do: {id, s.ref}

    Enum.map(statements, &drop_proposed(&1, proposed))
  end

  defp drop_proposed(
         %{method: "undescribed", resolution: :ambiguous, detail: detail} = s,
         proposed
       )
       when not is_map_key(detail, "proposed") and not is_map_key(detail, "best") do
    {taken, left} = Enum.split_with(s.candidate_ids, &Map.has_key?(proposed, &1))
    elsewhere = Enum.map_join(taken, ", ", &"#{&1} is proposed for #{proposed[&1]}")

    case left do
      _ when taken == [] ->
        s

      [] ->
        %{s | candidate_ids: []}
        |> keep_comparisons([])
        |> unresolved("#{elsewhere}: new proposed")
        |> put_in([:detail, "proposed"], "new")

      [one] ->
        s
        |> keep_comparisons([one])
        |> best_undescribed(one, "#{elsewhere}; one undescribed candidate left (admin confirms)")

      several ->
        keep_comparisons(
          %{
            s
            | candidate_ids: several,
              detail:
                Map.put(detail, "reason", "#{elsewhere}; several undescribed candidates left")
          },
          several
        )
    end
  end

  defp drop_proposed(statement, _proposed), do: statement

  defp keep_comparisons(%{detail: %{"comparisons" => comparisons}} = s, ids),
    do: put_in(s, [:detail, "comparisons"], Enum.filter(comparisons, &(&1["gall_id"] in ids)))

  defp keep_comparisons(statement, _ids), do: statement

  @doc """
  Settles the pairs of `statements` (Gall statements with the admin's
  decisions overlaid, `Gallformers.Import.Queue.overlay/2`): one of a pair
  decided as the entry makes the other new; decided new, the other is the
  entry (method `"pair"`). Decided otherwise or skipped, the other is no
  longer paired and is queued on its own.
  """
  @spec settle_pairs([statement()]) :: [statement()]
  def settle_pairs(statements) do
    by_ref = Map.new(statements, &{&1.ref, &1})
    Enum.map(statements, &settle_pair(&1, by_ref[get_in(&1.detail, ["pair", "ref"])]))
  end

  defp settle_pair(%{resolution: :ambiguous, candidate_ids: [id]} = s, %{} = mate) do
    settled = %{s | flags: s.flags -- ["paired_with_gall"], method: "pair"}

    cond do
      mate.resolution == :resolved and mate.gall_id == id ->
        %{settled | resolution: :new}

      mate.resolution == :new ->
        %{settled | resolution: :resolved, gall_id: id}

      mate.resolution == :resolved or "skipped" in mate.flags ->
        reason = "#{mate.ref}, its pair, was decided otherwise: the entry matches this Gall"

        %{
          s
          | flags: s.flags -- ["paired_with_gall"],
            detail: s.detail |> Map.delete("pair") |> Map.put("reason", reason)
        }

      true ->
        s
    end
  end

  defp settle_pair(statement, _mate), do: statement

  # -- the admin queue ---------------------------------------------------------

  @doc """
  The queue items the Gall statements call for, as
  `%{kind, statement_ref, subject, proposal, reason}`. The proposal holds
  `"candidate_ids"` (ranked), `"proposed"` (a firm match, or `"new"`),
  `"best"` (a match only to check), `"conflicts"` (the fields the proposed
  or best match conflicts on), `"comparisons"` (each candidate's
  `Gallformers.Import.GallComparison.to_proposal/1`, in rank order) and
  `"pair"`, each when present. Undescribed
  candidates are `:undescribed_gall` (with the best one, if any), other
  ambiguous matches `:ambiguous_match` (a pair's with the other Gall as
  `"pair"`), unresolved Galls `:unresolved_name` (`"proposed"` `"new"` when
  new is proposed). A Gall waiting on its Inducer or its Host, and the
  second of a pair, have none.
  """
  @spec queue_items([statement()]) :: [map()]
  def queue_items(statements) do
    for %{kind: :gall, resolution: resolution} = s <- statements,
        resolution in @open,
        not Enum.any?(@not_queued, &(&1 in s.flags)) do
      %{
        kind: queue_kind(s),
        statement_ref: s.ref,
        subject: Map.take(s.detail, ["name_as_written", "generation", "plant_part", "new"]),
        proposal:
          %{
            "candidate_ids" => s.candidate_ids,
            "proposed" => s.detail["proposed"],
            "best" => s.detail["best"],
            "conflicts" => s.detail["conflicts"],
            "comparisons" => s.detail["comparisons"],
            "pair" => s.detail["pair"]
          }
          |> Map.reject(fn {_k, v} -> is_nil(v) end),
        reason: s.detail["reason"]
      }
    end
  end

  defp queue_kind(%{resolution: :unresolved}), do: :unresolved_name
  defp queue_kind(%{method: "undescribed"}), do: :undescribed_gall
  defp queue_kind(_statement), do: :ambiguous_match
end
