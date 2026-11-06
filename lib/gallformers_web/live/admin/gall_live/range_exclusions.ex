defmodule GallformersWeb.Admin.GallLive.RangeExclusions do
  @moduledoc """
  The Gall page's range exclusions (matter a856, Decision 6, Task 7): a
  curator marks places of a Gall's potential range as excluded or restores
  them, and the change is saved as Gallformers' own statement — a gall batch
  fragment (`priv/import/GALLFORMERS_STATEMENTS.md`) taken in through
  `Gallformers.Import.submit_gallformers_fragment/2`, so it is audited,
  replayable and attributed like any import.

  The map works on leaf places (`Gallformers.Places`): a current exclusion
  naming a country stands for its subdivisions. Saving compares the marked
  leaves with the current exclusions (`plan/2`):

    * a marked place no current exclusion covers gets a `confirm` range Fact
      `exclude`;
    * a current exclusion with a leaf no longer marked is withdrawn: the
      Gallformers Source states a `deny` on the same Fact (gall, `exclude`,
      place) — the newest statement decides its standing
      (`Gallformers.Facts.Standing`). Its other leaves that stay marked are
      excluded one by one.
  """
  alias Gallformers.Catalog
  alias Gallformers.Import.GallformersFragment
  alias Gallformers.Places

  @typedoc "A current exclusion with the leaf places it stands for."
  @type exclusion :: %{
          required(:place_code) => String.t(),
          required(:leaves) => [String.t()],
          optional(atom()) => any()
        }

  @typedoc "What saving states: places to exclude, exclusions to withdraw (by place code)."
  @type plan :: %{exclude: [String.t()], withdraw: [String.t()]}

  @typedoc """
  A Gall's range as the exclusions map starts from: `everywhere?` (no Host
  range data), its potential range split for colouring, its current
  exclusions and the leaves they exclude.
  """
  @type state :: %{
          everywhere?: boolean(),
          in_range: [String.t()],
          inherited_range: [String.t()],
          introduced_range: [String.t()],
          exclusions: [exclusion()],
          excluded: MapSet.t(String.t())
        }

  @doc """
  Gall `gall_id`'s range as the map starts from (`t:state/0`), its places
  by code (`place_by_code`, from `Gallformers.Places.list_all_places/0`).
  """
  @spec load(integer(), %{String.t() => map()}) :: state()
  def load(gall_id, place_by_code) when is_integer(gall_id) do
    adjustments =
      for a <- Catalog.list_range_adjustments(gall_id), a.adjustment == :exclude, do: a

    leaf_ids = adjustments |> Enum.map(& &1.place_id) |> Places.leaf_descendant_ids_by_place()
    code_by_id = Map.new(place_by_code, fn {code, place} -> {place.id, code} end)

    exclusions =
      Enum.map(adjustments, fn adjustment ->
        leaves =
          leaf_ids
          |> Map.get(adjustment.place_id, [adjustment.place_id])
          |> Enum.map(&Map.get(code_by_id, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.sort()

        Map.put(adjustment, :leaves, leaves)
      end)

    excluded = exclusions |> Enum.flat_map(& &1.leaves) |> MapSet.new()

    case Catalog.display_range(gall_id) do
      :everywhere ->
        %{
          everywhere?: true,
          in_range: [],
          inherited_range: [],
          introduced_range: [],
          exclusions: exclusions,
          excluded: excluded
        }

      display ->
        %{
          everywhere?: false,
          in_range: display.in_range,
          inherited_range: display.inherited_range,
          introduced_range: display.introduced_range,
          exclusions: exclusions,
          excluded: excluded
        }
    end
  end

  @doc """
  Whether a curator may mark place `code`: a place of the potential range or
  a currently excluded one; any place when the range is everywhere.
  """
  @spec markable?(state(), String.t()) :: boolean()
  def markable?(%{everywhere?: true}, _code), do: true

  def markable?(state, code) do
    code in state.in_range or code in state.inherited_range or
      MapSet.member?(state.excluded, code)
  end

  @doc """
  The places the potential range offers to mark (the drill-down's places):
  its places and the currently excluded ones, by code.
  """
  @spec markable_codes(state()) :: [String.t()]
  def markable_codes(state) do
    (state.in_range ++ state.inherited_range ++ MapSet.to_list(state.excluded))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  The map's colours with the `marked` places excluded: the potential range's
  places (a restored exclusion shows as exact), less the marked ones.
  """
  @spec map_ranges(state(), MapSet.t(String.t())) :: %{
          in_range: [String.t()],
          inherited_range: [String.t()],
          excluded_range: [String.t()],
          introduced_range: [String.t()]
        }
  def map_ranges(state, marked) do
    unmarked = &Enum.reject(&1, fn code -> MapSet.member?(marked, code) end)
    inherited = MapSet.new(state.inherited_range)

    restored =
      state.excluded |> MapSet.difference(inherited) |> MapSet.to_list()

    %{
      in_range: (state.in_range ++ restored) |> Enum.uniq() |> unmarked.() |> Enum.sort(),
      inherited_range: unmarked.(state.inherited_range),
      excluded_range: marked |> MapSet.to_list() |> Enum.sort(),
      introduced_range: state.introduced_range
    }
  end

  @doc """
  What saving the `marked` leaves states, given the current `exclusions`
  (`t:plan/0`): the marked places no kept exclusion covers are excluded; an
  exclusion with an unmarked leaf is withdrawn.
  """
  @spec plan([exclusion()], MapSet.t(String.t())) :: plan()
  def plan(exclusions, marked) do
    {kept, withdrawn} =
      Enum.split_with(exclusions, fn e -> Enum.all?(e.leaves, &MapSet.member?(marked, &1)) end)

    covered = kept |> Enum.flat_map(& &1.leaves) |> MapSet.new()

    %{
      exclude: marked |> MapSet.difference(covered) |> MapSet.to_list() |> Enum.sort(),
      withdraw: withdrawn |> Enum.map(& &1.place_code) |> Enum.uniq() |> Enum.sort()
    }
  end

  @doc """
  The gall batch stating `plan` about the Gall `summary` describes
  (`Gallformers.Catalog.gall_summary/1`), as Gallformers' own statement
  `statement` (`%{text, stated_on}`), each place written with its name from
  `place_names` (code → name).

  The Gall is named as an import names it
  (`Gallformers.Import.GallformersFragment.gall_batch/3`): by its Inducer
  and generation, with its first Host as well when the Inducer is above
  species rank or missing; `gallformers_gall_id` is checked against that.
  `{:error, :unidentified}` for a Gall with neither Inducer nor Host.
  """
  @spec batch(map(), plan(), %{text: String.t(), stated_on: Date.t()}, %{String.t() => String.t()}) ::
          {:ok, map()} | {:error, :unidentified}
  def batch(summary, plan, statement, place_names) do
    evidence = [
      %{
        "statement" => %{
          "text" => String.trim(statement.text),
          "stated_on" => Date.to_iso8601(statement.stated_on)
        }
      }
    ]

    facts =
      for {stance, code} <-
            Enum.map(plan.exclude, &{"confirm", &1}) ++ Enum.map(plan.withdraw, &{"deny", &1}) do
        %{
          "stance" => stance,
          "kind" => "range",
          "gall" => :gall,
          "adjustment" => "exclude",
          "place" => %{"value" => code, "as_written" => Map.get(place_names, code, code)},
          "evidence" => evidence
        }
      end

    GallformersFragment.gall_batch(summary, facts)
  end
end
