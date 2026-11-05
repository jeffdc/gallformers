defmodule Gallformers.Import.NameSuggestions do
  @moduledoc """
  Taxa to suggest for a name that resolves to nothing (queue triage rule
  G): before a name is called new, or left unresolved, the tree is asked
  for it in other spellings. A hit is a proposal for a curator, never a
  resolution (`docs/import/producer-guide-background.md`, *What
  Gallformers does on import*: fuzzy matching may only suggest). Without
  it, an old Source's name the tree holds in another genus or spelling
  would be created again as a new taxon.

  Tried in order, stopping at the first that finds anything:

    1. For a 19th-century oak-gall name ("C. q. aciculata", "Cynips q.
       nigræ"): "Cynips X" and "Cynips quercus X" (method `"cynips_name"`),
       then the fused epithet *quercusX* in another ending, in any genus
       (`"spelling_variant"`).
    2. Otherwise the name with its last epithet in another ending or
       spelling (`Gallformers.Import.NameVariants`), in the genus as
       written or, for "D. vesicula", each genus of that initial the batch
       or document names (`"spelling_variant"`).
    3. The epithet alone, in any spelling, within the family of the genus
       as written ("ANDRICUS DASYDACTYLI" is *Heteroecus dasydactyli*,
       method `"epithet_in_family"`). A genus the tree does not hold takes
       its family from the tree's other names in it (`genus_families/2`);
       with no family, this step is skipped.

  Also the family checks for rules C and H (`same_family?/2`).
  """

  alias Gallformers.Import.NameVariants
  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon

  @typedoc "Suggested taxa: how they were found, the names that found them, the family searched."
  @type suggestion :: %{
          method: String.t(),
          tried: [String.t()],
          taxa: [Taxon.t()],
          families: [String.t()]
        }

  @fused ~r/\A(?:\S+\s+(?:q\.|quercus[-\s]?)|[A-Z]\.\s*Q\.)\s*([a-z][a-z-]+)\z/i
  @abbreviation ~r/\A([A-Z])\.\s*(.+)\z/

  @doc """
  The taxa to suggest for declared taxon `t`, or nil. `context` is the
  resolver's (`Gallformers.Import.Resolver.context/2`, for the genera an
  abbreviation expands to), `opts` the resolution options
  (`Gallformers.Taxa.resolve_name/2`).
  """
  @spec suggest(map(), map(), keyword()) :: suggestion() | nil
  def suggest(t, context, opts) do
    [t["name_reading"], t["name_as_written"]]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&clean/1)
    |> Enum.uniq()
    |> Enum.find_value(fn name ->
      name |> stages(context) |> Enum.find_value(&run(&1, opts))
    end)
  end

  defp clean(name), do: name |> NameVariants.spell_ligatures() |> String.split() |> Enum.join(" ")

  # The steps for `name`, as {method, how, names}.
  defp stages(name, context) do
    cond do
      match = Regex.run(@fused, name) ->
        x = match |> List.last() |> String.downcase() |> String.replace("-", "")
        xs = [x | NameVariants.variants(x)]

        [
          {"cynips_name", :names,
           for(v <- xs, n <- ["Cynips #{v}", "Cynips quercus #{v}"], do: n)},
          {"spelling_variant", :epithets, for(v <- tl(xs), do: "quercus" <> v)},
          {"epithet_in_family", {:family, ["Cynips"]}, xs}
        ]

      match = Regex.run(@abbreviation, name) ->
        [_, initial, rest] = match
        genera = for g <- context.genera, String.starts_with?(g, initial), do: g
        variant_stages(genera, String.split(rest))

      true ->
        case String.split(name) do
          [genus | [_ | _] = rest] -> variant_stages([genus], rest)
          _ -> []
        end
    end
  end

  # The name in `genera` with `rest` its words after the genus: the last
  # word's variants; for a binomial, the epithet within the family too.
  defp variant_stages([], _rest), do: []

  defp variant_stages(genera, rest) do
    {init, [last]} = Enum.split(rest, -1)
    epithet = NameNormalizer.normalize(last)
    variants = NameVariants.variants(epithet)
    prefixes = for g <- genera, do: Enum.join([g | init], " ")

    [{"spelling_variant", :names, for(p <- prefixes, v <- variants, do: "#{p} #{v}")}] ++
      if(init == [],
        do: [{"epithet_in_family", {:family, genera}, [epithet | variants]}],
        else: []
      )
  end

  defp run({_method, _how, []}, _opts), do: nil

  defp run({method, :names, names}, opts),
    do: found(method, names, &taxa(Taxa.resolve_name(&1, opts)), [])

  defp run({method, :epithets, epithets}, opts) do
    opts = Keyword.delete(opts, :rank)
    found(method, epithets, &taxa(Taxa.resolve_epithet(&1, opts)), [])
  end

  defp run({method, {:family, genera}, epithets}, opts) do
    families = genus_families(genera, opts[:kingdom])

    if map_size(families) > 0,
      do: found(method, epithets, &in_family(&1, families, opts), Map.values(families))
  end

  defp in_family(epithet, families, opts) do
    epithet |> Taxa.resolve_epithet(opts) |> taxa() |> Enum.filter(&in_families?(&1, families))
  end

  # The taxa each of `names` finds (`lookup`), as a suggestion, or nil.
  defp found(method, names, lookup, families) do
    hits = for name <- names, taxa = lookup.(name), taxa != [], do: {name, taxa}

    case hits do
      [] ->
        nil

      hits ->
        %{
          method: method,
          tried: Enum.map(hits, &elem(&1, 0)),
          taxa: hits |> Enum.flat_map(&elem(&1, 1)) |> Enum.uniq_by(& &1.id),
          families: families
        }
    end
  end

  defp taxa({:ok, taxon}), do: [taxon]
  defp taxa({:ambiguous, taxa}), do: taxa
  defp taxa(:none), do: []

  defp in_families?(%Taxon{id: id}, families) do
    id |> family_ids() |> Enum.any?(&Map.has_key?(families, &1))
  end

  defp family_ids(id) do
    for %{rank: :family, taxon_id: family} <- Map.get(Taxa.lineages([id]), id, []), do: family
  end

  # -- families ----------------------------------------------------------------

  @doc """
  Whether the genus of a synonym (`genus`, a name) is in the family of
  `taxon` (rules C and H: a synonymy across families, such as a cynipid
  name held for a eulophid, is not trusted). False when either family is
  unknown, or when the genus's names point to more than one family.
  """
  @spec same_family?(String.t(), Taxon.t()) :: boolean()
  def same_family?(genus, %Taxon{} = taxon) do
    taxon_families = MapSet.new(family_ids(taxon.id))
    genus_families = genus |> List.wrap() |> genus_families(taxon.kingdom, taxon.id) |> Map.keys()

    MapSet.size(taxon_families) > 0 and genus_families != [] and
      Enum.all?(genus_families, &MapSet.member?(taxon_families, &1))
  end

  @doc """
  The families of `genera` (names), family ID to name: of each genus the
  tree holds (through its accepted name or a synonym), or, for a genus it
  does not hold, of the tree's taxa with a name in that genus (other than
  `exclude`, a taxon ID).
  """
  @spec genus_families([String.t()], String.t() | nil, integer() | nil) :: %{
          integer() => String.t()
        }
  def genus_families(genera, kingdom, exclude \\ nil) do
    ids = Enum.flat_map(genera, &genus_member_ids(&1, kingdom, exclude))

    for {_id, lineage} <- Taxa.lineages(ids),
        %{rank: :family, taxon_id: family, name: name} <- lineage,
        into: %{},
        do: {family, name}
  end

  defp genus_member_ids(genus, kingdom, exclude) do
    case Taxa.resolve_name(genus, rank: :genus, kingdom: kingdom) do
      {:ok, taxon} -> [taxon.id]
      {:ambiguous, taxa} -> Enum.map(taxa, & &1.id)
      :none -> named_in(genus, kingdom, exclude)
    end
  end

  # The taxa (but `exclude`) with a name, accepted or synonym, in `genus`.
  defp named_in(genus, kingdom, exclude) do
    word = NameNormalizer.normalize(genus)

    ids =
      genus
      |> Taxa.search_ids(ranks: Rank.species_and_below(), kingdom: kingdom)
      |> List.delete(exclude)

    synonyms = Taxa.list_synonyms_by_taxon(ids)
    lineages = Taxa.lineages(ids)

    Enum.filter(ids, fn id ->
      accepted = lineages |> Map.get(id, []) |> List.last()

      names =
        Enum.map(Map.get(synonyms, id, []), & &1.name) ++ List.wrap(accepted && accepted.name)

      Enum.any?(names, &(NameVariants.genus(&1) == word))
    end)
  end
end
