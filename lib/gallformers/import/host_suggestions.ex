defmodule Gallformers.Import.HostSuggestions do
  @moduledoc """
  Suggestions for a Host name the tree does not hold (queue triage rule F),
  for the `:unresolved_host` item. Nothing is applied: the Host stays
  unresolved and holds the gall batch until a curator decides (`d585`).
  WCVP names are often homonyms (*Mulgedium acuminatum* twice, *Rubus
  villosus* five times), so every record found is shown, with its authors
  and status, the doubtful ones (illegitimate, invalid, misapplied,
  unplaced) last.

  Looked for in order, each name tried as written, as read, and with its
  genus abbreviation expanded:

    1. the tree, the last epithet in another ending or spelling
       (`Gallformers.Import.NameVariants`: rubrum/rubra, niger/nigra,
       ii/i), method `"spelling_variant"`;
    2. WCVP, the name itself, also with the hybrid sign ("Rubus x
       loganobaccus" is *Rubus × loganobaccus*): `"exact"` for an accepted
       record, `"synonym"` otherwise;
    3. if the tree holds none of those, WCVP with the epithet's variants
       (`"spelling_variant"`);
    4. if steps 1–3 found nothing at all, WCVP names of the genus within an
       edit distance of 2 (1 when an epithet has five letters or fewer),
       sharing the epithet's first letter (`"edit_distance"`). The whole
       name is compared, a variety's epithet included ("Quercus chrysolepis
       var. vaccinifolia" is WCVP's var. *vacciniifolia*, a synonym of
       *Q. vacciniifolia*), and a record must be in the Source's genus, as
       must the plant it is a synonym of (*Quercus prinodes*, near
       "Quercus prinos", is *Castanopsis indica*). This is fuzzy matching,
       so it is only ever a suggestion;
    5. if the tree holds none of steps 1–3, for a variety or subspecies,
       its species in the tree (`"species_of_infraspecies"`: *Populus
       nigra* var. *italica* is under *P. nigra*), then the infraspecific
       epithet as a species of the genus (`"infraspecies_as_species"`:
       *Q. prinos* var. *bicolor* may be *Q. bicolor*; weak). These come
       after the near spellings: the species may be another plant.

  Each suggestion is a map: `"source"` (`"tree"` or `"wcvp"`), `"match"`,
  `"name"`, and for WCVP `"wcvp_id"`, `"authors"`, `"wcvp_status"` and,
  for a record that is not itself accepted, its `"accepted"` record. Its
  `"taxon_id"` is the tree's taxon for it (nil when the tree has none) and
  its `"action"` what deciding it would take: `"add_synonym"` (the name as
  written, `"synonym"`, becomes a synonym of that taxon) or
  `"add_from_wcvp"` (add the accepted record as a new plant).

  The proposed taxon (one click) is the tree's taxon of the first
  suggestion found by steps 1–3 (not a variety's species, the weak or
  fuzzy ones, nor a doubtful WCVP record), when all of that step's
  suggestions agree on it. A variety's species (step 5) comes after any
  WCVP record found for the variety itself, and is only suggested: WCVP
  may sink the variety into another plant (*Rubus ursinus* var.
  *loganobaccus* is *Rubus × loganobaccus*, the loganberry).

  Hybrid formulas ("R. ursinus x idaeus" for *Rubus × loganobaccus*) are
  not looked up: `Gallformers.Wcvp.LookupBehaviour` does not read WCVP's
  `hybrid_formula`.
  """

  alias Gallformers.Import.NameVariants
  alias Gallformers.Ranges.Wcvp, as: WcvpLinks
  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer

  @type suggestions :: %{
          suggestions: [map()],
          candidate_ids: [integer()],
          proposed: integer() | nil,
          reason: String.t()
        }

  @type common_name_suggestions :: %{
          suggestions: [map()],
          candidate_ids: [integer()],
          proposed: nil,
          reason: String.t(),
          genus: map() | nil,
          sections: [map()]
        }

  @plantae "Plantae"
  @abbreviation ~r/\A([A-Z])\.\s*(.+)\z/
  @markers ~w(var. var subsp. subsp ssp. ssp f. forma)
  @doubtful ~w(Illegitimate Invalid Misapplied Unplaced)
  # A variety's species is only ever a suggestion: the variety may be sunk
  # into another plant (Rubus ursinus var. loganobaccus is the loganberry,
  # Rubus × loganobaccus, not R. ursinus).
  @proposable ~w(spelling_variant exact synonym)
  @search_limit 50
  @genus_limit 5000
  @max_fuzzy 5

  @doc """
  The suggestions for Host `t` (a declared taxon), or nil when nothing is
  found. `context` is the resolver's (`Gallformers.Import.Resolver.context/2`:
  `:genera` for abbreviations, `:wcvp` the WCVP lookup module), `opts` the
  resolution options (`Gallformers.Taxa.resolve_name/2`).
  """
  @spec suggest(map(), map(), keyword()) :: suggestions() | nil
  def suggest(t, context, opts) do
    names = names(t, context)
    wcvp = context.wcvp

    found =
      (tree_variants(names, opts) ++ wcvp_names(names, wcvp, "exact"))
      |> unless_tree(&wcvp_variants(names, wcvp, &1))
      |> unless_tree(&(&1 ++ near_unless_found(&1, names, wcvp) ++ infraspecific(names)))
      |> Enum.uniq_by(&(&1["wcvp_id"] || {:tree, &1["taxon_id"]}))

    if found != [], do: result(found)
  end

  @doc """
  The suggestions for a Host the Source names only by a common name
  (`"common_name": true`, "the black oak"), or nil when none: the plants
  whose Gallformers common name it is (`Gallformers.Taxa.find_by_common_name/2`,
  as read and as written), each with match `"common_name"`, the
  `"common_name"` that matched and the plant's `"genus"` (`%{"taxon_id",
  "name"}`, when it has one). Nothing is proposed: a common name may mean
  another plant to this Source, so a curator always decides. No `"action"`:
  a common name is never added as a synonym.

  Also the `genus` the common name points to (`%{"taxon_id", "name"}`), even
  when no plant has that common name ("an unknown oak"): the genus every
  suggestion is in; else the genus its head word (its last word, "tree",
  "shrub" or "bush" left out) names, as a genus's common name, singular or
  plural ("oak" is Quercus's "Oaks"), or as a genus's name; one genus only,
  else none. And that genus's `sections` from the tree (`%{"taxon_id",
  "name", "common_name"}`, the first common name the tree holds for it, by
  name): an unnamed oak is usually a section's, not the genus's (`d213`).
  Nil when there is neither a suggestion nor a genus.
  """
  @spec suggest_common_name(map()) :: common_name_suggestions() | nil
  def suggest_common_name(t) do
    names =
      [t["name_reading"], t["name_as_written"]]
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    found =
      names
      |> Enum.flat_map(&Taxa.find_by_common_name(&1, kingdom: @plantae))
      |> Enum.uniq_by(& &1.taxon_id)
      |> Enum.map(&common_name_suggestion/1)

    genus = suggestions_genus(found) || head_word_genus(names)

    if found != [] or genus != nil do
      sections = if genus, do: sections(genus["taxon_id"]), else: []

      %{
        suggestions: found,
        candidate_ids: Enum.map(found, & &1["taxon_id"]),
        proposed: nil,
        reason: common_name_reason(found, genus, sections),
        genus: genus,
        sections: sections
      }
    end
  end

  defp common_name_reason(found, genus, sections) do
    plants =
      case found do
        [] ->
          "no Gallformers plant has this common name"

        _ ->
          listed = Enum.map_join(found, "; ", &"#{&1["name"]} (“#{&1["common_name"]}”)")
          "Gallformers' plants of this common name (#{length(found)}): #{listed}"
      end

    in_genus =
      case {genus, sections} do
        {nil, _} -> ""
        {g, []} -> "; its genus #{g["name"]}"
        {g, s} -> "; its genus #{g["name"]}, sections #{Enum.map_join(s, ", ", & &1["name"])}"
      end

    "a common name, so a curator decides which plant; " <> plants <> in_genus
  end

  # The genus every suggestion is in, when they share one.
  defp suggestions_genus(found) do
    case found |> Enum.map(& &1["genus"]) |> Enum.uniq() do
      [%{"taxon_id" => id} = genus] when is_integer(id) -> genus
      _ -> nil
    end
  end

  @not_head ~w(tree trees shrub shrubs bush bushes)

  # The one genus a common name's head word names: as a genus's common
  # name ("oak", "oaks": Quercus's "Oaks") or as a genus's name.
  defp head_word_genus(names) do
    names
    |> Enum.flat_map(&head_word/1)
    |> Enum.uniq()
    |> Enum.flat_map(fn word ->
      by_common =
        for form <- word_forms(word),
            hit <- Taxa.find_by_common_name(form, kingdom: @plantae),
            hit.rank == :genus,
            do: %{"taxon_id" => hit.taxon_id, "name" => hit.name}

      by_name =
        for taxon <- taxa(Taxa.resolve_name(word, rank: :genus, kingdom: @plantae)),
            do: %{"taxon_id" => taxon.id, "name" => Taxa.accepted_name(taxon)}

      by_common ++ by_name
    end)
    |> Enum.uniq_by(& &1["taxon_id"])
    |> case do
      [genus] -> genus
      _ -> nil
    end
  end

  defp head_word(name) do
    name
    |> String.downcase()
    |> String.split(~r/[^a-z]+/, trim: true)
    |> Enum.reject(&(&1 in @not_head))
    |> List.last()
    |> List.wrap()
  end

  # The word, its plurals and its singulars ("oak", "oaks", "beeches").
  defp word_forms(word) do
    singulars =
      for suffix <- ["es", "s"],
          String.ends_with?(word, suffix),
          stem = String.replace_suffix(word, suffix, ""),
          stem != "",
          do: stem

    Enum.uniq([word, word <> "s", word <> "es" | singulars])
  end

  # A genus's sections, by name, each with its first common name.
  defp sections(genus_id) do
    for child <- Taxa.children_with_ranks(genus_id), child.rank == :section do
      %{
        "taxon_id" => child.taxon_id,
        "name" => child.name,
        "common_name" => List.first(child.common_names)
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)
    end
  end

  defp common_name_suggestion(hit) do
    genus =
      case Enum.find(Taxa.lineage(hit.taxon_id), &(&1.rank == :genus)) do
        nil -> nil
        g -> %{"taxon_id" => g.taxon_id, "name" => g.name}
      end

    %{
      "source" => "tree",
      "match" => "common_name",
      "name" => hit.name,
      "common_name" => hit.common_name,
      "taxon_id" => hit.taxon_id,
      "genus" => genus
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  # The near spellings when nothing was found by name or variant: before a
  # variety's species, which may be another plant.
  defp near_unless_found([], names, wcvp), do: near(names, wcvp)
  defp near_unless_found(_found, _names, _wcvp), do: []

  defp unless_tree(found, fun),
    do: if(Enum.any?(found, & &1["taxon_id"]), do: found, else: fun.(found))

  defp result(found) do
    %{
      suggestions: found,
      candidate_ids: found |> Enum.map(& &1["taxon_id"]) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
      proposed: proposed(found),
      reason: reason(found)
    }
  end

  defp proposed(found) do
    case Enum.filter(found, &proposable?/1) do
      [first | _] = proposable ->
        proposable
        |> Enum.filter(&(&1["match"] == first["match"]))
        |> Enum.map(& &1["taxon_id"])
        |> Enum.uniq()
        |> case do
          [id] -> id
          _ -> nil
        end

      [] ->
        nil
    end
  end

  defp proposable?(s),
    do: s["taxon_id"] != nil and s["match"] in @proposable and s["wcvp_status"] not in @doubtful

  defp reason(found) do
    listed = found |> Enum.take(3) |> Enum.map_join("; ", &describe/1)
    more = if length(found) > 3, do: " (and #{length(found) - 3} more)", else: ""
    "no plant has this name or synonym; suggested (#{length(found)}): #{listed}#{more}"
  end

  defp describe(%{"source" => "tree"} = s), do: "#{s["name"]} in the tree (#{s["match"]})"

  defp describe(%{"source" => "wcvp"} = s) do
    accepted =
      case s["accepted"] do
        %{"name" => name, "authors" => authors} -> ", accepted #{name} #{authors}"
        _ -> ""
      end

    in_tree = if s["taxon_id"], do: ", in the tree", else: ", not in the tree"

    "#{s["name"]} #{s["authors"]} (WCVP #{s["wcvp_status"]}, #{s["match"]}#{accepted}#{in_tree})"
  end

  # -- the names tried ---------------------------------------------------------

  # The name as read and as written, with a genus abbreviation expanded;
  # abbreviated forms left out.
  defp names(t, context) do
    [t["name_reading"], t["name_as_written"]]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&(&1 |> String.split() |> Enum.join(" ")))
    |> Enum.flat_map(&expand(&1, context.genera))
    |> Enum.uniq_by(&NameNormalizer.normalize/1)
  end

  defp expand(name, genera) do
    case Regex.run(@abbreviation, name) do
      [_, initial, rest] -> for g <- genera, String.starts_with?(g, initial), do: "#{g} #{rest}"
      nil -> [name]
    end
  end

  # {words before the last, the last}, for a name of two words or more.
  defp split_last(name) do
    case String.split(name) do
      [_, _ | _] = words ->
        {init, [last]} = Enum.split(words, -1)
        {Enum.join(init, " "), last}

      _ ->
        nil
    end
  end

  defp variant_names(names) do
    for name <- names,
        {prefix, last} <- List.wrap(split_last(name)),
        v <- NameVariants.variants(last),
        do: {name, "#{prefix} #{v}"}
  end

  # -- the tree ----------------------------------------------------------------

  defp tree_variants(names, opts) do
    for {written, name} <- variant_names(names),
        taxon <- taxa(Taxa.resolve_name(name, opts)),
        do: tree_suggestion(taxon, "spelling_variant", written)
  end

  defp infraspecific(names) do
    for name <- names,
        {species, infra} <- List.wrap(infraspecies(name)),
        {match, lookup} <- [
          {"species_of_infraspecies", species},
          {"infraspecies_as_species", infra}
        ],
        taxon <- taxa(Taxa.resolve_name(lookup, kingdom: @plantae)),
        do: tree_suggestion(taxon, match, name)
  end

  # "Genus species var. infra" as {"Genus species", "Genus infra"}.
  defp infraspecies(name) do
    case String.split(name) do
      [genus, species, marker, infra | _] ->
        if String.downcase(marker) in @markers,
          do: {"#{genus} #{species}", "#{genus} #{infra}"}

      _ ->
        nil
    end
  end

  defp tree_suggestion(taxon, match, written) do
    %{
      "source" => "tree",
      "match" => match,
      "name" => taxon.matched_name.name,
      "taxon_id" => taxon.id,
      "action" => "add_synonym",
      "synonym" => written
    }
  end

  defp taxa({:ok, taxon}), do: [taxon]
  defp taxa({:ambiguous, taxa}), do: taxa
  defp taxa(:none), do: []

  # -- WCVP --------------------------------------------------------------------

  defp wcvp_names(names, wcvp, match) do
    for name <- names,
        query <- Enum.uniq([name | hybrid(name)]),
        record <- exact(wcvp, query),
        do: wcvp_suggestion(wcvp, record, match, name)
  end

  defp wcvp_variants(names, wcvp, found) do
    variants =
      for {written, name} <- variant_names(names),
          query <- Enum.uniq([name | hybrid(name)]),
          record <- exact(wcvp, query),
          do: wcvp_suggestion(wcvp, record, "spelling_variant", written)

    found ++ variants
  end

  # "Genus x epithet" or "Genus epithet" as "Genus × epithet".
  defp hybrid(name) do
    case String.split(name) do
      [genus | rest] when rest != [] ->
        ["#{genus} × #{rest |> Enum.reject(&(&1 in ["x", "×"])) |> Enum.join(" ")}"]

      _ ->
        []
    end
  end

  # The WCVP records named `query` (any status), the doubtful last.
  defp exact(wcvp, query) do
    wanted = NameNormalizer.normalize(query)

    query
    |> wcvp.search(include_synonyms: true, limit: @search_limit)
    |> Enum.filter(&(NameNormalizer.normalize(&1.taxon_name) == wanted))
    |> Enum.sort_by(&(&1.taxon_status in @doubtful))
  end

  # WCVP names of the genus near the name: never more than a suggestion.
  defp near(names, wcvp) do
    names
    |> Enum.flat_map(&near_name(&1, wcvp))
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.uniq_by(&elem(&1, 1).plant_name_id)
    |> Enum.take(@max_fuzzy)
    |> Enum.map(fn {_distance, record, name} ->
      wcvp_suggestion(wcvp, record, "edit_distance", name)
    end)
  end

  # The whole name is compared, a variety's epithet included, with the
  # names of the same number of words (a variety with WCVP's varieties and
  # subspecies of the species). Its epithets limit the distance: 1 when one
  # has five letters or fewer, else 2. A record, and the plant it is a
  # synonym of, must be in the Source's genus: Quercus prinodes is near
  # "Quercus prinos" but is Castanopsis indica.
  defp near_name(name, wcvp) do
    case String.split(name) do
      [genus, epithet | rest] = words ->
        wanted = NameNormalizer.normalize(name)

        shortest =
          [epithet | rest] |> epithets() |> Enum.map(&String.length/1) |> Enum.min(fn -> 0 end)

        max = if shortest <= 5, do: 1, else: 2

        for record <-
              wcvp.search("#{genus} #{String.first(epithet)}",
                include_synonyms: true,
                limit: @genus_limit
              ),
            length(String.split(record.taxon_name)) == length(words),
            distance =
              NameVariants.edit_distance(wanted, NameNormalizer.normalize(record.taxon_name)),
            distance in 1..max//1,
            in_genus?(record, genus),
            in_genus?(accepted(wcvp, record), genus),
            do: {distance, record, name}

      _ ->
        []
    end
  end

  defp epithets(words), do: Enum.reject(words, &(String.downcase(&1) in ["x", "×" | @markers]))

  # A record WCVP names nothing for (nil) is checked by the record itself.
  defp in_genus?(nil, _genus), do: true

  defp in_genus?(record, genus) do
    record_genus = record.genus || record.taxon_name |> String.split() |> List.first()
    String.downcase(record_genus || "") == String.downcase(genus)
  end

  # WCVP records are `Gallformers.Wcvp.WcvpName`s from the lookup, read as
  # maps (Import's boundary does not reach Gallformers.Wcvp).
  defp wcvp_suggestion(wcvp, record, match, written) do
    accepted = accepted(wcvp, record)
    taxon_id = tree_taxon(accepted)
    match = if match == "exact" and accepted != record, do: "synonym", else: match

    %{
      "source" => "wcvp",
      "match" => match,
      "name" => record.taxon_name,
      "authors" => record.taxon_authors,
      "wcvp_id" => record.plant_name_id,
      "wcvp_status" => record.taxon_status,
      "taxon_id" => taxon_id,
      "action" => action(taxon_id, accepted),
      "synonym" => if(taxon_id, do: written)
    }
    |> put_accepted(record, accepted)
    |> Map.reject(fn {key, value} -> is_nil(value) and key != "taxon_id" end)
  end

  # A plant WCVP doesn't accept (an unplaced name) can't be added from it.
  defp action(taxon_id, _accepted) when is_integer(taxon_id), do: "add_synonym"
  defp action(nil, accepted), do: if(accepted?(accepted), do: "add_from_wcvp")

  defp put_accepted(suggestion, record, accepted) when accepted in [nil, record], do: suggestion

  defp put_accepted(suggestion, _record, accepted) do
    Map.put(suggestion, "accepted", %{
      "name" => accepted.taxon_name,
      "authors" => accepted.taxon_authors,
      "wcvp_id" => accepted.plant_name_id
    })
  end

  # The record `record` points to: itself when accepted (or when WCVP names
  # nothing else), else the record WCVP names, accepted or not.
  defp accepted(_wcvp, %{accepted_plant_name_id: id} = record) when id in [nil, ""], do: record

  defp accepted(wcvp, record) do
    if accepted?(record), do: record, else: wcvp.get_accepted_name(record.plant_name_id)
  end

  defp accepted?(%{taxon_status: "Accepted"}), do: true
  defp accepted?(%{plant_name_id: id, accepted_plant_name_id: id}), do: true
  defp accepted?(_record), do: false

  # The tree's plant for a WCVP record: linked to it, else by its name.
  defp tree_taxon(nil), do: nil

  defp tree_taxon(record) do
    case WcvpLinks.linked_taxon_ids(record.plant_name_id) do
      [id | _] ->
        id

      [] ->
        case Taxa.resolve_name(record.taxon_name, kingdom: @plantae) do
          {:ok, taxon} -> taxon.id
          _ -> nil
        end
    end
  end
end
