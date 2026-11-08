defmodule Gallformers.Import.TraitTerms do
  @moduledoc """
  Placing a Source's Trait terms on import (matter `d213`, Task C).

  A trait Fact carries the Source's term and the producer's suggested
  category (format 4: `term`, `category`, `depends_on_gall`; format 3:
  `value.as_written` is the term and `value.value` the suggestion), and the
  checker places every term blind (`review.json` `placements`, format 4
  only). A format 3 producer's Trait terms set aside (`unmapped` with a
  Trait slot) are terms with no suggestion.

  ## Uses

  A Gall's use of a term for a Trait is its Facts with that term (compared
  by `Gallformers.Catalog.Vocab.TraitTermMapping.normalize/1`): usually one,
  one per value when the term's words name several ("green-yellow": a
  green Fact and a yellow one; "protruding from both sides": upper leaf and
  lower leaf). The producer and each checker (by `reviewer`) are compared
  per use, as sets of categories: they **agree** when every checker's set
  is the producer's, or when the producer suggested nothing (no Fact of
  the use has a suggestion) and every checker's set is the same, and every
  Fact of the use has a placement. Format 3 has no checker, so its readers never agree.

  ## The rules

  By the term's standing in the term table (`Gallformers.Catalog.get_term/2`):

    * **placed** — the Facts go on its categories (one Fact per category:
      a term naming several values writes one for each, even when the
      Source's use has one Fact), the Source's term on the attribution. A
      term that is the name of one of the Trait's values
      ("globular") is placed under it. When the producer suggested another
      category, the Fact's statement row is flagged
      `"suggested_other_category"`, with `detail["spot_check"]`
      (`%{"trait", "term", "category", "suggested"}`), for a spot check
      (`Gallformers.Import.list_term_spot_checks/0`).
    * **ambiguous** — a use is written when its readers agree on
      categories (none null); otherwise it is a question.
    * **no_fit** — no Fact: the term is kept as text on the Gall.
    * **new** — when every use in the batch agrees on the same categories
      (one, or the several values the term names) and no reader says it
      depends on the Gall, the term is placed under them for every Source
      when the batch is applied (`placed_by: :agreement`,
      through `Gallformers.Import.record_term_edit/3`, so it replays before
      the batch) and the Facts are written; when every use agrees on no
      category, it is marked as fitting none (by agreement) and kept as
      text. Otherwise every use is a question.

  Resolving changes nothing: placements by agreement, Facts and waiting
  terms are written when the batch is applied (`apply_plan/3`).

  ## Questions

  The uses that are questions are one `:trait_term` queue item per Trait
  and normalized term within a batch (`queue_items/3`), its
  `statement_ref` `"u:<trait>:<normalized term>"` (`statement_ref/2`),
  never holding approval. Its `subject`:

      %{"trait", "term" (the first use's, as written), "normalized_term",
        "status" => "new" | "ambiguous", "candidates" (an ambiguous term's),
        "format_version",
        "covers" => [%{"gall" => ref | nil, "name_as_written", "term",
                       "facts" => [refs], "evidence" => [quotes],
                       "suggestions" => [the producer's category | nil, per Fact],
                       "depends_on_gall" => the producer says so,
                       "placements" => [%{"reviewer", "category", "depends_on_gall", "reason"}],
                       "findings" => [checker findings the producer disputed: format 3's,
                                      and format 4 disputes taken in, `absorb_disputes/2`],
                       "note" => a set-aside entry's note, "position"}]}

  and its proposal `%{"category" => c}` when the producer and the checkers
  agree on `c` for every Gall it covers (a term they say depends on the
  Gall), else none.

  ## Decisions (`choices/1`, carried out by `change_term/2` and the import)

  | Decision | Does |
  |---|---|
  | `%{"place" => c}` or `%{"place" => [c1, c2]}` | places the term under `c` for every Source, or under each value its words name (a new term, or one fitting none); every waiting use of it, in every Source, gets its Fact for each |
  | `%{"category" => c}` | `c` for these Galls only; the term becomes ambiguous, `c` among its candidates |
  | `%{"categories" => %{gall_ref => c \\| [c1, c2] \\| nil}}` | per Gall: each covered Gall (every one, by its ref in the batch) under its own category or categories, or kept as text (nil); the term becomes ambiguous, the categories chosen among its candidates. The same values for every Gall of a new term (or one fitting none) are recorded as `place` (`remembered/2`) |
  | `%{"no_fit" => true}` | marks a new term as fitting no category (counted for superadmins); every waiting use stays text |
  | `%{"keep" => true}` | these uses stay text; the term is left as it is |

  At apply a decided item's decision is the outcome of its uses; a
  question still open stores each use as a waiting term
  (`Gallformers.Catalog.put_pending_term/2`, linked to the item). A use
  kept as text is a waiting term settled with no category: both are shown
  on the Gall's page as text, and neither reaches the ID tool. A use
  whose Fact waits on an open dispute is stored so too, linked to the
  dispute (`store_disputed/3`).
  """

  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Catalog.Vocab.TraitTermMapping
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Import.Disputes
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.VocabEdits

  @kind :trait_term

  # Longer normalized terms are shortened in the ref, with a hash to keep it unique.
  @max_term_bytes 200

  @typedoc "One Fact (or set-aside entry) using a term."
  @type fact :: %{
          ref: String.t(),
          gall: String.t() | nil,
          trait: String.t(),
          term: String.t(),
          suggestion: String.t() | nil,
          depends_on_gall: boolean(),
          stance: String.t(),
          evidence: [map()],
          placements: [map()],
          findings: [map()],
          note: String.t() | nil,
          position: non_neg_integer()
        }

  @typedoc "A Gall's use of a term for a Trait: its Facts with that term."
  @type use :: %{
          gall: String.t() | nil,
          name_as_written: String.t() | nil,
          trait: String.t(),
          term: String.t(),
          normalized: String.t(),
          facts: [fact()],
          position: non_neg_integer()
        }

  @doc """
  A term question's ref (`"u:<trait>:<normalized term>"`, a Trait term's or
  a set-aside's) as `statement_ref/2` makes it now, from one logged with an
  older normalization (before plurals were folded, `c8c3`). A shortened
  ref (its term hashed) and any other ref are returned as they are.
  """
  @spec current_ref(String.t() | nil) :: String.t() | nil
  def current_ref("u:" <> rest = ref) do
    case String.split(rest, ":", parts: 2) do
      [trait, term] -> if String.contains?(term, "#"), do: ref, else: statement_ref(trait, term)
      _ -> ref
    end
  end

  def current_ref(ref), do: ref

  @doc "The kind of queue item for a question about a term."
  @spec kind() :: QueueItem.kind()
  def kind, do: @kind

  @doc "The statement ref of the question about `term` for `trait`."
  @spec statement_ref(String.t(), String.t()) :: String.t()
  def statement_ref(trait, term) do
    normalized = TraitTermMapping.normalize(term)

    term_part =
      if byte_size(normalized) <= @max_term_bytes do
        normalized
      else
        hash = :crypto.hash(:sha256, normalized) |> Base.encode16(case: :lower)
        String.slice(normalized, 0, 100) <> "#" <> binary_part(hash, 0, 12)
      end

    "u:#{trait}:#{term_part}"
  end

  # -- uses ----------------------------------------------------------------------

  @doc """
  The uses of Trait terms in `content` (a decoded batch), in batch order,
  with the checkers' placements from `review` (decoded `review.json`, or
  nil). Options: `:file` (the batch's file, default `"gall.json"`), `:drop`
  (Fact refs a curator dropped).
  """
  @spec uses(map(), map() | nil, keyword()) :: [use()]
  def uses(content, review \\ nil, opts \\ []) do
    file = Keyword.get(opts, :file, "gall.json")
    drop = MapSet.new(Keyword.get(opts, :drop, []))
    v4? = format(content) >= 4
    placements = if v4?, do: placements(review), else: %{}
    findings = if v4?, do: %{}, else: findings(review, file)
    names = Map.new(List.wrap(content["galls"]), &{&1["ref"], &1["name_as_written"]})
    stated = List.wrap(content["facts"])

    facts =
      for {%{"kind" => "trait", "trait" => trait} = f, i} <- Enum.with_index(stated),
          is_binary(trait),
          not MapSet.member?(drop, f["id"]),
          term = fact_term(f),
          present?(term) do
        %{
          ref: f["id"],
          gall: f["gall"],
          trait: trait,
          term: term,
          suggestion: suggestion(f),
          depends_on_gall: f["depends_on_gall"] == true,
          stance: f["stance"] || "confirm",
          evidence: List.wrap(f["evidence"]),
          placements: Map.get(placements, f["id"], []),
          findings: Map.get(findings, f["id"], []),
          note: nil,
          position: i
        }
      end

    (facts ++ set_aside(content, length(stated)))
    |> Enum.group_by(&{&1.gall, &1.trait, TraitTermMapping.normalize(&1.term)})
    |> Enum.map(fn {{gall, trait, normalized}, facts} ->
      [first | _] = facts = Enum.sort_by(facts, & &1.position)

      %{
        gall: gall,
        name_as_written: gall && names[gall],
        trait: trait,
        term: first.term,
        normalized: normalized,
        facts: facts,
        position: first.position
      }
    end)
    |> Enum.sort_by(& &1.position)
  end

  # A format 3 producer's Trait terms set aside: one per Trait, term and
  # Gall, its quotes gathered.
  defp set_aside(content, offset) do
    content
    |> Map.get("unmapped")
    |> List.wrap()
    |> Enum.with_index(offset)
    |> Enum.filter(fn {e, _i} ->
      is_map(e) and e["slot"] in TraitValue.traits() and present?(e["term"])
    end)
    |> Enum.group_by(fn {e, _i} -> "#{statement_ref(e["slot"], e["term"])}@#{e["gall"]}" end)
    |> Enum.map(fn {ref, [{e, i} | _] = entries} ->
      %{
        ref: ref,
        gall: e["gall"],
        trait: e["slot"],
        term: e["term"],
        suggestion: nil,
        depends_on_gall: false,
        stance: "confirm",
        evidence: Enum.flat_map(entries, fn {entry, _i} -> List.wrap(entry["evidence"]) end),
        placements: [],
        findings: [],
        note: e["note"],
        position: i
      }
    end)
  end

  defp format(content) do
    case content["format_version"] do
      n when is_integer(n) -> n
      _ -> 3
    end
  end

  defp present?(term), do: is_binary(term) and String.trim(term) != ""

  defp fact_term(%{"term" => term}), do: term
  defp fact_term(f), do: get_in(f, ["value", "as_written"]) || get_in(f, ["value", "value"])

  defp suggestion(%{"term" => _} = f), do: category(f["category"])
  defp suggestion(f), do: get_in(f, ["value", "value"])

  defp category(%{"value" => value}) when is_binary(value), do: value
  defp category(_category), do: nil

  # The checkers' placements by Fact ref.
  defp placements(%{"placements" => placements}) when is_list(placements) do
    for %{"id" => id} = p <- placements, reduce: %{} do
      acc ->
        placement =
          compact(%{
            "reviewer" => p["reviewer"],
            "category" => category(p["category"]),
            "depends_on_gall" => p["depends_on_gall"] == true,
            "reason" => p["reason"]
          })

        Map.update(acc, id, [placement], &(&1 ++ [placement]))
    end
  end

  defp placements(_review), do: %{}

  # Format 3: the checker's findings on Facts that the producer disputed.
  defp findings(%{"findings" => findings}, file) when is_list(findings) do
    findings
    |> Enum.filter(
      &(is_map(&1) and &1["batch"] == file and get_in(&1, ["response", "decision"]) == "disagree")
    )
    |> Enum.group_by(
      & &1["id"],
      &Map.take(&1, ["problem", "reason", "summary", "suggestion", "reviewer", "response"])
    )
  end

  defp findings(_review, _file), do: %{}

  defp compact(map), do: map |> Enum.reject(fn {_k, v} -> v in [nil, false] end) |> Map.new()

  # -- the rules -------------------------------------------------------------------

  @doc """
  The outcome of each use of `content` (`uses/3` options; `:items`,
  the batch's `:trait_term` items: a decided one's decision is the outcome
  of its uses; `:values`, a curator's values for a Trait Fact by its ref,
  `Gallformers.Import.FactEdits`: its use's outcome), and the term changes applying it makes (placements and
  no-fits by agreement). Each use gains `item_ref` (its question's ref),
  `standing` and `outcome`: `{:facts, categories}`, `:text` or
  `:question`; and `spot`, the producer's other suggestions for a placed
  term.
  """
  @spec plan(map(), map() | nil, keyword()) :: %{uses: [map()], edits: [VocabEdits.term_edit()]}
  def plan(content, review, opts \\ []) do
    decided =
      for %QueueItem{kind: @kind, status: :decided} = q <- Keyword.get(opts, :items, []),
          into: %{},
          do: {q.statement_ref, q.decision}

    values = Catalog.list_trait_values() |> Enum.group_by(& &1.trait, & &1.value)

    {uses, edits} =
      content
      |> uses(review, opts)
      |> Enum.group_by(&statement_ref(&1.trait, &1.normalized))
      |> Enum.map(fn {ref, uses} -> plan_term(ref, uses, decided[ref], values) end)
      |> Enum.unzip()

    edited = Keyword.get(opts, :values, %{})

    uses =
      uses
      |> List.flatten()
      |> Enum.map(&edited(&1, edited))
      |> Enum.sort_by(& &1.position)

    %{uses: uses, edits: List.flatten(edits)}
  end

  # A use a curator gave other values (`Gallformers.Import.FactEdits`, by
  # the ref of one of its Facts): its Facts go on them.
  defp edited(use, edited) when map_size(edited) == 0, do: use

  defp edited(use, edited) do
    case Enum.find_value(use.facts, &Map.get(edited, &1.ref)) do
      nil -> use
      values -> %{use | outcome: {:facts, values}, spot: nil}
    end
  end

  defp plan_term(ref, [first | _] = uses, decision, values) do
    standing = standing(first, values)
    uses = Enum.map(uses, &Map.merge(&1, %{item_ref: ref, standing: standing, spot: nil}))

    case decision do
      %{"place" => c} -> {outcome(uses, {:facts, TraitTermMapping.categories(c)}), []}
      %{"category" => c} -> {outcome(uses, {:facts, [c]}), []}
      %{"categories" => by_gall} -> {Enum.map(uses, &per_gall(&1, by_gall)), []}
      %{"no_fit" => true} -> {outcome(uses, {:text, :no_fit}), []}
      %{} -> {outcome(uses, {:text, :kept}), []}
      nil -> by_standing(standing, uses)
    end
  end

  defp outcome(uses, outcome), do: Enum.map(uses, &Map.put(&1, :outcome, outcome))

  # A use under a per-Gall decision: its Gall's categories, else text.
  defp per_gall(use, by_gall) do
    case TraitTermMapping.categories(Map.get(by_gall, use.gall)) do
      [] -> Map.put(use, :outcome, {:text, :kept})
      categories -> Map.put(use, :outcome, {:facts, categories})
    end
  end

  # The term's standing: {:placed, categories}, :ambiguous, :no_fit or :new.
  defp standing(use, values) do
    case Catalog.get_term(use.trait, use.term) do
      %{status: :placed, categories: categories} ->
        {:placed, categories}

      %{status: status} ->
        status

      nil ->
        case Enum.find(Map.get(values, use.trait, []), &(normalize(&1) == use.normalized)) do
          nil -> :new
          value -> {:placed, [value]}
        end
    end
  end

  defp normalize(value), do: TraitTermMapping.normalize(value)

  defp by_standing({:placed, categories}, uses) do
    {Enum.map(uses, &Map.merge(&1, %{outcome: {:facts, categories}, spot: spot(&1, categories)})),
     []}
  end

  defp by_standing(:no_fit, uses), do: {outcome(uses, {:text, :no_fit}), []}

  defp by_standing(:ambiguous, uses) do
    {Enum.map(uses, fn use ->
       case agreement(use) do
         {:agree, categories, _depends?} when categories != [] ->
           if nil in categories,
             do: Map.put(use, :outcome, :question),
             else: Map.put(use, :outcome, {:facts, categories})

         _ ->
           Map.put(use, :outcome, :question)
       end
     end), []}
  end

  defp by_standing(:new, [first | _] = uses) do
    agreed = uses |> Enum.map(&agreement/1) |> Enum.uniq()

    case agreed do
      [{:agree, [nil], false}] ->
        {outcome(uses, {:text, :no_fit}), [{:mark_no_fit, first.trait, first.term, :agreement}]}

      [{:agree, [_ | _] = categories, false}] ->
        if Enum.all?(categories, &is_binary/1),
          do:
            {outcome(uses, {:facts, categories}),
             [{:place, first.trait, first.term, placement(categories), :agreement}]},
          else: {outcome(uses, :question), []}

      _ ->
        {outcome(uses, :question), []}
    end
  end

  # One category as itself, several as the set.
  defp placement([category]), do: category
  defp placement(categories), do: categories

  @doc """
  Whether a use's readers agree: `{:agree, categories, depends_on_gall?}`
  (the categories in the order the producer gave them, or the first
  checker's when the producer suggested none; nil for none), `:disagree`,
  or `:none` when a Fact has no checker placement.

  The producer is silent on a use when no Fact of it has a suggestion; then
  the checkers agree among themselves, every checker's set the same, and a
  checker naming another value is a disagreement. Agreeing on a value then
  takes at least two checkers; a single checker's value is no agreement.
  """
  @spec agreement(use()) ::
          {:agree, [String.t() | nil], boolean()} | :disagree | :none
  def agreement(use) do
    producer = Enum.map(use.facts, & &1.suggestion)
    placements = Enum.flat_map(use.facts, & &1.placements)

    depends? =
      Enum.any?(use.facts, & &1.depends_on_gall) or
        Enum.any?(placements, &(&1["depends_on_gall"] == true))

    readers = Enum.group_by(placements, & &1["reviewer"], & &1["category"])
    [first | _] = Map.values(readers) ++ [[]]

    # A silent producer gives way to the checkers: the first checker's answer
    # stands when every checker gave it, and a value needs two checkers.
    silent? = Enum.all?(producer, &is_nil/1)
    agreed = if silent?, do: first, else: producer
    lone? = silent? and map_size(readers) < 2 and Enum.any?(agreed, &is_binary/1)

    cond do
      Enum.any?(use.facts, &(&1.placements == [])) -> :none
      lone? -> :disagree
      Enum.all?(Map.values(readers), &same?(&1, agreed)) -> {:agree, Enum.uniq(agreed), depends?}
      true -> :disagree
    end
  end

  defp same?(categories, others), do: MapSet.new(categories) == MapSet.new(others)

  # A placed term's use: what the producer suggested other than its categories.
  defp spot(use, categories) do
    suggested =
      for %{suggestion: s} <- use.facts, is_binary(s), s not in categories, uniq: true, do: s

    if suggested != [],
      do: %{"trait" => use.trait, "term" => use.term, "suggested" => suggested}
  end

  # -- questions -------------------------------------------------------------------

  @doc """
  The questions `content` calls for (`plan/3`'s options): one item per
  Trait and normalized term whose uses are questions, in batch order.
  """
  @spec queue_items(map(), map() | nil, keyword()) :: [map()]
  def queue_items(content, review, opts \\ []) do
    %{uses: uses} = plan(content, review, opts)

    uses
    |> Enum.filter(&(&1.outcome == :question))
    |> Enum.group_by(& &1.item_ref)
    |> Enum.sort_by(fn {_ref, [first | _]} -> first.position end)
    |> Enum.map(&item(&1, format(content)))
  end

  defp item({ref, [first | _] = uses}, format) do
    candidates =
      case Catalog.get_term(first.trait, first.term) do
        %{status: :ambiguous, candidates: candidates} -> candidates
        _ -> []
      end

    status = if first.standing == :ambiguous, do: "ambiguous", else: "new"

    %{
      kind: @kind,
      statement_ref: ref,
      subject: %{
        "trait" => first.trait,
        "term" => first.term,
        "normalized_term" => first.normalized,
        "status" => status,
        "candidates" => candidates,
        "format_version" => format,
        "covers" => Enum.map(uses, &cover/1)
      },
      proposal: proposal(uses),
      reason: reason(status, first)
    }
  end

  defp cover(use) do
    %{
      "gall" => use.gall,
      "name_as_written" => use.name_as_written,
      "term" => use.term,
      "facts" => Enum.map(use.facts, & &1.ref),
      "evidence" => Enum.flat_map(use.facts, & &1.evidence),
      "suggestions" => Enum.map(use.facts, & &1.suggestion),
      "depends_on_gall" => Enum.any?(use.facts, & &1.depends_on_gall),
      "placements" => Enum.flat_map(use.facts, & &1.placements),
      "findings" => Enum.flat_map(use.facts, & &1.findings),
      "note" => Enum.find_value(use.facts, & &1.note),
      "position" => use.position
    }
  end

  # The category the readers agree on for every Gall, when one.
  defp proposal(uses) do
    case uses |> Enum.map(&agreement/1) |> Enum.uniq() do
      [{:agree, [category], _depends?}] when is_binary(category) -> %{"category" => category}
      _ -> %{}
    end
  end

  defp reason("ambiguous", use),
    do:
      "\"#{use.term}\" is an ambiguous #{use.trait} term and the readers didn't agree on its " <>
        "category for these Galls; until settled they show it without one"

  defp reason("new", use),
    do:
      "\"#{use.term}\" is a new #{use.trait} term the readers didn't place alike; until " <>
        "settled the Galls show it without a category"

  # -- applying --------------------------------------------------------------------

  @doc """
  What applying `content` writes for its Trait terms (`plan/3`'s options):
  `facts`, trait Facts in the contract's shape for the batch's Fact writer
  (`"value"` the category, `"term"` the Source's term, `"spot_check"` the
  spot-check detail); `unwritten`, `{ref, reason}` for the Facts that are
  not; `waiting`, the uses to store as waiting terms (`text` `:no_fit` or
  `:kept`: settled as text, and why; `false`: waiting on a question); and
  `edits`, the term changes to make first.
  """
  @spec apply_plan(map(), map() | nil, keyword()) :: %{
          facts: [map()],
          unwritten: [{String.t(), String.t()}],
          waiting: [%{use: map(), text: false | :no_fit | :kept}],
          edits: [VocabEdits.term_edit()]
        }
  def apply_plan(content, review, opts \\ []) do
    %{uses: uses, edits: edits} = plan(content, review, opts)
    acc = %{facts: [], unwritten: [], waiting: [], edits: edits}
    Enum.reduce(uses, acc, &apply_use(&1.outcome, &1, &2))
  end

  defp apply_use({:facts, categories}, use, acc) do
    {written, left} = facts(use, categories)
    first = written |> List.first() |> Map.get("id")

    %{
      acc
      | facts: acc.facts ++ written,
        unwritten: acc.unwritten ++ for(f <- left, do: {f.ref, "same term as #{first}"})
    }
  end

  defp apply_use(outcome, use, acc) do
    reason =
      if outcome == :question,
        do: "waiting on a question about its term \"#{use.term}\"",
        else: "its term \"#{use.term}\" is kept as text"

    %{
      acc
      | unwritten: acc.unwritten ++ for(f <- use.facts, do: {f.ref, reason}),
        waiting: acc.waiting ++ [%{use: use, text: text_reason(outcome)}]
    }
  end

  defp text_reason({:text, why}), do: why
  defp text_reason(_outcome), do: false

  @doc """
  The trait Facts (the contract's shape) a waiting use with Fact `ref` in
  `content` gets under `categories`, one each (one value, or a list); none
  for nil or `[]`.
  """
  @spec facts_for(map(), String.t(), String.t() | [String.t()] | nil) :: [map()]
  def facts_for(content, ref, categories) do
    case {TraitTermMapping.categories(categories),
          Enum.find(uses(content), fn use -> Enum.any?(use.facts, &(&1.ref == ref)) end)} do
      {[], _use} -> []
      {_categories, nil} -> []
      {categories, use} -> use |> facts(categories) |> elem(0)
    end
  end

  # The Facts `use` writes under `categories`: one per category, each from
  # the Fact suggesting it, else the next not used, else the first again
  # under a ref of its own. Also the Facts left over.
  defp facts(use, categories) do
    {pairs, left} =
      Enum.reduce(categories, {[], use.facts}, fn category, {pairs, left} ->
        case Enum.find(left, &(&1.suggestion == category)) || List.first(left) do
          nil ->
            base = hd(use.facts)
            {[{%{base | ref: "#{base.ref}+#{category}"}, category} | pairs], left}

          fact ->
            {[{fact, category} | pairs], List.delete(left, fact)}
        end
      end)

    {pairs |> Enum.reverse() |> Enum.map(fn {f, c} -> fact(use, f, c) end), left}
  end

  defp fact(use, f, category) do
    fact = %{
      "id" => f.ref,
      "kind" => "trait",
      "stance" => f.stance,
      "gall" => use.gall,
      "trait" => use.trait,
      "value" => %{"value" => category, "as_written" => f.term},
      "term" => f.term,
      "evidence" => f.evidence
    }

    case use[:spot] do
      nil -> fact
      spot -> Map.put(fact, "spot_check", Map.put(spot, "category", category))
    end
  end

  @doc """
  Stores the `waiting` uses of `apply_plan/3` for the batch being applied
  (`ctx`: `:actor`, `:source`, `:batch`, and `:term_items`, the batch's
  `:trait_term` items) on their Galls (`galls`, ref to ID; a use whose Gall
  is not resolved is skipped), each linked to its question.
  """
  @spec store_waiting(map(), [map()], %{String.t() => integer()}) :: :ok | {:error, term()}
  def store_waiting(ctx, waiting, galls) do
    items = Map.new(Map.get(ctx, :term_items, []), &{&1.statement_ref, &1.id})

    Enum.reduce_while(waiting, :ok, fn %{use: use, text: text?}, :ok ->
      case store(ctx, use, text?, galls[use.gall], items[use.item_ref]) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp store(_ctx, _use, _text?, nil, _item_id), do: {:ok, nil}

  defp store(ctx, use, text?, gall_id, item_id) do
    attrs = %{
      gall_id: gall_id,
      source_id: ctx.source.id,
      package_id: ctx.batch.package_id,
      batch_id: ctx.batch.id,
      queue_item_id: item_id,
      statement_ref: hd(use.facts).ref,
      trait: use.trait,
      term: use.term,
      evidence: Enum.flat_map(use.facts, & &1.evidence)
    }

    with {:ok, pending} <- Catalog.put_pending_term(ctx.actor, attrs) do
      if text?,
        do:
          Catalog.settle_pending_terms(ctx.actor, use.trait, use.term, nil,
            gall_ids: [gall_id],
            source_id: ctx.source.id,
            as: text?
          ),
        else: {:ok, pending}
    end
  end

  @doc """
  Stores, for the batch being applied (`ctx` as for `store_waiting/3`,
  with `:review`), the uses whose Facts wait on an open dispute
  (`disputes`, the batch's open Trait disputes,
  `Gallformers.Import.Disputes`) as waiting terms on their Galls (`galls`,
  ref to ID), each linked to its dispute: the Gall's page shows the
  Source's words meanwhile. Kept, the dispute writes the Facts and settles
  the term; dropped, it settles the term as text.
  """
  @spec store_disputed(map(), [QueueItem.t()], %{String.t() => integer()}) ::
          :ok | {:error, term()}
  def store_disputed(_ctx, [], _galls), do: :ok

  def store_disputed(ctx, disputes, galls) do
    content = ctx.batch.content
    by_ref = for d <- disputes, ref <- Disputes.refs(d), into: %{}, do: {ref, d.id}
    others = for f <- List.wrap(content["facts"]), not Map.has_key?(by_ref, f["id"]), do: f["id"]

    content
    |> uses(Map.get(ctx, :review), file: ctx.batch.file, drop: others)
    |> Enum.filter(fn use -> Enum.all?(use.facts, &Map.has_key?(by_ref, &1.ref)) end)
    |> Enum.reduce_while(:ok, fn use, :ok ->
      case store(ctx, use, false, galls[use.gall], by_ref[hd(use.facts).ref]) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc "Makes the term changes of `apply_plan/3` (`edits`), each recorded for replay."
  @spec record_edits(Actor.t(), [VocabEdits.term_edit()]) :: :ok | {:error, term()}
  def record_edits(actor, edits) do
    Enum.reduce_while(edits, :ok, fn edit, :ok ->
      case VocabEdits.record_term_edit(actor, edit) do
        {:ok, _term} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  One question per statement (`c8c3`): a Trait dispute
  (`Gallformers.Import.Disputes.trait?/1`) about a Fact one of `terms`
  (`queue_items/3`) covers, and about no other batch's statement, is asked
  as that term's question: its findings join the use's `"findings"`, and
  it has no item of its own. A question with a disputed use proposes
  nothing, however its readers placed it. Returns `{terms, disputes}`, the
  disputes less those taken in.
  """
  @spec absorb_disputes([map()], [map()]) :: {[map()], [map()]}
  def absorb_disputes(terms, disputes) do
    covered =
      for t <- terms, cover <- t.subject["covers"], ref <- List.wrap(cover["facts"]), into: %{} do
        {ref, t.statement_ref}
      end

    {absorbed, kept} =
      Enum.split_with(disputes, fn d ->
        Disputes.trait?(d) and Map.has_key?(covered, d.statement_ref) and
          List.wrap(d.subject["also"]) == []
      end)

    findings = Map.new(absorbed, &{&1.statement_ref, List.wrap(&1.subject["findings"])})
    {Enum.map(terms, &take_findings(&1, findings)), kept}
  end

  defp take_findings(term, findings) do
    covers =
      for cover <- term.subject["covers"] do
        case Enum.flat_map(List.wrap(cover["facts"]), &Map.get(findings, &1, [])) do
          [] -> cover
          more -> Map.update(cover, "findings", more, &(List.wrap(&1) ++ more))
        end
      end

    disputed? = covers != term.subject["covers"]

    %{
      term
      | subject: Map.put(term.subject, "covers", covers),
        proposal: if(disputed?, do: %{}, else: term.proposal)
    }
  end

  # -- deciding ------------------------------------------------------------------

  @doc """
  The choices a question allows, as `{key, check}`
  (`Gallformers.Import.Queue.validate_decision/3`): placing for every
  Source (under a value, or a list of the values the term names, none
  twice) and marking as fitting none are for a new term (or one fitting
  none); an ambiguous term is decided per use.
  """
  @spec choices(QueueItem.t()) :: [{String.t(), (term() -> boolean())}]
  def choices(%QueueItem{subject: %{"trait" => trait, "term" => term}} = item) do
    status =
      case Catalog.get_term(trait, term) do
        nil -> :new
        %{status: status} -> status
      end

    value? = &(is_binary(&1) and Catalog.get_trait_value(trait, &1) != nil)

    [
      {"keep", &(&1 == true)},
      {"category", &(value?.(&1) and status in [:new, :ambiguous] and galls?(item))},
      {"categories", &(status in [:new, :ambiguous] and per_gall?(item, &1, value?))},
      {"place", &(placement?(&1, value?) and status in [:new, :no_fit])},
      {"no_fit", &(&1 == true and status in [:new, :no_fit])}
    ]
  end

  def choices(_item), do: [{"keep", &(&1 == true)}]

  defp galls?(item), do: covered_galls(item) != []

  # A value of the Trait, or values of it, at least one and none twice.
  defp placement?([_ | _] = categories, value?),
    do: Enum.all?(categories, value?) and Enum.uniq(categories) == categories

  defp placement?(category, value?), do: value?.(category)

  # A category, or several, (or nil, text) for every Gall the question
  # covers, and no other.
  defp per_gall?(item, by_gall, value?) when is_map(by_gall) and map_size(by_gall) > 0 do
    Enum.sort(Map.keys(by_gall)) == Enum.sort(covered_galls(item)) and
      Enum.all?(Map.values(by_gall), &(is_nil(&1) or placement?(&1, value?)))
  end

  defp per_gall?(_item, _by_gall, _value?), do: false

  @doc "The refs of the Galls a question covers, in order."
  @spec covered_galls(QueueItem.t()) :: [String.t()]
  def covered_galls(%QueueItem{subject: subject}) do
    for %{"gall" => gall} <- List.wrap(subject["covers"]), is_binary(gall), uniq: true, do: gall
  end

  @doc """
  The decision a curator's answer `decision` to question `item` is
  recorded as (`c8c3`): per-Gall values (`"categories"`) that are the same
  for every Gall it covers, of a new term or one fitting none, place the
  term under them for every Source (`"place"`), so no later Source asks
  again. Answers that differ by Gall ("it depends on the Gall") place
  nothing, nor does any answer for an ambiguous term. Anything else is
  `decision` itself.
  """
  @spec remembered(QueueItem.t(), map()) :: map()
  def remembered(
        %QueueItem{kind: @kind, subject: %{"trait" => trait, "term" => term}} = item,
        %{"categories" => by_gall} = decision
      )
      when is_map(by_gall) do
    sets =
      for gall <- covered_galls(item),
          do: by_gall |> Map.get(gall) |> TraitTermMapping.categories() |> Enum.sort()

    standing = Catalog.get_term(trait, term)

    case Enum.uniq(sets) do
      [[_ | _]] when standing == nil or standing.status == :no_fit ->
        ordered = by_gall |> Map.get(hd(covered_galls(item))) |> TraitTermMapping.categories()

        decision
        |> Map.delete("categories")
        |> Map.put("place", placement(ordered))

      _ ->
        decision
    end
  end

  def remembered(_item, decision), do: decision

  @doc """
  Changes the term as the question's decision says (`decision`): places it
  for every Source (`place`, by a curator: under a value, or each of the
  values it names), marks it ambiguous with the
  category among its candidates, with the readers' (`category`), or as
  fitting none (`no_fit`). `keep` changes nothing. The queue decision is
  what the replay log records.
  """
  @spec change_term(Actor.t(), QueueItem.t()) ::
          {:ok, TraitTermMapping.t() | nil} | {:error, term()}
  def change_term(%Actor{} = actor, %QueueItem{subject: subject, decision: decision} = item) do
    trait = subject["trait"]
    term = subject["term"]

    case decision do
      %{"place" => c} ->
        Catalog.place_term(actor, trait, term, c, :curator)

      %{"no_fit" => true} ->
        Catalog.mark_term_no_fit(actor, trait, term, :curator)

      %{"category" => c} ->
        ambiguous(actor, item, Catalog.get_term(trait, term), [c])

      %{"categories" => by_gall} ->
        case by_gall
             |> Map.values()
             |> Enum.flat_map(&TraitTermMapping.categories/1)
             |> Enum.uniq() do
          [] -> {:ok, Catalog.get_term(trait, term)}
          chosen -> ambiguous(actor, item, Catalog.get_term(trait, term), chosen)
        end

      _keep ->
        {:ok, nil}
    end
  end

  # The term ambiguous, with the `chosen` categories among its candidates.
  defp ambiguous(
         actor,
         %QueueItem{subject: %{"trait" => trait, "term" => term}} = item,
         nil,
         chosen
       ),
       do: Catalog.mark_term_ambiguous(actor, trait, term, candidates(item, chosen), :curator)

  defp ambiguous(actor, item, %{status: :ambiguous, candidates: candidates} = t, chosen) do
    case chosen -- candidates do
      [] ->
        {:ok, t}

      more ->
        Catalog.mark_term_ambiguous(
          actor,
          item.subject["trait"],
          item.subject["term"],
          candidates ++ more,
          :curator
        )
    end
  end

  defp ambiguous(_actor, _item, t, _chosen), do: {:ok, t}

  # The `chosen` categories and those the readers gave, values of the Trait.
  defp candidates(%QueueItem{subject: subject}, chosen) do
    trait = subject["trait"]

    read =
      for cover <- List.wrap(subject["covers"]),
          c <-
            List.wrap(cover["suggestions"]) ++
              Enum.map(List.wrap(cover["placements"]), & &1["category"]),
          is_binary(c),
          do: c

    (chosen ++ read)
    |> Enum.uniq()
    |> Enum.filter(&(Catalog.get_trait_value(trait, &1) != nil))
  end

  @doc "The categories a decision settles its uses under (`[]`: as text)."
  @spec settled_categories(map()) :: [String.t()]
  def settled_categories(%{"place" => c}), do: TraitTermMapping.categories(c)
  def settled_categories(%{"category" => c}), do: TraitTermMapping.categories(c)
  def settled_categories(_decision), do: []

  @doc """
  How a question's decision settles its waiting uses: `[{categories, fact
  refs | :all}]` (no categories: as text). A per-Gall decision
  (`"categories"`) settles each covered Gall's use (by its first Fact's
  ref, as a waiting term stores it) under that Gall's category; every
  other decision settles them all under `settled_categories/1`.
  """
  @spec settlements(QueueItem.t()) :: [{[String.t()], [String.t()] | :all}]
  def settlements(%QueueItem{decision: %{"categories" => by_gall}, subject: subject}) do
    subject
    |> Map.get("covers")
    |> List.wrap()
    |> Enum.filter(&is_binary(&1["gall"]))
    |> Enum.group_by(
      &TraitTermMapping.categories(Map.get(by_gall, &1["gall"])),
      &List.first(List.wrap(&1["facts"]))
    )
    |> Enum.map(fn {categories, refs} -> {categories, Enum.reject(refs, &is_nil/1)} end)
    |> Enum.sort()
  end

  def settlements(%QueueItem{decision: decision}), do: [{settled_categories(decision), :all}]

  @doc "Whether the decision settles every Source's waiting uses of the term (placing it, or fitting none)."
  @spec every_source?(map()) :: boolean()
  def every_source?(decision),
    do: Map.has_key?(decision, "place") or Map.get(decision, "no_fit") == true
end
