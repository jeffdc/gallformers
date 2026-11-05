defmodule Gallformers.Import.TermCandidates do
  @moduledoc """
  Seeding the term table before go-live (matter `d213`, Task F), so early
  Sources don't flood the review queue with questions about terms.

  ## Gathering (`gather/2`, `mix gallformers.import.term_candidates`)

  Reads every `gall.json` under the directories given (producer package
  directories, found recursively; a package is named by its directory) and
  takes its Trait terms as the import does (`Gallformers.Import.TraitTerms.uses/3`):
  format 4 `term` with `category` the producer's suggestion, format 3
  `value.as_written` with `value.value`, and a producer's Trait terms set
  aside (`unmapped` with a Trait slot) with no suggestion. A use is a
  Gall's use of a term for a Trait; it counts once for each category it
  suggests (nil: set aside, or none suggested).

  Uses are grouped by Trait and normalized term
  (`Gallformers.Catalog.Vocab.TraitTermMapping.normalize/1`) into
  candidates (`Gallformers.Import.TermCandidate`), upserted: a new term is
  added; an open candidate takes the counts of the packages read now in
  place of what it had from them (so gathering a package again counts it
  once) and keeps the other packages'; a decided candidate is never
  changed. A term the term table already holds — or the name of one of
  the Trait's values, which the import places under it — is not a
  candidate: it is reported with its standing and the other categories
  producers suggested for it (conflicts).

  ## Deciding (`decide/3`, `place_by_suggestion/2`)

  A superadmin rules on each candidate from the vocabulary page. Each
  ruling is a term edit made as `:superadmin`, recorded for replay
  (`Gallformers.Import.record_term_edit/3`): these are the same rulings a
  superadmin makes on the vocabulary page after go-live, and placing a
  term goes through `Gallformers.Import.place_term/4`, so its uses
  already waiting, in any Source on preview, get their Facts, there and on
  replay. (`:seed` stays the committed `traits.json` vocabulary, which
  the loader writes without an actor or a replay entry.)

    * `{:place, category}` — placed under `category` for every Source.
    * `{:ambiguous, candidates}` — used in more than one sense; each use is
      decided on its own between `candidates`.
    * `:no_fit` — fits no category; it stays text on the Gall.

  Skipping a candidate is not a decision: it stays open.
  """

  import Ecto.Query, only: [from: 2]

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Catalog.Vocab.TraitTermMapping
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Import
  alias Gallformers.Import.TermCandidate
  alias Gallformers.Import.TraitTerms
  alias Gallformers.Repo

  # Example uses kept per candidate.
  @max_examples 5

  @typedoc "A ruling on a candidate."
  @type decision :: {:place, String.t()} | {:ambiguous, [String.t()]} | :no_fit

  @typedoc "A term the term table holds, as gathering reports it."
  @type held :: %{
          trait: String.t(),
          term: String.t(),
          status: TraitTermMapping.status(),
          categories: [String.t()],
          candidates: [String.t()],
          conflicts: [TermCandidate.suggestion()]
        }

  @typedoc "What gathering did."
  @type summary :: %{
          packages: [String.t()],
          uses: non_neg_integer(),
          created: non_neg_integer(),
          updated: non_neg_integer(),
          decided: non_neg_integer(),
          held: [held()],
          unreadable: [{String.t(), String.t()}]
        }

  # -- gathering -------------------------------------------------------------------

  @doc """
  Gathers the Trait terms of the packages under `dirs` into candidates (see
  *Gathering*), in one audited transaction as `actor`.
  """
  @spec gather(Actor.t(), [String.t()]) :: {:ok, summary()} | {:error, term()}
  def gather(%Actor{} = actor, dirs) when is_list(dirs) do
    {uses, packages, unreadable} = read(dirs)
    values = Catalog.list_trait_values() |> Enum.group_by(& &1.trait, & &1.value)

    {held, open} =
      uses
      |> Enum.group_by(&{&1.trait, &1.normalized})
      |> Enum.map(fn {{trait, normalized}, uses} -> group(trait, normalized, uses) end)
      |> Enum.sort_by(&{&1.trait, &1.normalized_term})
      |> Enum.split_with(&held?(&1, values))

    Audit.transaction(actor, "import.gather_term_candidates", fn ->
      counts =
        open
        |> Enum.map(&upsert(&1, packages))
        |> Enum.frequencies()

      %{
        packages: packages,
        uses: length(uses),
        created: Map.get(counts, :created, 0),
        updated: Map.get(counts, :updated, 0),
        decided: Map.get(counts, :decided, 0),
        held: Enum.map(held, &held(&1, values)),
        unreadable: unreadable
      }
    end)
  end

  # Every use in the packages under `dirs`: {uses, package names, unreadable files}.
  defp read(dirs) do
    traits = MapSet.new(TraitValue.traits())

    {uses, packages, unreadable} =
      dirs
      |> Enum.flat_map(&Path.wildcard(Path.join(Path.expand(&1), "**/gall.json")))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.reduce({[], [], []}, fn path, {uses, packages, unreadable} ->
        package = path |> Path.dirname() |> Path.basename()

        with {:ok, bytes} <- File.read(path),
             {:ok, %{} = content} <- Jason.decode(bytes) do
          {uses ++ package_uses(content, package, traits), [package | packages], unreadable}
        else
          {:ok, _not_a_batch} -> {uses, packages, [{path, "not a JSON object"} | unreadable]}
          {:error, reason} -> {uses, packages, [{path, describe(reason)} | unreadable]}
        end
      end)

    {uses, packages |> Enum.uniq() |> Enum.sort(), Enum.reverse(unreadable)}
  end

  defp describe(%Jason.DecodeError{} = error), do: Exception.message(error)
  defp describe(reason), do: inspect(reason)

  defp package_uses(content, package, traits) do
    for use <- TraitTerms.uses(content), MapSet.member?(traits, use.trait) do
      %{
        source: package,
        trait: use.trait,
        term: String.trim(use.term),
        normalized: use.normalized,
        categories: use.facts |> Enum.map(& &1.suggestion) |> Enum.uniq(),
        gall: use.name_as_written || use.gall,
        quote: use.facts |> Enum.flat_map(& &1.evidence) |> Enum.find_value(& &1["quote"])
      }
    end
  end

  # A candidate's gathered fields from its uses.
  defp group(trait, normalized, uses) do
    %{
      trait: trait,
      normalized_term: normalized,
      term: written(uses),
      counts_by_source:
        uses
        |> Enum.group_by(& &1.source)
        |> Map.new(fn {s, us} ->
          {s, %{"uses" => length(us), "suggestions" => suggestions(us)}}
        end),
      uses: Enum.map(uses, &example/1)
    }
  end

  # The term as most often written; the first so written on a tie.
  defp written(uses) do
    uses
    |> Enum.map(& &1.term)
    |> Enum.with_index()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.min_by(fn {_term, [first | _] = indexes} -> {-length(indexes), first} end)
    |> elem(0)
  end

  # Each category the uses suggest, with how many, most first (nil last on a tie).
  defp suggestions(uses) do
    uses
    |> Enum.flat_map(& &1.categories)
    |> Enum.frequencies()
    |> Enum.map(fn {category, count} -> %{"category" => category, "count" => count} end)
    |> sort_suggestions()
  end

  defp sort_suggestions(suggestions),
    do: Enum.sort_by(suggestions, &{-&1["count"], is_nil(&1["category"]), &1["category"]})

  defp example(use) do
    %{
      "source" => use.source,
      "gall" => use.gall,
      "category" => List.first(use.categories),
      "quote" => use.quote
    }
  end

  defp held?(group, values), do: standing(group, values) != nil

  # The term table's row for the term, or its Trait's value of that name.
  defp standing(%{trait: trait, term: term, normalized_term: normalized}, values) do
    case Catalog.get_term(trait, term) do
      nil ->
        case Enum.find(
               Map.get(values, trait, []),
               &(TraitTermMapping.normalize(&1) == normalized)
             ) do
          nil -> nil
          value -> %{status: :placed, categories: [value], candidates: []}
        end

      term ->
        term
    end
  end

  defp held(group, values) do
    standing = standing(group, values)
    fits = if standing.status == :ambiguous, do: standing.candidates, else: standing.categories

    conflicts =
      group.counts_by_source
      |> Map.values()
      |> Enum.flat_map(& &1["suggestions"])
      |> Enum.filter(&(is_binary(&1["category"]) and &1["category"] not in fits))
      |> merge_counts()

    %{
      trait: group.trait,
      term: group.term,
      status: standing.status,
      categories: standing.categories,
      candidates: standing.candidates,
      conflicts: conflicts
    }
  end

  defp merge_counts(suggestions) do
    suggestions
    |> Enum.group_by(& &1["category"], & &1["count"])
    |> Enum.map(fn {category, counts} ->
      %{"category" => category, "count" => Enum.sum(counts)}
    end)
    |> sort_suggestions()
  end

  # Inserts or updates the group's candidate: :created, :updated or :decided.
  defp upsert(group, packages) do
    existing =
      Repo.one(
        from(c in TermCandidate,
          where: c.trait == ^group.trait and c.normalized_term == ^group.normalized_term,
          lock: "FOR UPDATE"
        )
      )

    case existing do
      nil ->
        %TermCandidate{} |> write(attrs(group, %{}, [])) |> Repo.insert!()
        :created

      %TermCandidate{decided_at: %DateTime{}} ->
        :decided

      %TermCandidate{} = candidate ->
        counts = Map.drop(candidate.counts_by_source, packages)
        kept = Enum.reject(candidate.uses, &(&1["source"] in packages))
        candidate |> write(attrs(group, counts, kept)) |> Repo.update!()
        :updated
    end
  end

  defp write(candidate, attrs), do: TermCandidate.gathered_changeset(candidate, attrs)

  # The group's fields, over the counts and examples kept from other packages.
  defp attrs(group, kept_counts, kept_examples) do
    counts = Map.merge(kept_counts, group.counts_by_source)
    suggestions = counts |> Map.values() |> Enum.flat_map(& &1["suggestions"]) |> merge_counts()

    %{
      trait: group.trait,
      term: group.term,
      normalized_term: group.normalized_term,
      counts_by_source: counts,
      suggestions: suggestions,
      uses: examples(kept_examples ++ group.uses, suggestions),
      total: counts |> Map.values() |> Enum.map(& &1["uses"]) |> Enum.sum()
    }
  end

  # A few examples: one for each category suggested first, most suggested
  # first, then the rest in order.
  defp examples(uses, suggestions) do
    firsts =
      for %{"category" => c} <- suggestions,
          use = Enum.find(uses, &(&1["category"] == c)),
          use != nil,
          do: use

    (firsts ++ uses) |> Enum.uniq() |> Enum.take(@max_examples)
  end

  # -- listing ---------------------------------------------------------------------

  @doc """
  The candidates still open, by Trait, most used first; `decided: true`
  adds the decided ones.
  """
  @spec list(keyword()) :: [TermCandidate.t()]
  def list(opts \\ []) do
    query =
      from(c in TermCandidate,
        order_by: [asc: c.trait, desc: c.total, asc: c.normalized_term]
      )

    query =
      if Keyword.get(opts, :decided, false),
        do: query,
        else: from(c in query, where: is_nil(c.decided_at))

    Repo.all(query)
  end

  @doc "A candidate by ID, raising if there is none."
  @spec get!(integer()) :: TermCandidate.t()
  def get!(id), do: Repo.get!(TermCandidate, id)

  # -- deciding --------------------------------------------------------------------

  @doc """
  Rules on `candidate` (see *Deciding*): makes the term edit, recorded for
  replay, and marks the candidate decided, in one transaction. On error
  (the term edit's, or `{:decided, candidate}`) nothing is written.
  """
  @spec decide(Actor.t(), TermCandidate.t(), decision()) ::
          {:ok, TermCandidate.t()} | {:error, term()}
  def decide(%Actor{} = actor, %TermCandidate{id: id}, decision) do
    Audit.transaction(actor, "import.decide_term_candidate", fn ->
      candidate = Repo.one!(from(c in TermCandidate, where: c.id == ^id, lock: "FOR UPDATE"))

      if TermCandidate.decided?(candidate), do: Repo.rollback({:decided, candidate})

      with {:ok, recorded} <- recorded(decision),
           {:ok, _term} <- edit(actor, candidate, decision),
           {:ok, decided} <-
             candidate
             |> TermCandidate.decide_changeset(recorded, actor, DateTime.utc_now())
             |> Repo.update() do
        decided
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp recorded({:place, category}) when is_binary(category), do: {:ok, %{"place" => category}}

  defp recorded({:ambiguous, [_ | _] = candidates}),
    do: {:ok, %{"ambiguous" => Enum.uniq(candidates)}}

  defp recorded(:no_fit), do: {:ok, %{"no_fit" => true}}
  defp recorded(decision), do: {:error, {:invalid_decision, decision}}

  defp edit(actor, %TermCandidate{trait: trait, term: term}, {:place, category}),
    do: Import.place_term(actor, trait, term, category)

  defp edit(actor, %TermCandidate{trait: trait, term: term}, {:ambiguous, candidates}),
    do:
      Import.record_term_edit(
        actor,
        {:mark_ambiguous, trait, term, Enum.uniq(candidates), :superadmin}
      )

  defp edit(actor, %TermCandidate{trait: trait, term: term}, :no_fit),
    do: Import.record_term_edit(actor, {:mark_no_fit, trait, term, :superadmin})

  @doc """
  Places each of `candidates` whose uses all suggest one category under it
  (`TermCandidate.agreed_category/1`), each its own ruling (`decide/3`).
  The others are skipped. Returns how many were placed and skipped, and
  the ones whose ruling failed, with why.
  """
  @spec place_by_suggestion(Actor.t(), [TermCandidate.t()]) ::
          {:ok,
           %{
             placed: non_neg_integer(),
             skipped: non_neg_integer(),
             failed: [{TermCandidate.t(), term()}]
           }}
  def place_by_suggestion(%Actor{} = actor, candidates) when is_list(candidates) do
    result =
      Enum.reduce(candidates, %{placed: 0, skipped: 0, failed: []}, fn candidate, acc ->
        case place_agreed(actor, candidate) do
          :skipped -> %{acc | skipped: acc.skipped + 1}
          {:ok, _} -> %{acc | placed: acc.placed + 1}
          {:error, reason} -> %{acc | failed: acc.failed ++ [{candidate, reason}]}
        end
      end)

    {:ok, result}
  end

  defp place_agreed(actor, candidate) do
    case TermCandidate.agreed_category(candidate) do
      nil -> :skipped
      category -> decide(actor, candidate, {:place, category})
    end
  end
end
