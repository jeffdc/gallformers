defmodule GallformersWeb.Admin.Review.Units do
  @moduledoc """
  A Source's review as units of work, shown one at a time (matter `6611`,
  the build's Task 3). Every count on the review page comes from `tally/1`,
  so no two of them can disagree.

  A unit is one of:

    * `{:batch, section, entries}`: a section's firm suggestions, two or
      more, to look over and accept together. An entry the curator has
      unticked stays listed in the batch and also comes next on its own.
    * `{:one, section, entry}`: one question.
    * `:facts`: what approving will add, the last step before Approve.

  The units run in the steps' order (Names, Galls, Disputes, Traits), a
  question about the Source itself ("Which Source this is") first,
  each step's sections in order and each section's entries as given; a
  chosen stage's units come first; skipped units come last, before the
  Facts, in the order they were skipped. The hedged statements (the Hedges
  step's sections) are not units: they stay out unless the curator states
  one, and are counted apart.

  Entries are as `GallformersWeb.Admin.ReviewLive.Loader.entries/3` shapes
  them; only `item.id`, `item.status`, `question.section`,
  `question.proposal`, `holds` and `rejected` are read.
  """

  alias GallformersWeb.Admin.Review.Steps

  @typedoc "A unit of work."
  @type unit :: {:batch, map(), [map()]} | {:one, map(), map()} | :facts

  @typedoc "What is answered and left, and what must be answered before approving."
  @type tally :: %{
          done: non_neg_integer(),
          left: non_neg_integer(),
          total: non_neg_integer(),
          holding: non_neg_integer(),
          hedged: non_neg_integer()
        }

  @typedoc "A stage (a step) of the review, with what is left in it."
  @type stage :: %{
          id: atom(),
          title: String.t(),
          state: :current | :todo | :done,
          left: non_neg_integer()
        }

  @hedges Enum.find(Steps.all(), &(&1.id == :hedges)).sections

  @doc "The questions answered and to go (hedged statements apart)."
  @spec tally([map()]) :: tally()
  def tally(entries) do
    {hedged, questions} = Enum.split_with(entries, &hedged?/1)
    {open, done} = Enum.split_with(questions, &open?/1)

    %{
      done: length(done),
      left: length(open),
      total: length(questions),
      holding: Enum.count(open, & &1.holds),
      hedged: Enum.count(hedged, &open?/1)
    }
  end

  @doc """
  The units in order, the Facts last. Options: `unticked` (a MapSet of item
  IDs taken out of their batch), `skipped` (unit keys, in the order
  skipped), `stage` (a step's id whose units come first).
  """
  @spec units([map()], keyword()) :: [unit()]
  def units(entries, opts \\ []) do
    unticked = Keyword.get(opts, :unticked, MapSet.new())
    skipped = Keyword.get(opts, :skipped, [])
    stage = Keyword.get(opts, :stage)

    units =
      entries
      |> Enum.filter(&(open?(&1) and not hedged?(&1)))
      |> Enum.sort_by(&order/1)
      |> Enum.chunk_by(& &1.question.section.id)
      |> Enum.flat_map(&section_units(&1, unticked))
      |> Enum.sort_by(&(stage != nil and step(&1) != stage))

    {later, now} = Enum.split_with(units, &(key(&1) in skipped))
    now ++ Enum.sort_by(later, &Enum.find_index(skipped, fn k -> k == key(&1) end)) ++ [:facts]
  end

  # A section's firm suggestions as one batch (two or more, at least one
  # still ticked), the unticked ones after it on their own, then the rest.
  defp section_units([first | _] = entries, unticked) do
    section = first.question.section
    {firm, rest} = Enum.split_with(entries, &batchable?/1)
    {out, ticked} = Enum.split_with(firm, &(&1.item.id in unticked))

    batch =
      if length(firm) >= 2 and ticked != [],
        do: [{:batch, section, firm} | Enum.map(out, &{:one, section, &1})],
        else: Enum.map(firm, &{:one, section, &1})

    batch ++ Enum.map(rest, &{:one, section, &1})
  end

  @doc "The units after the current one: three by default."
  @spec next([unit()], pos_integer()) :: [unit()]
  def next(units, n \\ 3), do: units |> Enum.drop(1) |> Enum.take(n)

  @doc "Each stage but the hedged statements, with what is left in it and whether it is current."
  @spec stages([map()], unit() | nil) :: [stage()]
  def stages(entries, current) do
    left =
      entries
      |> Enum.filter(&(open?(&1) and not hedged?(&1)))
      |> Enum.frequencies_by(&Steps.step_of(&1.question.section.id))

    current_step = current && step(current)

    for step <- Steps.all(), step.id != :hedges do
      n = Map.get(left, step.id, 0)

      state =
        cond do
          step.id == current_step -> :current
          n > 0 -> :todo
          true -> :done
        end

      %{id: step.id, title: step.title, state: state, left: n}
    end
  end

  @doc "A unit in one line, for Up next."
  @spec label(unit()) :: String.t()
  def label({:batch, section, entries}),
    do: "#{section.title}: #{length(entries)} suggested answers to look over"

  def label({:one, section, entry}),
    do: "#{section.title}: #{Map.get(entry.question, :written) || entry.question.question}"

  def label(:facts), do: "What approving will add"

  @doc "A unit's key, stable across reloads: for skipping and for the URL."
  @spec key(unit()) :: String.t()
  def key({:batch, section, _entries}), do: "batch-#{section.id}"
  def key({:one, _section, entry}), do: "q-#{entry.item.id}"
  def key(:facts), do: "facts"

  @doc """
  Whether `entry` is a firm suggestion a batch may hold: never one that
  creates a new Gall or answers Gall by Gall, which want a look of their own.
  """
  @spec batchable?(map()) :: boolean()
  def batchable?(entry) do
    case entry.question.proposal do
      %{firm: true, pending: false, decision: decision} ->
        not entry.rejected and not own_look?(decision)

      _ ->
        false
    end
  end

  defp own_look?(%{"new" => true}), do: true
  defp own_look?(%{"categories" => _}), do: true
  defp own_look?(_decision), do: false

  defp step({_kind, section, _}), do: Steps.step_of(section.id)
  defp step(:facts), do: nil

  # The steps' order, then each step's sections in order.
  defp order(entry) do
    section = entry.question.section.id
    step_id = Steps.step_of(section)
    step = Enum.find(Steps.all(), &(&1.id == step_id))

    # A question no step holds is about the Source itself ("Which Source
    # this is"): it comes first.
    case step do
      nil -> {0, 0}
      step -> {step.n, Enum.find_index(step.sections, &(&1 == section))}
    end
  end

  defp open?(entry), do: entry.item.status == :open
  defp hedged?(entry), do: entry.question.section.id in @hedges
end
