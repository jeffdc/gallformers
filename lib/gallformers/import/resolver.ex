defmodule Gallformers.Import.Resolver do
  @moduledoc """
  Resolves a batch's taxon names to taxa (`9449` Task 12; producer guide
  background, *What Gallformers does on import* steps 1–3).

  Each declared taxon (`taxa[]`: `ref`, `name_as_written`, `rank`, maybe
  `name_reading`, `sensu`, `new`) is looked up with
  `Gallformers.Taxa.resolve_name/2` — accepted names and synonyms, through
  the normalized name — filtered by its rank, and by kingdom Plantae when the
  batch uses it as a Host. The names tried, in order, stopping at the first
  that matches anything:

    1. `name_as_written` (method `"exact"`, or `"synonym"` when it matched a
       synonym);
    2. a genus abbreviation expanded ("Q. lobata" → "Quercus lobata",
       method `"abbreviation"`) with every genus of that initial the batch,
       the package's taxonomy batch or the document names — genera printed
       in capitals ("QUERCUS PRINOS") included — that the tree holds;
    3. `name_reading`, the evident printed name where the text is damaged
       (method `"name_reading"`), and its abbreviation expanded;
    4. a 19th-century oak-gall name ("Cynips q. spongifica", "C.
       quercus-spongifica", "C.Q. INANIS") as the fused epithet
       *quercusspongifica* in any genus (method `"fused_epithet"`).

  No fuzzy matching: it joined different species.

  Outcomes (`Gallformers.Import.BatchStatement`): `:resolved` (one taxon),
  `:ambiguous` (several, in `candidate_ids`), `:new` (no match, and the
  Source — the taxon itself or the package's taxonomy batch — presents it as
  new), `:unresolved`.

  Where several taxa match and only one of them through its accepted name
  (the others through a synonym), that one is proposed (`detail["proposed"]`,
  queue triage rule J); it is still for a curator to confirm, since the
  tree's synonyms carry no `sensu`.

  ## Suggestions, never resolutions

  A name that matches nothing is not called new, nor left bare, while the
  tree holds it in another spelling, ending or genus
  (`Gallformers.Import.NameSuggestions`, rule G): it is `:ambiguous` with
  those taxa as candidates (one proposed), so a curator decides and an old
  Source's name is not created again. An unresolved Host gets suggestions
  from the tree and WCVP (`Gallformers.Import.HostSuggestions`, rule F) in
  its `detail` and queue item; it stays unresolved.

  ## Common names

  A Host the Source names only by a common name (`"common_name": true`,
  "the black oak") never resolves on its own, even when its words are a
  name the tree holds: it is `:unresolved`, flagged in its detail
  (`"common_name"`), with the plants of that Gallformers common name as
  suggestions (`Gallformers.Import.HostSuggestions.suggest_common_name/1`),
  never proposed, and the genus the name points to (`"genus"`) and that
  genus's sections (`"sections"`), even with no plant of that name ("an
  unknown oak"). Its queue item is an `:unresolved_host`.

  ## No silent merges

  A name the tree holds as a synonym while this Source treats it as valid —
  the taxonomy batch gives it a `name`, `placement` or `common_name` act,
  makes it the accepted name of a synonymy, a parent, or a split's taxon or
  daughter — is not resolved to the accepted taxon: it is `:unresolved`,
  flagged `"synonym_held_valid"`, with that taxon as its candidate, in both
  batches (`9449` §3: gall names never resolve through a disagreement
  silently). In a gall batch, when the Source describes the name as new and
  the synonymy stays within a family, the taxon is proposed (rule H: the
  tree has since sunk the original name into another species).

  Except for an original description (rule C): when the Source presents the
  name as new and the tree holds that same combination as a synonym of a
  taxon with the same epithet (in any gender), in the same family, the
  synonym is the original combination of the tree's taxon — a later
  recombination cannot disagree with it. It resolves to that taxon, flagged
  `"original_combination"`, so its acts are recorded as history. A
  synonymy across families (*Diastrophus smilacis* held for the eulophid
  *Aprostocetus smilax*) is not trusted.

  ## The queue

  `queue_items/1` turns the statements that need an admin into queue items:
  unresolved Hosts (`d585`; they hold the gall batch), other unresolved
  names, ambiguous matches, and held-valid synonyms. A genus the tree does
  not hold that the taxonomy batch uses only as the parent of taxa the tree
  holds elsewhere is flagged `"parent_only"` and not queued (rule D): its
  placements cannot apply, and its name stays as written.
  """

  alias Gallformers.Import.HostSuggestions
  alias Gallformers.Import.NameSuggestions
  alias Gallformers.Import.NameVariants
  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer
  alias Gallformers.Taxa.Taxon

  @typedoc """
  What resolution needs besides the batch. `:wcvp` is the WCVP lookup
  (`Gallformers.Wcvp.LookupBehaviour`) for Host suggestions.
  """
  @type context :: %{
          genera: [String.t()],
          new_names: %{String.t() => String.t()},
          held_valid: MapSet.t(String.t()),
          host_refs: MapSet.t(String.t()),
          batch_type: String.t() | nil,
          wcvp: module()
        }

  @typedoc "A statement's resolution, as `Gallformers.Import.BatchStatement` takes it."
  @type statement :: %{
          kind: :taxon,
          ref: String.t(),
          resolution: :resolved | :ambiguous | :unresolved | :new,
          method: String.t() | nil,
          taxon_id: integer() | nil,
          candidate_ids: [integer()],
          flags: [String.t()],
          detail: map()
        }

  @abbreviation ~r/\A([A-Z])\.\s*(.+)\z/
  # "Cynips q. spongifica", "C. quercus-spongifica", "C.Q. INANIS"
  @fused ~r/\A(?:\S+\s+(?:q\.|quercus[-\s]?)|[A-Z]\.\s*Q\.)\s*([a-z][a-z-]+)\z/i
  @capitalized ~r/\b[A-Z][A-Za-z]+\b/u
  @abbreviated ~r/\A[A-Z]\./
  @plantae "Plantae"

  # The taxon refs a taxonomy act uses as names the Source treats as valid.
  @valid_roles %{
    "name" => ["taxon"],
    "placement" => ["taxon", "parent"],
    "synonymy" => ["accepted"],
    "split" => ["taxon", "into"],
    "common_name" => ["taxon"]
  }

  @doc """
  The context for resolving `batch` (decoded): `:taxonomy` is the package's
  taxonomy batch (decoded, or nil), `:document_texts` the document's item
  texts (for the genera it names), `:wcvp` the WCVP lookup module (default:
  the configured `:wcvp_lookup`).
  """
  @spec context(map(), keyword()) :: context()
  def context(batch, opts \\ []) do
    taxonomy = opts[:taxonomy]
    texts = Keyword.get(opts, :document_texts, [])
    declared = taxa(batch) ++ taxa(taxonomy)

    %{
      genera: genera(declared, texts),
      new_names: new_names(taxonomy, batch),
      held_valid: held_valid(taxonomy),
      host_refs: host_refs(batch),
      batch_type: batch["batch_type"],
      wcvp:
        Keyword.get_lazy(opts, :wcvp, fn ->
          Application.get_env(:gallformers, :wcvp_lookup, Gallformers.Wcvp.Lookup)
        end)
    }
  end

  defp taxa(%{"taxa" => taxa}) when is_list(taxa), do: taxa
  defp taxa(_batch), do: []

  # Genera written in full in the batches or the document, that the tree holds.
  defp genera(declared, texts) do
    from_batches =
      for t <- declared,
          t["common_name"] != true,
          name = t["name_reading"] || t["name_as_written"],
          is_binary(name),
          not Regex.match?(@abbreviated, name),
          [first | _] <- [String.split(name)],
          do: first

    from_document = for text <- texts, [word] <- Regex.scan(@capitalized, text), do: word

    (from_batches ++ from_document)
    |> Enum.map(&String.capitalize/1)
    |> Enum.uniq()
    |> Taxa.genus_names()
    |> Enum.sort()
  end

  # Normalized names the Source presents as new, with the status as written.
  defp new_names(taxonomy, batch) do
    for t <- taxa(taxonomy) ++ taxa(batch),
        %{"status" => status} <- [t["new"]],
        into: %{},
        do: {normalize(t), status}
  end

  defp held_valid(nil), do: MapSet.new()

  defp held_valid(taxonomy) do
    names = Map.new(taxa(taxonomy), &{&1["ref"], normalize(&1)})

    for %{"kind" => kind, "stance" => "confirm"} = act <- List.wrap(taxonomy["acts"]),
        role <- Map.get(@valid_roles, kind, []),
        ref <- List.wrap(act[role]),
        name = names[ref],
        into: MapSet.new(),
        do: name
  end

  # Refs used as Hosts: identified_by.host and host_of subjects.
  defp host_refs(batch) do
    from_galls = for %{"identified_by" => %{"host" => ref}} <- List.wrap(batch["galls"]), do: ref

    from_facts =
      for %{"kind" => "relationship", "type" => "host_of", "subject" => ref} <-
            List.wrap(batch["facts"]),
          do: ref

    MapSet.new(from_galls ++ from_facts)
  end

  # -- resolving ---------------------------------------------------------------

  @doc "Resolves every declared taxon of `batch` (decoded), in the batch's order."
  @spec resolve_taxa(map(), context()) :: [statement()]
  def resolve_taxa(batch, context) do
    batch
    |> taxa()
    |> Enum.map(&resolve_taxon(&1, context))
    |> flag_parent_only(List.wrap(batch["acts"]))
  end

  defp resolve_taxon(t, context) do
    host? = MapSet.member?(context.host_refs, t["ref"])
    opts = [rank: t["rank"], kingdom: if(host?, do: @plantae), sensu: t["sensu"]]

    detail =
      %{
        "name_as_written" => t["name_as_written"],
        "name_reading" => t["name_reading"],
        "rank" => t["rank"],
        "sensu" => t["sensu"],
        "host" => host?
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    statement = %{
      kind: :taxon,
      ref: t["ref"],
      resolution: :unresolved,
      method: nil,
      taxon_id: nil,
      candidate_ids: [],
      flags: [],
      detail: detail
    }

    if t["common_name"] == true do
      common_name(statement)
    else
      t
      |> attempts(context)
      |> first_match(opts)
      |> outcome(statement, t, context, opts)
    end
  end

  @common_name "a common name: it never resolves on its own, so a curator decides which plant"

  # A Host the Source names only by a common name: never resolved, even
  # when its words are a name the tree holds; a Host gets the plants of
  # that common name as suggestions, never proposed.
  defp common_name(%{detail: detail} = statement) do
    statement = %{statement | detail: Map.put(detail, "common_name", true)}

    t = %{
      "name_as_written" => detail["name_as_written"],
      "name_reading" => detail["name_reading"]
    }

    case detail["host"] && HostSuggestions.suggest_common_name(t) do
      found when is_map(found) -> host_suggestions(statement, found)
      _ -> put_in(statement.detail["reason"], @common_name)
    end
  end

  # The names to try, in order, as {method, name, how}: how is :name or
  # :epithet.
  defp attempts(t, context) do
    written = t["name_as_written"]
    reading = t["name_reading"]

    [{"exact", written, :name}] ++
      expansions(written, context) ++
      if(reading,
        do: [{"name_reading", reading, :name}] ++ expansions(reading, context, "name_reading"),
        else: []
      ) ++
      fused(reading) ++ fused(written)
  end

  defp expansions(name, context, method \\ "abbreviation") do
    case Regex.run(@abbreviation, String.trim(name)) do
      [_, initial, rest] ->
        expanded = for g <- context.genera, String.starts_with?(g, initial), do: "#{g} #{rest}"
        if expanded == [], do: [], else: [{method, expanded, :names}]

      nil ->
        []
    end
  end

  defp fused(nil), do: []

  defp fused(name) do
    name = name |> NameVariants.spell_ligatures() |> String.split() |> Enum.join(" ")

    case Regex.run(@fused, name) do
      [_, epithet] -> [{"fused_epithet", "quercus" <> String.replace(epithet, "-", ""), :epithet}]
      nil -> []
    end
  end

  # The first attempt that matches anything: {method, tried name, result}.
  defp first_match(attempts, opts) do
    Enum.find_value(attempts, :none, fn attempt ->
      case try_attempt(attempt, opts) do
        {_tried, :none} -> nil
        {tried, result} -> {elem(attempt, 0), tried, result}
      end
    end)
  end

  defp try_attempt({_method, name, :name}, opts), do: {name, Taxa.resolve_name(name, opts)}

  defp try_attempt({_method, name, :epithet}, opts),
    do: {name, Taxa.resolve_epithet(name, Keyword.delete(opts, :rank))}

  # Several expansions: one taxon across them all, or ambiguous.
  defp try_attempt({_method, names, :names}, opts) do
    hits =
      for name <- names, result = Taxa.resolve_name(name, opts), result != :none do
        {name, result}
      end

    taxa =
      hits
      |> Enum.flat_map(fn
        {_name, {:ok, taxon}} -> [taxon]
        {_name, {:ambiguous, taxa}} -> taxa
      end)
      |> Enum.uniq_by(& &1.id)

    case {hits, taxa} do
      {[], _} -> {nil, :none}
      {[{name, _}], [taxon]} -> {name, {:ok, taxon}}
      {[{name, _} | _], [taxon]} -> {name, {:ok, taxon}}
      {_hits, taxa} -> {Enum.map_join(hits, ", ", &elem(&1, 0)), {:ambiguous, taxa}}
    end
  end

  @no_match "no taxon has this name or synonym"

  # A Host: new as the Source says, or unresolved with suggestions (rule F).
  defp outcome(:none, %{detail: %{"host" => true}} = statement, t, context, opts) do
    case new_status(t, context) do
      nil -> host_suggestions(statement, HostSuggestions.suggest(t, context, opts))
      status -> new(statement, status)
    end
  end

  # Another name: a proposal when the tree holds it in another spelling or
  # genus (rule G), else new as the Source says, or unresolved.
  defp outcome(:none, statement, t, context, opts) do
    status = new_status(t, context)

    case NameSuggestions.suggest(t, context, opts) do
      nil when is_binary(status) -> new(statement, status)
      nil -> put_in(statement.detail["reason"], @no_match)
      found -> suggested(statement, found, status)
    end
  end

  defp outcome({method, tried, {:ok, %Taxon{} = taxon}}, statement, t, context, _opts) do
    matched = taxon.matched_name
    detail = Map.merge(statement.detail, %{"tried" => tried, "matched" => matched.name})
    synonym? = matched.status == :synonym

    resolved = %{
      statement
      | resolution: :resolved,
        method: method(method, matched),
        taxon_id: taxon.id
    }

    cond do
      synonym? and original_combination?(t, context, tried, taxon) ->
        reason =
          "the original combination of #{Taxa.accepted_name(taxon)}: the Source describes " <>
            "#{matched.name} as new, and the tree holds it as a synonym with the same epithet"

        %{resolved | flags: ["original_combination"], detail: Map.put(detail, "reason", reason)}

      synonym? and MapSet.member?(context.held_valid, NameNormalizer.normalize(tried)) ->
        held_valid(statement, method(method, matched), detail, t, context, taxon)

      true ->
        %{resolved | detail: detail}
    end
  end

  defp outcome({method, tried, {:ambiguous, taxa}}, statement, _t, _context, _opts) do
    proposed = accepted_hit(taxa)

    reason =
      if proposed,
        do:
          "#{length(taxa)} taxa have this name; only #{Taxa.accepted_name(proposed)} " <>
            "has it as its accepted name, the others as a synonym",
        else: "#{length(taxa)} taxa have this name"

    %{
      statement
      | resolution: :ambiguous,
        method: method,
        candidate_ids: Enum.map(taxa, & &1.id),
        detail:
          Map.merge(statement.detail, %{
            "tried" => tried,
            "reason" => reason,
            "proposed" => proposed && proposed.id
          })
          |> drop_nil()
    }
  end

  defp new(statement, status),
    do: %{statement | resolution: :new, detail: Map.put(statement.detail, "new_status", status)}

  defp host_suggestions(statement, nil), do: put_in(statement.detail["reason"], @no_match)

  defp host_suggestions(statement, found) do
    %{
      statement
      | candidate_ids: found.candidate_ids,
        detail:
          Map.merge(statement.detail, %{
            "suggestions" => non_empty(found.suggestions),
            "proposed" => found.proposed,
            "reason" => found.reason,
            "genus" => found[:genus],
            "sections" => non_empty(found[:sections])
          })
          |> drop_nil()
    }
  end

  # A name the tree holds as a synonym, which this Source treats as valid.
  # In a gall batch, a name the Source describes as new, sunk by the tree
  # within its family, proposes the tree's taxon (rule H).
  defp held_valid(statement, method, detail, t, context, taxon) do
    reason =
      "the tree holds #{detail["matched"]} as a synonym of #{Taxa.accepted_name(taxon)}, " <>
        "but this Source treats it as valid"

    propose? =
      context.batch_type == "gall" and new_status(t, context) != nil and
        NameSuggestions.same_family?(NameVariants.genus(detail["matched"]), taxon)

    detail =
      if propose?,
        do:
          Map.merge(detail, %{
            "proposed" => taxon.id,
            "reason" =>
              reason <> "; the Source describes it as new, and the tree has since sunk it there"
          }),
        else: Map.put(detail, "reason", reason)

    %{
      statement
      | resolution: :unresolved,
        method: method,
        candidate_ids: [taxon.id],
        flags: ["synonym_held_valid"],
        detail: detail
    }
  end

  # Rule C: the Source describes the name as new, and the tree holds that
  # same combination as a synonym of a taxon with the same epithet, in the
  # same family.
  defp original_combination?(t, context, tried, %Taxon{matched_name: matched} = taxon) do
    synonym_epithet = NameVariants.epithet(matched.name)
    accepted_epithet = NameVariants.epithet(Taxa.accepted_name(taxon))

    new_status(t, context) != nil and
      NameNormalizer.normalize(tried) == matched.normalized_name and
      is_binary(synonym_epithet) and is_binary(accepted_epithet) and
      NameVariants.same_epithet?(synonym_epithet, accepted_epithet) and
      NameSuggestions.same_family?(NameVariants.genus(matched.name), taxon)
  end

  # Rule G: what the tree holds in another spelling or genus, as candidates.
  defp suggested(statement, found, status) do
    held =
      Enum.map_join(found.taxa, ", ", fn taxon ->
        accepted = Taxa.accepted_name(taxon)
        matched = taxon.matched_name.name
        if matched == accepted, do: accepted, else: "#{matched} (a synonym of #{accepted})"
      end)

    how =
      case found.method do
        "cynips_name" -> "with \"C. q. X\" read as Cynips X or Cynips quercus X"
        "spelling_variant" -> "in another spelling or ending"
        "epithet_in_family" -> "with this epithet in #{Enum.join(found.families, ", ")}"
      end

    lead =
      if status,
        do: "the Source presents it as new (#{status}), but",
        else: "no taxon has this name or synonym, but"

    proposed = if match?([_], found.taxa), do: hd(found.taxa), else: accepted_hit(found.taxa)

    %{
      statement
      | resolution: :ambiguous,
        method: found.method,
        candidate_ids: Enum.map(found.taxa, & &1.id),
        detail:
          Map.merge(statement.detail, %{
            "tried" => Enum.join(found.tried, ", "),
            "new_status" => status,
            "proposed" => proposed && proposed.id,
            "reason" => "#{lead} the tree holds #{held} (#{how}): a suggestion, not a match"
          })
          |> drop_nil()
    }
  end

  # Of several taxa, the only one matched through its accepted name (rule J).
  defp accepted_hit(taxa) do
    case Enum.filter(taxa, &(&1.matched_name.status == :accepted)) do
      [taxon] when length(taxa) > 1 -> taxon
      _ -> nil
    end
  end

  defp drop_nil(map), do: Map.reject(map, fn {_k, v} -> is_nil(v) end)

  defp non_empty([]), do: nil
  defp non_empty(list), do: list

  defp method("exact", %{status: :synonym}), do: "synonym"
  defp method(method, _matched), do: method

  defp new_status(t, context) do
    case t["new"] do
      %{"status" => status} -> status
      _ -> Map.get(context.new_names, normalize(t))
    end
  end

  defp normalize(t), do: NameNormalizer.normalize(t["name_reading"] || t["name_as_written"] || "")

  # -- the admin queue ---------------------------------------------------------

  @doc """
  The queue items the statements call for, as
  `%{kind, statement_ref, subject, proposal, reason}`: an unresolved Host
  is `:unresolved_host` (it holds the gall batch, `d585`), another
  unresolved name `:unresolved_name`, an ambiguous match `:ambiguous_match`
  (with its candidates), a held-valid synonym `:taxonomy_disagreement`.
  Resolved and new statements need nothing, nor a genus used only as a
  parent (`"parent_only"`). The proposal is `"candidate_ids"`, with
  `"proposed"` (the one-click answer) and, for a Host, `"suggestions"`
  (`Gallformers.Import.HostSuggestions`) when there are any; for a Host
  named by a common name, also its `"genus"` and the genus's `"sections"`
  when found.
  """
  @spec queue_items([statement()]) :: [map()]
  def queue_items(statements) do
    for %{kind: :taxon, resolution: resolution, flags: flags} = s <- statements,
        resolution in [:unresolved, :ambiguous],
        "parent_only" not in flags do
      %{
        kind: queue_kind(s),
        statement_ref: s.ref,
        subject:
          Map.take(s.detail, [
            "name_as_written",
            "name_reading",
            "rank",
            "sensu",
            "host",
            "common_name"
          ]),
        proposal:
          %{
            "candidate_ids" => s.candidate_ids,
            "proposed" => s.detail["proposed"],
            "suggestions" => s.detail["suggestions"],
            "genus" => s.detail["genus"],
            "sections" => s.detail["sections"]
          }
          |> drop_nil(),
        reason: s.detail["reason"]
      }
    end
  end

  # -- a genus used only as a parent (rule D) ----------------------------------

  # The taxon refs an act uses, by role.
  @act_roles ["taxon", "parent", "name", "accepted", "into"]

  # An unresolved name the taxonomy batch's `acts` use only as the parent of
  # placements, each of whose taxa the tree holds (resolved, or with
  # candidates): those placements cannot apply, and nothing else needs it.
  # A placed taxon that is new keeps it an item: it may be a new genus.
  defp flag_parent_only(statements, []), do: statements

  defp flag_parent_only(statements, acts) do
    by_ref = Map.new(statements, &{&1.ref, &1})

    Enum.map(statements, fn s ->
      if parent_only?(s, acts, by_ref) do
        reason =
          "used only as the parent of taxa the tree holds elsewhere: its placements " <>
            "are not applied, and the name stays as written"

        %{s | flags: s.flags ++ ["parent_only"], detail: Map.put(s.detail, "reason", reason)}
      else
        s
      end
    end)
  end

  defp parent_only?(%{resolution: :unresolved, candidate_ids: [], flags: []} = s, acts, by_ref) do
    uses = for act <- acts, role <- @act_roles, s.ref in List.wrap(act[role]), do: {act, role}
    placed = for {%{"kind" => "placement"} = act, "parent"} <- uses, do: by_ref[act["taxon"]]

    uses != [] and length(placed) == length(uses) and Enum.all?(placed, &held_elsewhere?/1)
  end

  defp parent_only?(_statement, _acts, _by_ref), do: false

  defp held_elsewhere?(%{resolution: :resolved}), do: true
  defp held_elsewhere?(%{resolution: :new}), do: false
  defp held_elsewhere?(%{candidate_ids: [_ | _]}), do: true
  defp held_elsewhere?(_statement), do: false

  defp queue_kind(%{flags: flags} = s) do
    cond do
      "synonym_held_valid" in flags -> :taxonomy_disagreement
      s.resolution == :ambiguous -> :ambiguous_match
      s.detail["host"] -> :unresolved_host
      true -> :unresolved_name
    end
  end

  @doc """
  Whether the statements hold the gall batch: a Host name that is not
  resolved (or new) stops it until an admin resolves it (`d585`).
  """
  @spec holds_gall_batch?([statement()]) :: boolean()
  def holds_gall_batch?(statements) do
    Enum.any?(statements, fn s ->
      s.kind == :taxon and s.detail["host"] == true and s.resolution in [:unresolved, :ambiguous]
    end)
  end
end
