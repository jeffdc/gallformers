defmodule Gallformers.Import.UnusedNames do
  @moduledoc """
  The missed-names check (`d213`, "Cost correction (2026-11-05)"): the
  taxon names a Source prints that Gallformers' tree holds but that none of
  the package's batches declare — a short list a curator can scan for a
  taxon the producer left out (Osten Sacken's "Cynips quercus inanis").

  The text is the package's `document.json` as the reader shows it
  (`Gallformers.Import.Passages.blocks/1`: page headers and footers
  skipped). Within each block, every run of two or three words that starts
  with a capitalised genus ("Andricus", "ANDRICUS") or an abbreviated one
  ("Q. alba", expanded with every genus of that initial the batches write
  in full that the tree holds, `Gallformers.Import.Resolver.genera/2`) is
  a candidate:

    * rank markers ("var.", "subsp.", "f.") between the epithets are
      ignored, as is a subgenus in parentheses after the genus; the tree is
      asked for the name with and without them;
    * an authority after the name ("Smith", "L.") ends it;
    * old Cynips-style names ("C. q. inanis", "Cynips quercus inanis",
      "C.Q. INANIS") are asked for as written, as "Cynips inanis", and as
      today's fused epithet *quercusinanis* in any genus.

  All candidates are looked up in one query (`Gallformers.Taxa.names_held/2`).
  At each position the longest candidate that a batch declares or the tree
  holds wins and its words are used up ("Quercus prinos var. bicolor" is
  not also "Quercus prinos"); a tree-held one no batch declares is
  reported.

  A batch declares the names its `taxa` write (`name_as_written`,
  `name_reading`), read the same way, an authority dropped. A denied batch
  declares nothing.

  Each reported name is `%{name, normalized, taxon_ids, items, pages}`:
  the name as first printed, its normalized form (abbreviations expanded,
  Cynips style as "cynips quercus inanis"), the tree taxa holding it, the
  first few blocks it appears in (`#/texts/N`), and every page it appears
  on; in the order the Source first prints them. Nothing here writes.
  """

  import Ecto.Query

  alias Gallformers.Import.Batch
  alias Gallformers.Import.Package
  alias Gallformers.Import.Passages
  alias Gallformers.Import.Resolver
  alias Gallformers.Import.ReviewContext
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer

  @type unused_name :: %{
          name: String.t(),
          normalized: String.t(),
          taxon_ids: [integer()],
          items: [String.t()],
          pages: [pos_integer()]
        }

  # How many of a name's blocks are listed.
  @items_shown 5
  @token ~r/\p{L}+\.?/u
  @full_genus ~r/\A\p{Lu}\p{L}+\z/u
  @abbreviated_genus ~r/\A\p{Lu}\.\z/u
  # Rank markers as printed between epithets, and as the tree writes them.
  @markers ~w(var var. variety subsp subsp. ssp ssp. f. forma)
  @tree_markers ~w(var. subsp. ssp. f. forma form variety)
  # "q." for quercus in old Cynips-style names; capitals only after an
  # abbreviated or capitalised genus ("C.Q. INANIS", "CYNIPS Q. INANIS").
  @quercus ~w(q q. quercus)
  @quercus_caps ~w(Q Q. QUERCUS)

  @doc """
  The unused names of `package`: `{:ok, names}`, or the error reading its
  document (`Gallformers.Import.ReviewContext.document/1`).
  """
  @spec for_package(Package.t()) :: {:ok, [unused_name()]} | {:error, term()}
  def for_package(%Package{} = package) do
    with {:ok, doc} <- ReviewContext.document(package) do
      batches =
        Repo.all(
          from b in Batch,
            where: b.package_id == ^package.id and b.status != :denied,
            order_by: b.id,
            select: b.content
        )

      {:ok, list(doc, batches)}
    end
  end

  @doc """
  The names `doc` (a decoded `document.json`) prints that the tree holds
  and none of `batches` (decoded batch contents) declare.
  """
  @spec list(map(), [map()]) :: [unused_name()]
  def list(doc, batches) when is_map(doc) and is_list(batches) do
    taxa = Enum.flat_map(batches, &List.wrap(&1["taxa"]))
    genera = taxa |> Resolver.genera([]) |> Enum.group_by(&initial/1, &String.downcase/1)
    declared = declared(taxa, genera)

    blocks =
      for block <- Passages.blocks(doc) do
        tokens = tokens(block.text)

        spans =
          for i <- 0..(tuple_size(tokens) - 1)//1, do: spans(tokens, i, block.text, genera, :text)

        {block, List.to_tuple(spans)}
      end

    candidates = for {_block, spans} <- blocks, span <- Tuple.to_list(spans), do: span
    held = held(List.flatten(candidates))

    blocks
    |> Enum.flat_map(fn {block, spans} -> walk(block, spans, 0, declared, held, []) end)
    |> report()
  end

  # -- declared names ----------------------------------------------------------

  defp declared(taxa, genera) do
    for t <- taxa,
        name <- [t["name_as_written"], t["name_reading"]],
        is_binary(name),
        tokens = tokens(name),
        tuple_size(tokens) > 0,
        span <- Enum.take(spans(tokens, 0, name, genera, :declared), 1),
        option <- span,
        into: MapSet.new(),
        do: option.key
  end

  # -- reading the text --------------------------------------------------------

  defp tokens(text) do
    @token
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [{start, length}] -> {binary_part(text, start, length), start, length} end)
    |> List.to_tuple()
  end

  # The candidate names starting at token `i`, longest span first; each span
  # a list of options, one per genus an abbreviation expands to.
  defp spans(tokens, i, text, genera, mode) do
    {word, _, _} = elem(tokens, i)

    case heads(word, genera) do
      [] ->
        []

      heads ->
        caps? = Regex.match?(@abbreviated_genus, word) or String.upcase(word) == word

        tokens
        |> words_after(subgenus_skipped(tokens, i + 1, text), caps?, mode)
        |> Enum.map(fn {words, last} ->
          Enum.map(heads, &option(&1, words, start(tokens, i), stop(tokens, last), text, last))
        end)
    end
  end

  defp heads(word, genera) do
    cond do
      Regex.match?(@full_genus, word) -> [String.downcase(word)]
      Regex.match?(@abbreviated_genus, word) -> Map.get(genera, initial(word), [])
      true -> []
    end
  end

  defp initial(word), do: word |> String.first() |> String.downcase()

  # A subgenus in parentheses straight after the genus is skipped.
  defp subgenus_skipped(tokens, j, text) when j < tuple_size(tokens) do
    {word, start, length} = elem(tokens, j)
    after_word = binary_part(text, start + length, byte_size(text) - start - length)

    if start > 0 and binary_part(text, start - 1, 1) == "(" and
         Regex.match?(@full_genus, word) and Regex.match?(~r/\A[^\p{L}]*\)/u, after_word),
       do: j + 1,
       else: j
  end

  defp subgenus_skipped(_tokens, j, _text), do: j

  # The word lists a name starting before token `j` can have, longest first,
  # each with the index of its last token: `{:quercus, epithet}` for the
  # Cynips style, else one or two epithets (a marker between them kept).
  defp words_after(tokens, j, caps?, mode) do
    word = token(tokens, j)

    cond do
      quercus?(word, caps?) and epithet?(token(tokens, j + 1), mode) ->
        [{{:quercus, epithet(token(tokens, j + 1))}, j + 1}]

      quercus?(word, caps?) and word not in ["quercus", "QUERCUS"] ->
        []

      epithet?(word, mode) ->
        binomial = {[epithet(word)], j}

        if String.ends_with?(word, "."),
          do: [binomial],
          else: [trinomial(tokens, j, mode), binomial]

      true ->
        []
    end
    |> Enum.reject(&is_nil/1)
  end

  defp trinomial(tokens, j, mode) do
    first = epithet(token(tokens, j))
    next = token(tokens, j + 1)

    {marker, k} =
      if next && String.downcase(next) in @markers,
        do: {String.downcase(next), j + 2},
        else: {nil, j + 1}

    second = token(tokens, k)
    if epithet?(second, mode), do: {[first, {marker, epithet(second)}], k}
  end

  defp token(tokens, j) when j < tuple_size(tokens), do: elem(elem(tokens, j), 0)
  defp token(_tokens, _j), do: nil

  defp start(tokens, i), do: elem(elem(tokens, i), 1)

  defp stop(tokens, last) do
    {_, start, length} = elem(tokens, last)
    start + length
  end

  defp quercus?(nil, _caps?), do: false
  defp quercus?(word, caps?), do: word in @quercus or (caps? and word in @quercus_caps)

  # An epithet: two letters or more, not a rank marker; in a batch's name a
  # capitalised word after the genus is its authority ("Smith").
  defp epithet?(nil, _mode), do: false

  defp epithet?(word, mode) do
    bare = String.trim_trailing(word, ".")

    String.length(bare) >= 2 and String.downcase(word) not in @markers and
      not (mode == :declared and title_case?(bare))
  end

  defp title_case?(word), do: Regex.match?(~r/\A\p{Lu}.*\p{Ll}/u, word)

  defp epithet(word), do: word |> String.trim_trailing(".") |> String.downcase()

  # One candidate: the key it is declared under (Cynips style without
  # "quercus", markers dropped), its normalized form, the names asked of
  # the tree, the fused epithets asked in any genus.
  defp option(head, {:quercus, epithet}, start, stop, text, last) do
    %{
      key: normalize([head, epithet]),
      normalized: normalize([head, "quercus", epithet]),
      names: [
        normalize([head, "quercus", epithet]),
        normalize([head, "quercus" <> epithet]),
        normalize([head, epithet])
      ],
      epithets: [normalize(["quercus" <> epithet])],
      printed: binary_part(text, start, stop - start),
      last: last
    }
  end

  defp option(head, [first], start, stop, text, last) do
    name = normalize([head, first])

    %{
      key: name,
      normalized: name,
      names: [name],
      epithets: [],
      printed: binary_part(text, start, stop - start),
      last: last
    }
  end

  defp option(head, [first, {marker, second}], start, stop, text, last) do
    %{
      key: normalize([head, first, second]),
      normalized: normalize(Enum.reject([head, first, marker, second], &is_nil/1)),
      names: [
        normalize([head, first, second])
        | for(m <- @tree_markers, do: normalize([head, first, m, second]))
      ],
      epithets: [],
      printed: binary_part(text, start, stop - start),
      last: last
    }
  end

  defp normalize(words), do: words |> Enum.join(" ") |> NameNormalizer.normalize()

  # -- the tree ----------------------------------------------------------------

  # What the tree holds of every candidate, in one query: exact names, and
  # binomials by epithet for the fused Cynips-style names.
  defp held(options) do
    held =
      Taxa.names_held(
        options |> Enum.flat_map(& &1.names) |> Enum.uniq(),
        options |> Enum.flat_map(& &1.epithets) |> Enum.uniq()
      )

    by_epithet =
      for {name, ids} <- held, [_genus, epithet] <- [String.split(name)], reduce: %{} do
        acc -> Map.update(acc, epithet, ids, &(&1 ++ ids))
      end

    %{names: held, epithets: by_epithet}
  end

  defp held_ids(option, held) do
    (Enum.flat_map(option.names, &Map.get(held.names, &1, [])) ++
       Enum.flat_map(option.epithets, &Map.get(held.epithets, &1, [])))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # -- reporting ---------------------------------------------------------------

  # Left to right through a block's tokens: at each, the longest span that
  # a batch declares or the tree holds uses its tokens up.
  defp walk(_block, spans, i, _declared, _held, found) when i >= tuple_size(spans),
    do: Enum.reverse(found)

  defp walk(block, spans, i, declared, held, found) do
    case Enum.find_value(elem(spans, i), &match(&1, declared, held)) do
      nil ->
        walk(block, spans, i + 1, declared, held, found)

      {:declared, last} ->
        walk(block, spans, last + 1, declared, held, found)

      {:held, option, ids} ->
        hit = Map.merge(option, %{taxon_ids: ids, ref: block.ref, page: block.page})
        walk(block, spans, option.last + 1, declared, held, [hit | found])
    end
  end

  defp match(span, declared, held) do
    case Enum.find(span, &MapSet.member?(declared, &1.key)) do
      %{last: last} ->
        {:declared, last}

      nil ->
        Enum.find_value(span, &held_match(&1, held))
    end
  end

  defp held_match(option, held) do
    case held_ids(option, held) do
      [] -> nil
      ids -> {:held, option, ids}
    end
  end

  defp report(hits) do
    groups = Enum.group_by(hits, & &1.key)

    for key <- hits |> Enum.map(& &1.key) |> Enum.uniq() do
      [first | _] = all = groups[key]

      %{
        name: first.printed,
        normalized: first.normalized,
        taxon_ids: all |> Enum.flat_map(& &1.taxon_ids) |> Enum.uniq() |> Enum.sort(),
        items: all |> Enum.map(& &1.ref) |> Enum.uniq() |> Enum.take(@items_shown),
        pages: all |> Enum.map(& &1.page) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()
      }
    end
  end
end
