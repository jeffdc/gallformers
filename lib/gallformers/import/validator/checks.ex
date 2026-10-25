defmodule Gallformers.Import.Validator.Checks do
  @moduledoc false
  # validate.py's PackageChecks: one decoded batch against itself and its
  # document. Problems are `{level, message}`, in the order validate.py
  # reports them.

  alias Gallformers.Catalog.RelationshipTypes
  alias Gallformers.Import.Validator
  alias Gallformers.Sources.Docling
  alias Gallformers.Sources.QuoteLocator

  defstruct [
    :batch,
    :doc,
    :sha,
    problems: [],
    taxa: MapSet.new(),
    galls: MapSet.new(),
    ranks: %{},
    used_taxa: MapSet.new(),
    used_galls: MapSet.new()
  ]

  # Highest to lowest; acts that merge or divide taxa stop at family
  # (PRODUCER_GUIDE.md, Phase 2).
  @rank_order ~w(kingdom subkingdom phylum subphylum class subclass infraclass superorder order
                 suborder infraorder superfamily family subfamily tribe subtribe genus subgenus
                 section species subspecies variety form)
  @family_index Enum.find_index(@rank_order, &(&1 == "family"))

  @doc false
  @spec run(map(), map() | nil, String.t() | nil) :: [{:error | :warning, String.t()}]
  def run(batch, doc, sha) do
    %__MODULE__{batch: batch, doc: doc, sha: sha}
    |> declared("taxa", :taxa)
    |> declared("galls", :galls)
    |> ranks()
    |> document_hash()
    |> batch_checks()
    |> unmapped()
    |> unused()
    |> Map.fetch!(:problems)
    |> Enum.reverse()
  end

  defp error(c, message), do: %{c | problems: [{:error, message} | c.problems]}
  defp warning(c, message), do: %{c | problems: [{:warning, message} | c.problems]}

  defp list(c, key) do
    case c.batch[key] do
      list when is_list(list) -> Enum.filter(list, &is_map/1)
      _ -> []
    end
  end

  defp declared(c, key, field) do
    refs = Enum.map(list(c, key), & &1["ref"])

    c =
      refs
      |> ordered_frequencies()
      |> Enum.reduce(c, fn
        {ref, n}, acc when n > 1 -> error(acc, "#{key}: duplicate ref #{ref}")
        _, acc -> acc
      end)

    Map.put(c, field, MapSet.new(refs))
  end

  defp unique_ids(c, key) do
    list(c, key)
    |> Enum.map(& &1["id"])
    |> ordered_frequencies()
    |> Enum.reduce(c, fn
      {id, n}, acc when n > 1 -> error(acc, "#{key}: duplicate id #{id}")
      _, acc -> acc
    end)
  end

  # Counts in first-seen order (Python's Counter).
  defp ordered_frequencies(values) do
    counts = Enum.frequencies(values)
    values |> Enum.uniq() |> Enum.map(&{&1, counts[&1]})
  end

  defp ranks(c), do: %{c | ranks: Map.new(list(c, "taxa"), &{&1["ref"], &1["rank"]})}

  defp document_hash(c) do
    expected = Validator.dig(c.batch, ["source", "document", "sha256"])

    if c.sha && expected && expected != c.sha,
      do: error(c, "source.document.sha256 is #{expected}, but document.json hashes to #{c.sha}"),
      else: c
  end

  defp taxon(c, nil, _where), do: c

  defp taxon(c, ref, where) do
    c = %{c | used_taxa: MapSet.put(c.used_taxa, ref)}

    if MapSet.member?(c.taxa, ref),
      do: c,
      else: error(c, "#{where}: taxon #{ref} is not declared in taxa")
  end

  defp gall(c, nil, _where), do: c

  defp gall(c, ref, where) do
    c = %{c | used_galls: MapSet.put(c.used_galls, ref)}

    if MapSet.member?(c.galls, ref),
      do: c,
      else: error(c, "#{where}: Gall #{ref} is not declared in galls")
  end

  # -- evidence ----------------------------------------------------------------

  defp evidence(c, evidence, where) when is_list(evidence) do
    evidence
    |> Enum.with_index()
    |> Enum.reduce(c, fn {ev, i}, acc -> one_evidence(acc, ev, "#{where}/evidence/#{i}") end)
  end

  defp evidence(c, _evidence, _where), do: c

  defp one_evidence(%{doc: nil} = c, _ev, _path), do: c
  defp one_evidence(c, %{"statement" => _}, _path), do: c

  defp one_evidence(c, %{} = ev, path) do
    case ev["item"] do
      nil ->
        error(c, "#{path}: the package has a document, so evidence needs an item")

      ref ->
        item = if is_binary(ref), do: Docling.resolve(c.doc, ref)
        check_item(c, ev, ref, item, path)
    end
  end

  defp one_evidence(c, _ev, _path), do: c

  defp check_item(c, _ev, ref, nil, path),
    do: error(c, "#{path}: item #{ref} does not exist in document.json")

  defp check_item(c, %{"whole_item" => whole}, ref, item, path) when whole not in [nil, false] do
    if String.trim(Docling.item_text(item)) == "",
      do: error(c, "#{path}: whole_item #{ref} has no text"),
      else: c
  end

  defp check_item(c, ev, ref, item, path) do
    quote = if is_binary(ev["quote"]), do: ev["quote"], else: ""

    if quote_in?(quote, Docling.item_text(item)) do
      c
    else
      elsewhere =
        for other <- Docling.items(c.doc),
            quote_in?(quote, Docling.item_text(other)),
            do: other["self_ref"]

      hint =
        case elsewhere do
          [] -> "; not found anywhere in the document"
          refs -> "; found in #{refs |> Enum.take(3) |> Enum.join(", ")}"
        end

      error(
        c,
        "#{path}: quote not found in #{ref}#{hint}: #{inspect(String.slice(quote, 0, 80))}"
      )
    end
  end

  # validate.py's quote_in: a blank quote is in every text.
  defp quote_in?(quote, text) do
    String.trim(quote) == "" or match?({:ok, _span}, QuoteLocator.locate(text, quote))
  end

  # -- taxonomy batches --------------------------------------------------------

  defp batch_checks(c) do
    if c.batch["batch_type"] == "taxonomy", do: taxonomy_batch(c), else: gall_batch(c)
  end

  defp above_family?(c, ref) do
    case Enum.find_index(@rank_order, &(&1 == c.ranks[ref])) do
      nil -> false
      index -> index < @family_index
    end
  end

  defp taxonomy_batch(c) do
    c = unique_ids(c, "acts")

    list(c, "acts")
    |> Enum.with_index()
    |> Enum.reduce(c, fn {act, i}, acc ->
      where = "acts/#{i}"

      acc
      |> act_taxa(act, where)
      |> act_rank(act, where)
      |> evidence(act["evidence"], where)
    end)
  end

  defp act_taxa(c, act, where) do
    c = Enum.reduce(["taxon", "parent", "name", "accepted"], c, &taxon(&2, act[&1], where))

    case act["into"] do
      into when is_list(into) -> Enum.reduce(into, c, &taxon(&2, &1, where))
      _ -> c
    end
  end

  defp act_rank(c, act, where) do
    cond do
      act["kind"] == "synonymy" and
          (above_family?(c, act["name"]) or above_family?(c, act["accepted"])) ->
        error(c, "#{where}: synonymy above family is not supported")

      act["kind"] == "split" and above_family?(c, act["taxon"]) ->
        error(c, "#{where}: split above family is not supported")

      true ->
        c
    end
  end

  # -- gall batches ------------------------------------------------------------

  defp gall_batch(c) do
    facts = list(c, "facts")
    by_id = Map.new(facts, &{&1["id"], &1})
    c = unique_ids(c, "facts")

    c =
      list(c, "galls")
      |> Enum.with_index()
      |> Enum.reduce(c, fn {g, i}, acc ->
        ident = identified_by(g)
        where = "galls/#{i}/identified_by"
        acc |> taxon(ident["inducer"], where) |> taxon(ident["host"], where)
      end)

    init = %{inducers: [], descriptions: [], about: MapSet.new(), inducer_of: MapSet.new()}

    {c, seen} =
      facts
      |> Enum.with_index()
      |> Enum.reduce({c, init}, fn {fact, i}, {acc, seen} ->
        where = "facts/#{i}"
        {acc, seen} = fact_checks(acc, seen, fact, by_id, where)
        {evidence(acc, fact["evidence"], where), seen}
      end)

    c
    |> more_than_one(seen.inducers, "inducer_of")
    |> more_than_one(seen.descriptions, "description")
    |> gall_statements(seen)
  end

  defp identified_by(g) do
    case g["identified_by"] do
      %{} = ident -> ident
      _ -> %{}
    end
  end

  defp fact_checks(c, seen, %{"kind" => "relationship"} = fact, _by_id, where) do
    {subject, object} = {fact["subject"], fact["object"]}
    {c, seen} = relationship_refs(c, seen, fact, where)

    seen =
      if fact["type"] == "inducer_of" and fact["stance"] == "confirm" do
        %{
          seen
          | inducers: seen.inducers ++ [object],
            inducer_of: MapSet.put(seen.inducer_of, {subject, object})
        }
      else
        seen
      end

    {c, seen}
  end

  defp fact_checks(c, seen, %{"kind" => "qualifier"} = fact, by_id, where) do
    {qualifier_target(c, fact, Map.get(by_id, fact["of"]), where), seen}
  end

  defp fact_checks(c, seen, fact, _by_id, where) do
    c = gall(c, fact["gall"], where)
    seen = about(seen, [fact["gall"]])

    seen =
      if fact["kind"] == "description",
        do: %{seen | descriptions: seen.descriptions ++ [fact["gall"]]},
        else: seen

    {c, seen}
  end

  defp relationship_refs(c, seen, fact, where) do
    {subject, object, context} = {fact["subject"], fact["object"], fact["gall_context"]}

    case endpoints(fact["type"]) do
      :taxon_to_taxon_in_gall ->
        c = c |> taxon(subject, where) |> taxon(object, where) |> gall(context, where)
        {c, about(seen, [context])}

      :gall_to_gall ->
        {c |> gall(subject, where) |> gall(object, where), about(seen, [subject, object])}

      :taxon_to_gall ->
        {c |> taxon(subject, where) |> gall(object, where), about(seen, [object])}
    end
  end

  defp qualifier_target(c, fact, nil, where),
    do: error(c, "#{where}: qualifier points at #{fact["of"]}, which is not a Fact in this batch")

  defp qualifier_target(c, fact, %{"kind" => "relationship"} = target, where) do
    allowed = allowed_types(fact["qualifier"])

    if target["type"] in allowed,
      do: c,
      else:
        error(
          c,
          "#{where}: #{fact["qualifier"]} is not allowed on #{target["type"]} " <>
            "(allowed: #{Enum.join(allowed, ", ")})"
        )
  end

  defp qualifier_target(c, fact, _target, where),
    do: error(c, "#{where}: qualifier points at #{fact["of"]}, which is not a Relationship Fact")

  defp about(seen, refs), do: %{seen | about: Enum.into(refs, seen.about)}

  # An unknown type is a schema error already; checked as organism → Gall.
  defp endpoints(type) do
    case RelationshipTypes.get(type) do
      %{endpoints: endpoints} -> endpoints
      nil -> :taxon_to_gall
    end
  end

  # The Relationship types a qualifier fits, sorted.
  defp allowed_types(qualifier) do
    for(%{name: name, qualifiers: qs} <- RelationshipTypes.all(), qualifier in qs, do: name)
    |> Enum.sort()
  end

  defp more_than_one(c, refs, kind) do
    refs
    |> ordered_frequencies()
    |> Enum.reduce(c, fn
      {gall, n}, acc when n > 1 ->
        error(acc, "Gall #{gall} has more than one #{kind} Fact (#{n})")

      _, acc ->
        acc
    end)
  end

  defp gall_statements(c, seen) do
    Enum.reduce(list(c, "galls"), c, fn g, acc ->
      ref = g["ref"]
      new? = g["new"] == true

      acc =
        if new? and not MapSet.member?(seen.about, ref),
          do: error(acc, "Gall #{ref} is new but has no Facts about it"),
          else: acc

      inducer_fact(acc, g, seen, new?)
    end)
  end

  # A Gall the batch introduces must state its Inducer; for one Gallformers
  # already holds, the Inducer is only how it is looked up, so the Fact is
  # optional.
  defp inducer_fact(c, g, seen, new?) do
    ref = g["ref"]
    inducer = identified_by(g)["inducer"]

    if inducer && not MapSet.member?(seen.inducer_of, {inducer, ref}) do
      message =
        "Gall #{ref} is identified by Inducer #{inducer} but has no confirmed " <>
          "inducer_of Fact from #{inducer}"

      if new? or g["formerly_undescribed"] == true,
        do: error(c, message),
        else: warning(c, message)
    else
      c
    end
  end

  # -- the rest ----------------------------------------------------------------

  defp unmapped(c) do
    list(c, "unmapped")
    |> Enum.with_index()
    |> Enum.reduce(c, fn {entry, i}, acc ->
      where = "unmapped/#{i}"
      acc |> gall(entry["gall"], where) |> evidence(entry["evidence"], where)
    end)
  end

  defp unused(c) do
    c =
      c.taxa
      |> MapSet.difference(c.used_taxa)
      |> Enum.sort()
      |> Enum.reduce(c, &warning(&2, "taxon #{&1} is declared but never used"))

    c.galls
    |> MapSet.difference(c.used_galls)
    |> Enum.sort()
    |> Enum.reduce(c, &warning(&2, "Gall #{&1} is declared but never used"))
  end
end
