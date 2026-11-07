defmodule Gallformers.Facts.Standing do
  @moduledoc """
  The standing rules (`9449` §2; reasons in `8567` *Sources–Facts design*),
  as pure functions: no database, no Source lookups. The caller passes each
  Fact's attributions, with whether each one's Source is retracted, and the
  Fact's previous standing.

  ## A Fact's own standing

  1. Attributions from retracted Sources are ignored. A Fact with
     attributions but none left is `:retracted`; a Fact with no attributions
     at all is `:unsupported`. Attributions that do not count (`counts:
     false`: a Source's taxonomic statement no curator has accepted, or one
     declined, `f923`) are ignored too; a Fact left with none that count is
     `:unsupported`.
  2. The newest `stated_on` decides: a confirmation makes the Fact
     `:current`, a denial `:withdrawn`. Import order never matters.
  3. Partial dates compare at the coarser precision of the two, so `"1897"`
     ties with `"1897-05"` while `"1897-03"` is older than `"1897-08"`. Each
     date is the period it names (a year, a month, a day); one is newer than
     another only when its whole period comes after the other's. The newest
     attributions are those nothing is newer than, and they all tie with
     each other. If they disagree in stance, that is a `:same_date`
     `Gallformers.Facts.Standing.Conflict` and the Fact keeps its previous
     standing until a curator decides.
  4. An undated attribution (`stated_on` nil) sorts before every dated one;
     see `undated_period/0`.

  **No previous standing.** A Fact with no previous standing has never been
  shown, so a conflict leaves it `:unsupported` (hidden) until decided. This
  is also the standing `Gallformers.Facts.create_fact/2` gives a new Fact, so
  a stored Fact behaves the same either way.

  ## Slots

  5. Facts competing for one value share a slot. Among the slot's `:current`
     Facts, the one with the newest confirmation (rule 3's ordering, over all
     their confirmations) stays `:current` and the others become
     `:superseded`. Facts that are not current keep their own standing.

  **Ties in a slot.** When the newest confirmations belong to more than one
  Fact, that is a `:slot_tie` conflict, handled like rule 3: each tied Fact
  keeps its previous standing (`:unsupported` if it has none), and the slot's
  other current Facts are `:superseded`, since something newer outranks them
  either way.

  ## Contests

  6. Facts in different slots (or in none) may contest one thing for
     different holders (`contest`, `holder`): a name as one taxon's
     accepted name (a `:claimant`) or as a synonym of another taxon (a
     `:rival`). A claimant its own statements confirm (rules 1–4: it is
     `:current`, or `:superseded` in its slot by a newer value, as a
     taxon's former name) outranks each `:current` rival held by another
     holder whose newest counting confirmation is older than the
     claimant's newest counting confirmation (older by rule 3: the
     claimant's period comes entirely after): the rival becomes
     `:superseded`. So a claimant confirmed only by undated statements
     outranks nothing, and an undated rival loses to any dated claimant.
     Claimants keep their standing. Matter `f923`, "A revalidated name
     outranks an older synonymy of it": a paper revalidating a name states
     its name, not "N is not a synonym of X".
  """

  alias Gallformers.Facts.Standing.Conflict
  alias Gallformers.Sources.PartialDate

  @type standing :: :current | :withdrawn | :superseded | :retracted | :unsupported
  @type stance :: :confirm | :deny

  @typedoc """
  An attribution as the rules see it. Other keys (an attribution ID, a
  Source ID) are carried through into conflicts untouched.
  """
  @type statement :: %{
          required(:stance) => stance(),
          required(:stated_on) => Date.t() | nil,
          required(:stated_precision) => PartialDate.precision() | nil,
          required(:retracted) => boolean(),
          optional(:counts) => boolean(),
          optional(any()) => any()
        }

  @typedoc """
  A Fact: its ID, its previous standing (nil if it never had one), its
  attributions; for rule 6, the thing it contests (`contest`), for whom
  (`holder`) and its `role` there.
  """
  @type fact :: %{
          required(:id) => term(),
          required(:previous) => standing() | nil,
          required(:attributions) => [statement()],
          optional(:contest) => term() | nil,
          optional(:holder) => term() | nil,
          optional(:role) => :claimant | :rival | nil,
          optional(any()) => any()
        }

  @type result :: {%{term() => standing()}, [Conflict.t()]}

  @typedoc "A date's period, as an inclusive range of Gregorian days."
  @type period :: {integer(), integer()}

  # The Gregorian day before the earliest date Calendar.ISO supports.
  @before_every_date Date.to_gregorian_days(~D[-9999-01-01]) - 1

  @doc """
  The standing of one Fact that is in no slot (rules 1–4).

  Returns `{%{fact_id => standing}, conflicts}`.
  """
  @spec resolve(fact()) :: result()
  def resolve(%{id: id} = fact) do
    {standing, conflicts} = own_standing(fact)
    {%{id => standing}, conflicts}
  end

  @doc """
  The standings of every Fact in one slot (rules 1–5). Pass all of the
  slot's Facts.

  Returns `{%{fact_id => standing}, conflicts}`, with each Fact's own
  `:same_date` conflicts and any `:slot_tie`.
  """
  @spec resolve_slot([fact()]) :: result()
  def resolve_slot(facts) when is_list(facts) do
    owns = Enum.map(facts, fn fact -> {fact, own_standing(fact)} end)

    standings = Map.new(owns, fn {fact, {standing, _}} -> {fact.id, standing} end)
    own_conflicts = Enum.flat_map(owns, fn {_fact, {_standing, conflicts}} -> conflicts end)
    current = for {fact, {:current, _}} <- owns, do: fact

    {standings, slot_conflicts} = settle_slot(current, standings)
    {standings, own_conflicts ++ slot_conflicts}
  end

  @doc """
  Settles contests (rule 6) over `standings`, the standings rules 1–5 gave
  `facts`: each `:current` rival a claimant in its contest outranks
  becomes `:superseded`. Pass every Fact of each contest concerned, with
  its slot siblings settled in `standings`; Facts with no contest are left
  as they are.

  Returns the updated standings.
  """
  @spec settle_contests([fact()], %{term() => standing()}) :: %{term() => standing()}
  def settle_contests(facts, standings) when is_list(facts) and is_map(standings) do
    facts
    |> Enum.filter(&Map.get(&1, :contest))
    |> Enum.group_by(& &1.contest)
    |> Enum.reduce(standings, fn {_contest, contesters}, acc ->
      settle_contest(contesters, standings, acc)
    end)
  end

  defp settle_contest(contesters, standings, acc) do
    # Confirmed by its own statements: current, or outranked in its slot.
    claims =
      for %{role: :claimant} = fact <- contesters,
          Map.get(standings, fact.id) in [:current, :superseded],
          do: {fact.holder, latest_confirmation_start(fact)}

    outranked =
      for %{role: :rival} = fact <- contesters,
          Map.get(standings, fact.id) == :current,
          outranked?(fact, claims),
          do: {fact.id, :superseded}

    Map.merge(acc, Map.new(outranked))
  end

  defp outranked?(rival, claims) do
    rival_end = latest_confirmation_end(rival)
    Enum.any?(claims, fn {holder, start} -> holder != rival.holder and start > rival_end end)
  end

  # Where the latest-starting (or latest-ending) counting confirmation of
  # `fact` starts (ends), as a Gregorian day; undated ones at
  # `undated_period/0`, so a claimant with only those outranks nothing.
  defp latest_confirmation_start(fact), do: confirmation_bound(fact, &elem(&1, 0))
  defp latest_confirmation_end(fact), do: confirmation_bound(fact, &elem(&1, 1))

  defp confirmation_bound(%{attributions: attributions}, bound) do
    for(
      a <- attributions,
      not a.retracted and counts?(a) and a.stance == :confirm,
      do: bound.(period(a))
    )
    |> Enum.max(fn -> @before_every_date end)
  end

  @doc """
  Where an undated attribution sorts: before every dated one, so any dated
  attribution outranks it and undated ones tie with each other.

  This is the parked date decision (`8567` *Sources–Facts design* point 7;
  `9449` §2). To change where undated statements sort, change only this
  function.
  """
  @spec undated_period() :: period()
  def undated_period, do: {@before_every_date, @before_every_date}

  defp own_standing(%{attributions: []}), do: {:unsupported, []}

  defp own_standing(%{id: id, previous: previous, attributions: attributions}) do
    case Enum.reject(attributions, & &1.retracted) do
      [] ->
        {:retracted, []}

      live ->
        case Enum.filter(live, &counts?/1) do
          [] -> {:unsupported, []}
          counting -> standing_of(id, previous, counting)
        end
    end
  end

  defp standing_of(id, previous, live) do
    newest = newest(live, & &1)

    case newest |> Enum.map(& &1.stance) |> Enum.uniq() do
      [:confirm] ->
        {:current, []}

      [:deny] ->
        {:withdrawn, []}

      _both ->
        conflict = %Conflict{type: :same_date, fact_ids: [id], attributions: newest}
        {kept(previous), [conflict]}
    end
  end

  defp counts?(statement), do: Map.get(statement, :counts, true)

  defp settle_slot(current, standings) when length(current) < 2, do: {standings, []}

  defp settle_slot(current, standings) do
    confirmations =
      for fact <- current,
          a <- fact.attributions,
          not a.retracted and counts?(a) and a.stance == :confirm do
        {fact, a}
      end

    newest = newest(confirmations, fn {_fact, a} -> a end)
    tied = newest |> Enum.map(fn {fact, _a} -> fact end) |> Enum.uniq_by(& &1.id)
    tied_ids = MapSet.new(tied, & &1.id)

    settled =
      Enum.reduce(current, standings, fn fact, acc ->
        cond do
          not MapSet.member?(tied_ids, fact.id) -> Map.put(acc, fact.id, :superseded)
          length(tied) == 1 -> acc
          true -> Map.put(acc, fact.id, kept(fact.previous))
        end
      end)

    conflicts =
      case tied do
        [_winner] ->
          []

        _several ->
          [
            %Conflict{
              type: :slot_tie,
              fact_ids: Enum.map(tied, & &1.id),
              attributions: Enum.map(newest, fn {_fact, a} -> a end)
            }
          ]
      end

    {settled, conflicts}
  end

  defp kept(nil), do: :unsupported
  defp kept(previous), do: previous

  # The items whose period nothing else comes entirely after. Calendar
  # periods are nested or disjoint, so these all overlap: they are the ones
  # whose period ends on or after the latest start.
  defp newest(items, statement_of) do
    with_periods = Enum.map(items, fn item -> {item, period(statement_of.(item))} end)
    latest_start = with_periods |> Enum.map(fn {_item, {first, _last}} -> first end) |> Enum.max()

    for {item, {_first, last}} <- with_periods, last >= latest_start, do: item
  end

  @spec period(statement()) :: period()
  defp period(%{stated_on: nil}), do: undated_period()

  defp period(%{stated_on: %Date{} = date, stated_precision: precision}) do
    {first, last} =
      case precision do
        :year -> {Date.new!(date.year, 1, 1), Date.new!(date.year, 12, 31)}
        :month -> {Date.beginning_of_month(date), Date.end_of_month(date)}
        :day -> {date, date}
      end

    {Date.to_gregorian_days(first), Date.to_gregorian_days(last)}
  end
end
