defmodule Gallformers.Import.Disputes do
  @moduledoc """
  Phase 6 disputes as queue items (`9449` §5): findings in `review.json`
  that the producer disagreed with, one item per statement (several
  reviewers' findings together), holding approval until a curator decides
  `%{"keep" => true}` or `%{"skip" => true}`.

  ## Trait Facts

  A format 3 checker's finding on a Trait Fact is about its value, which
  format 4 replaced with the Source's term placed by Gallformers (matter
  `d213`): it is no dispute, but a disagreement on the term
  (`Gallformers.Import.TraitTerms`, which carries the finding into the
  term's question). A format 4 finding on a Trait Fact (its term, its
  support) is a dispute like any other.

  Dropping a Trait Fact (`skip`) keeps the Source's words as text on the
  Gall: the decision adds an `unmapped` entry
  (`Gallformers.Import.BatchUnmapped`) for it, its slot the Trait
  (`texts/2`).

  An item may also ask about statements of another batch,
  `subject["also"]` listing them as `%{"batch" => file, "ref" => ref}`;
  its decision holds for each (`refs/1`).

  ## One question for identical disputes (matter `d213`, Task 10)

  Disputes about the same statement — the same kind of Fact with the same
  value, the Gall aside: ten Galls each "on Quercus" — share a group,
  `subject["group"]` (`group/2`: `"host_of:quercus"`), and are shown and
  decided as one question (`Gallformers.Import.decide_group/3`, one
  decision per item). A dispute about an act, a taxon or a Gall, or a
  description, has no group.

  ## A Host dispute kept, the Host read as another plant

  A dispute about a Host (`host?/1`: a `host_of` Fact) may be decided
  `%{"keep" => true, "host_reading" => %{"name" => as_written, "taxon_id"
  => plant}}`: the statement stands, but the Source means another plant
  by its Host's name (`check_reading/3`: the name is the disputed Host's).
  The reading is a Gall decision's (`Gallformers.Import.GallDecisions`):
  the tree records the name as the plant's synonym in the Source's sense,
  and every use of the name in the package resolves to the plant. A group
  of Host disputes kept with a reading reads it for each one kept
  (`Gallformers.Import.decide_group/3`).

  That is for a misapplied species name, the Source's throughout (Osten
  Sacken's "Q. nigra" is Q. marilandica). A Host above species rank (a
  genus, a section) is the Source's name for many Galls, and is not read
  so (`check_reading/3`): Ashmead's "an unknown oak" Galls, stated on
  Quercus, are each on one section or another. Such a dispute is kept on
  the plant chosen for its statements, `%{"keep" => true, "host_taxon_id"
  => plant}` (any rank, `check_host_taxon/3`): each of them goes in on the
  plant (`chosen_hosts/1`), and nothing else changes — no synonym, no
  reading. A group of Host disputes may be kept so too.

  ## Disputes about Trait terms

  A dispute about a format 4 Trait Fact (`trait?/1`: `subject["trait"]`
  and `subject["term"]`) is about where the term is placed, and goes with
  the Trait terms: it holds no approval
  (`Gallformers.Import.Queue.blocking?/2`). Left open when its batch is
  applied, its Fact waits, unwritten, and its term is stored on the Gall
  as a waiting term linked to the dispute
  (`Gallformers.Import.TraitTerms.store_disputed/3`), so the Gall's page
  shows the Source's words; decided afterwards, `keep` writes it as the
  batch would have and settles the waiting term under its categories, and
  `skip` keeps its words as text (the waiting term settled as text).

  Such a dispute says what each side chose as data, not only in its
  findings' prose (`c8c3`; a producer's summary once dropped the value it
  chose): `subject["facts"]`, the term's Facts on the Gall (one per value
  its words name); `subject["suggestions"]`, the producer's category for
  each (nil for none); and `subject["placements"]`, each checker's, as
  `Gallformers.Import.TraitTerms` gives a term's covers.
  """
  alias Gallformers.Import.Batch
  alias Gallformers.Import.GallDecisions
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.TraitTerms
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer

  @doc """
  The dispute items for batch `file` (decoded `content`) from `review` (the
  decoded `review.json`, or nil), in ref order.
  """
  @spec items(map() | nil, String.t(), map()) :: [map()]
  def items(nil, _file, _content), do: []

  def items(review, file, content) do
    facts = Map.new(List.wrap(content["facts"]), &{&1["id"], &1})

    uses =
      for use <- TraitTerms.uses(content, review, file: file),
          f <- use.facts,
          into: %{},
          do: {f.ref, use}

    review
    |> Map.get("findings", [])
    |> List.wrap()
    |> Enum.filter(&(&1["batch"] == file and get_in(&1, ["response", "decision"]) == "disagree"))
    |> Enum.reject(&valued_trait?(facts[&1["id"]]))
    |> Enum.group_by(& &1["id"])
    |> Enum.map(fn {id, findings} -> item(id, findings, facts[id], content, uses[id]) end)
    |> Enum.sort_by(&ref_order(&1.statement_ref))
  end

  # A format 3 Trait Fact (a value, no term).
  defp valued_trait?(%{"kind" => "trait"} = fact), do: not Map.has_key?(fact, "term")
  defp valued_trait?(_fact), do: false

  defp item(id, findings, fact, content, use) do
    %{
      kind: :dispute,
      statement_ref: id,
      subject:
        %{
          "findings" =>
            Enum.map(
              findings,
              &Map.take(&1, ["problem", "reason", "summary", "suggestion", "reviewer", "response"])
            ),
          "group" => group(fact, content)
        }
        |> Map.merge(trait_term(fact))
        |> Map.merge(chosen(fact, use))
        |> Map.reject(fn {_k, v} -> is_nil(v) end),
      proposal: %{},
      reason:
        Enum.map_join(findings, " | ", fn f ->
          "reviewer: #{f["reason"]}; producer: #{f["response"]["reason"]}"
        end)
    }
  end

  defp trait_term(%{"kind" => "trait", "trait" => trait, "term" => term})
       when is_binary(trait) and is_binary(term),
       do: %{"trait" => trait, "term" => term}

  defp trait_term(_fact), do: %{}

  # What each side chose for a format 4 Trait Fact, as data (`c8c3`): its
  # use's Facts (the term's every Fact on the Gall, one per value), the
  # producer's category for each (nil for none), and the checkers'
  # placements, as `Gallformers.Import.TraitTerms` gives a term's covers.
  defp chosen(%{"kind" => "trait", "term" => term}, %{facts: facts}) when is_binary(term) do
    %{
      "facts" => Enum.map(facts, & &1.ref),
      "suggestions" => Enum.map(facts, & &1.suggestion),
      "placements" => Enum.flat_map(facts, & &1.placements)
    }
  end

  defp chosen(_fact, _use), do: %{}

  @doc """
  The group of a dispute about `fact` (a Fact of the decoded batch
  `content`, or nil for an act, taxon or Gall): its kind or type and its
  value, the Gall aside, taxa by their names as written, normalized —
  `"host_of:quercus"`, `"trait:detachable:attached by a small point"`,
  `"occurrence:US-CA"`. Nil for a description, and for anything but a Fact.
  """
  @spec group(map() | nil, map()) :: String.t() | nil
  def group(%{"kind" => "relationship", "type" => type} = fact, content) do
    names = taxon_names(content)

    sides =
      for ref <- [fact["subject"], fact["object"]],
          is_binary(ref),
          not String.starts_with?(ref, "g"),
          do: Map.get(names, ref, ref)

    Enum.join([type | sides], ":")
  end

  def group(%{"kind" => "trait", "trait" => trait} = fact, _content) do
    term =
      fact["term"] || get_in(fact, ["value", "as_written"]) || get_in(fact, ["value", "value"])

    if is_binary(term), do: "trait:#{trait}:#{words(term)}"
  end

  def group(%{"kind" => "qualifier", "qualifier" => q} = fact, _content),
    do: "qualifier:#{q}:#{value(fact["value"])}"

  def group(%{"kind" => "range"} = fact, _content),
    do: "range:#{fact["adjustment"]}:#{value(fact["place"])}"

  def group(%{"kind" => "occurrence"} = fact, _content),
    do: "occurrence:#{value(fact["place"])}"

  def group(%{"kind" => "alias", "name" => name}, _content) when is_binary(name),
    do: "alias:#{words(name)}"

  def group(_fact, _content), do: nil

  defp taxon_names(content) do
    for %{"ref" => ref} = t <- List.wrap(content["taxa"]),
        name = t["name_reading"] || t["name_as_written"],
        is_binary(name),
        into: %{},
        do: {ref, NameNormalizer.normalize(name)}
  end

  defp value(%{"value" => value}), do: value
  defp value(value), do: value

  defp words(text), do: text |> String.downcase() |> String.split() |> Enum.join(" ")

  @doc "Whether a dispute is about a Trait term (a format 4 Trait Fact)."
  @spec trait?(QueueItem.t() | map()) :: boolean()
  def trait?(%{kind: kind}) when kind != :dispute, do: false

  def trait?(%{subject: %{"trait" => trait, "term" => term}}),
    do: is_binary(trait) and is_binary(term)

  def trait?(_item), do: false

  defp ref_order(ref) do
    case Regex.run(~r/\A(\D*)(\d+)\z/, ref) do
      [_, prefix, n] -> {prefix, String.to_integer(n), ref}
      nil -> {ref, 0, ref}
    end
  end

  # -- deciding ----------------------------------------------------------------

  @doc "The statement refs a dispute item is about: its own, then those in `subject[\"also\"]`."
  @spec refs(QueueItem.t() | map()) :: [String.t()]
  def refs(%{statement_ref: ref, subject: subject}),
    do: [ref | for(%{"ref" => other} <- List.wrap(subject["also"]), do: other)]

  @doc "Whether a dispute is about a Host: a `host_of` Fact (its group, `group/2`)."
  @spec host?(QueueItem.t() | map()) :: boolean()
  def host?(%{kind: :dispute, subject: %{"group" => "host_of:" <> _}}), do: true
  def host?(_item), do: false

  @host_extras ["host_reading", "host_taxon_id"]

  @doc "Whether a dispute's decision carries a Host's reading or a Host chosen for it."
  @spec host_extras?(map()) :: boolean()
  def host_extras?(choice), do: Enum.any?(@host_extras, &Map.has_key?(choice, &1))

  @doc "Splits a dispute's decision into `{extras, choice}`: `host_reading` and `host_taxon_id`, and the rest."
  @spec split(map()) :: {map(), map()}
  def split(choice), do: Map.split(choice, @host_extras)

  @doc """
  Checks a Host dispute's extras (`split/1`) beside its `choice`: a reading
  (`check_reading/3`) or a Host chosen (`check_host_taxon/3`), not both.
  `:ok` or `{:error, message}`.
  """
  @spec check_extras(QueueItem.t(), map(), map()) :: :ok | {:error, String.t()}
  def check_extras(item, extras, choice) do
    case extras do
      %{"host_reading" => _, "host_taxon_id" => _} ->
        {:error, "host_reading and host_taxon_id don't go together"}

      %{"host_reading" => reading} ->
        check_reading(item, choice, reading)

      %{"host_taxon_id" => id} ->
        check_host_taxon(item, choice, id)
    end
  end

  @doc """
  Checks a Host dispute's reading (`"host_reading"`) beside its `choice`:
  only kept, and the name its own Host's as the batch writes it, read as a
  plant (`Gallformers.Import.GallDecisions.check_reading/2`). A Host above
  species rank (a genus, a section) is never read so: its name is the
  Source's for many Galls, and reading it would move every one
  (`check_host_taxon/3` chooses the plant for these Galls instead). `:ok`
  or `{:error, message}`.
  """
  @spec check_reading(QueueItem.t(), map(), term()) :: :ok | {:error, String.t()}
  def check_reading(item, choice, reading) do
    content = content(item)

    cond do
      not host?(item) ->
        {:error, "host_reading goes only on a dispute about a Host"}

      choice != %{"keep" => true} ->
        {:error, "host_reading goes only with keep"}

      not (is_map(reading) and
               Enum.any?(
                 host_names(item, content),
                 &GallDecisions.same_name?(&1, reading["name"])
               )) ->
        {:error, "host_reading must name the disputed Host"}

      rank = above_species_rank(item, content) ->
        {:error, "this Host is a #{rank}: choose a plant for these Galls instead"}

      true ->
        GallDecisions.check_reading(content, reading)
    end
  end

  @doc """
  Checks a Host dispute's Host chosen for its statements (`"host_taxon_id"`)
  beside its `choice`: only kept, and a plant, of any rank. `:ok` or
  `{:error, message}`.
  """
  @spec check_host_taxon(QueueItem.t(), map(), term()) :: :ok | {:error, String.t()}
  def check_host_taxon(item, choice, id) do
    cond do
      not host?(item) -> {:error, "host_taxon_id goes only on a dispute about a Host"}
      choice != %{"keep" => true} -> {:error, "host_taxon_id goes only with keep"}
      not plant?(id) -> {:error, "host_taxon_id must be a plant"}
      true -> :ok
    end
  end

  defp plant?(id), do: is_integer(id) and match?(%{kingdom: "Plantae"}, Taxa.get_taxon(id))

  @doc """
  The Hosts chosen for the statements of `decided` (decided items):
  a Host dispute kept with `"host_taxon_id"`, for each of its Facts, ref
  to the plant. That statement goes in on the plant; nothing else of the
  Source changes.
  """
  @spec chosen_hosts([QueueItem.t()]) :: %{String.t() => integer()}
  def chosen_hosts(decided) do
    for %QueueItem{decision: %{"keep" => true, "host_taxon_id" => id}} = item <- decided,
        host?(item),
        is_integer(id),
        ref <- refs(item),
        into: %{},
        do: {ref, id}
  end

  # The rank of the disputed Host, when it is above species rank: the
  # taxon its statement resolved to, else the rank the batch declares.
  defp above_species_rank(item, content),
    do: GallDecisions.above_species_rank(item.batch_id, content, host_refs(item, content))

  # The refs of the disputed statements' Host.
  defp host_refs(item, content) do
    facts = Map.new(List.wrap(content["facts"]), &{&1["id"], &1})

    for ref <- refs(item),
        %{"type" => "host_of", "subject" => host} <- [facts[ref]],
        is_binary(host),
        uniq: true,
        do: host
  end

  # The names the batch writes the disputed statements' Host by.
  defp host_names(item, content) do
    taxa = Map.new(List.wrap(content["taxa"]), &{&1["ref"], &1})

    for host <- host_refs(item, content),
        t = taxa[host],
        is_map(t),
        name <- [t["name_as_written"], t["name_reading"]],
        is_binary(name),
        do: name
  end

  defp content(%QueueItem{batch_id: batch_id}) when is_integer(batch_id),
    do: Repo.get!(Batch, batch_id).content || %{}

  defp content(_item), do: %{}

  @doc "The choices a dispute allows, as `{key, check}` (`Gallformers.Import.Queue.validate_decision/3`)."
  @spec choices(QueueItem.t()) :: [{String.t(), (term() -> boolean())}]
  def choices(_item), do: [{"keep", &(&1 == true)}, {"skip", &(&1 == true)}]

  @doc """
  The `unmapped` entries (`Gallformers.Import.BatchUnmapped` fields, less
  the batch and position) that keep as text the Trait Facts of `content`
  (the decoded batch) that the dispute `item`, decided `skip`, drops.
  """
  @spec texts(QueueItem.t(), map()) :: [map()]
  def texts(%QueueItem{kind: :dispute, decision: %{"skip" => true}} = item, content) do
    facts = Map.new(List.wrap(content["facts"]), &{&1["id"], &1})

    for ref <- refs(item),
        %{"kind" => "trait", "trait" => trait} = fact <- [facts[ref]],
        term = fact["term"] || get_in(fact, ["value", "as_written"]),
        is_binary(term),
        do: %{
          term: term,
          slot: trait,
          gall_ref: fact["gall"],
          note: "kept as text: #{item.decided_by_name} dropped the disputed #{trait} (#{ref})",
          evidence: List.wrap(fact["evidence"])
        }
  end

  def texts(_item, _content), do: []
end
