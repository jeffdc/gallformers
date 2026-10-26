defmodule Gallformers.CatalogMigration.Ranges do
  @moduledoc """
  Today's stored gall ranges (`gall_range`) as range Facts (`9449` §6,
  Task 17; `b5bd` M0, reopened): reports first, Facts after decisions.

  A Gall's potential range is computed from its Hosts
  (`Gallformers.Catalog.ReadModels.PotentialRange`), so only the
  differences between its stored range and its host union are kept, and
  only as a curator decides (`priv/catalog_migration/range_decisions.csv`).

  ## Comparing

  Both sides are compared as leaf places, as the potential range is: a
  stored or host-range row on a country with subdivisions stands for its
  subdivisions, whatever its precision. The host union is the range rows
  (`host_range` by `taxon_id`, native and introduced) of the Gall's Hosts
  as migrated: each `gallhost` plant, a genus placeholder as its genus.
  Regions in both are redundant and dropped. Galls with no stored range
  are not compared.

  ## Causes (the heuristics)

  A stored range is often a copy of the host union made in the old admin
  ("Recompute from hosts" copies the **native** union), and the copy keeps
  no record of where it came from. `gall_range` has no timestamps; what
  exists is `gallhost.inserted_at` (when a Host was linked),
  `host_traits.wcvp_synced_at` (when a plant's range was last re-imported
  from WCVP) and `gall_traits.range_computed_at` (when the Gall's range was
  last confirmed, written by the confirm action; call it *T*). Each region
  in the union but not stored is put down to the first cause that fits,
  judged on the Hosts that give it natively:

    1. `introduced` — no Host gives it natively, only as introduced range.
       A copy of the native union never had it.
    2. `host_added_later` — every such Host is *late* for this Gall: none of
       its native regions is in the stored range (it played no part in the
       copy), or it was linked after *T*. The union widened after the copy.
    3. `host_range_widened` — every such Host is late or had its range
       re-imported after *T* (needs *T*). The union widened after the copy.
    4. `removed` — otherwise: likely a curator removal.

  Stored regions outside a non-empty union are `outside`; a Gall whose
  Hosts have no range data at all has its whole stored range as
  `no_host_range` (its potential range would otherwise be every region).

  These are heuristics, not facts: the worksheet shows each row's places,
  `range_confirmed` and *T*, and a `suggested` decision; the curator
  decides. A Host whose regions a curator removed entirely looks late, and
  a later Host whose range overlaps the copied ones looks copied.

  ## Decisions

  `range_decisions.csv`: `gall_id, cause, decision, scope, note` (`scope`
  and `note` optional). `gall_id` selects the Galls a row is for:

    * a Gall ID — that Gall;
    * `confirmed` — every Gall whose range a curator confirmed
      (`gall_traits.range_confirmed`);
    * `*` — every Gall.

  `scope`, when given, is space-separated place codes (`US CA MX`, `MX-JAL`);
  the row then decides only the cause's places within them (a place covers
  the places below it: a country its subdivisions). Empty is every place.
  An unknown code is an error naming the row (`check/1`, before anything is
  written).

  **Precedence.** For each Gall and cause, each place is decided by the
  first row, in this order, whose scope covers it: the Gall's own row, then
  the `confirmed` row (for a range-confirmed Gall), then the `*` row. A
  place no row covers is pending. So a scoped `confirmed` row leaves its
  other places to the `*` row.

    * `removed`, `host_added_later`, `host_range_widened`, `introduced`:
      `exclude` — one `exclude` range Fact per region, attributed to the
      Gallformers Source (curator removals; `b5bd` M0) with an undated
      statement — or `ignore` (drift: no Fact).
    * `outside`: `ignore` only. A Gall's range never leaves every one of
      its Hosts' ranges, so a stored place outside them is not kept (a
      place where a Source says the Gall occurs but no Host grows is a
      recorded occurrence, not a range adjustment).
    * `no_host_range`: `only` — `only` Facts, keeping the stored range — or
      `ignore` (the Gall then appears in every region). `only` narrows a
      range its Hosts leave unknown (every region); it never widens one.

  An exclusion's statement says where it comes from: the range a curator
  confirmed (a range-confirmed Gall) or the range curators stored. The
  decision row's `note` is a curation record and stays in the decision
  file, out of the statement. `only` Facts are attributed to the
  "Gallformers legacy data" Source, as every legacy Fact is (`9449` §6, the
  M0 mechanism). A difference with no decision is pending
  (`Gallformers.CatalogMigration`).

  The worksheet's `decided_by` column shows, per Gall and cause, which rows
  decided which places (`<gall_id> [scope] <decision>: places`); its
  `decision` and `note` are filled only when one row decided every place.
  """

  alias Gallformers.CatalogMigration.Curated
  alias Gallformers.CatalogMigration.Old
  alias Gallformers.CatalogMigration.Report

  @input "range_decisions.csv"

  @decisions %{
    "removed" => ~w(exclude ignore),
    "host_added_later" => ~w(exclude ignore),
    "host_range_widened" => ~w(exclude ignore),
    "introduced" => ~w(exclude ignore),
    "outside" => ~w(ignore),
    "no_host_range" => ~w(only ignore)
  }

  @suggested %{
    "removed" => "exclude",
    "host_added_later" => "ignore",
    "host_range_widened" => "ignore",
    "introduced" => "ignore",
    "outside" => "ignore",
    "no_host_range" => "only"
  }

  @causes ~w(removed host_added_later host_range_widened introduced outside no_host_range)

  # Each place (`place_id`) with the leaf places below it (itself if a leaf).
  @leaf_ctes """
  WITH RECURSIVE down(place_id, leaf_id) AS (
    SELECT id, id FROM place
    UNION
    SELECT d.place_id, ph.place_id FROM down d JOIN place_hierarchy ph ON ph.parent_id = d.leaf_id
  ),
  leaf AS (
    SELECT d.place_id, d.leaf_id FROM down d
    WHERE NOT EXISTS (SELECT 1 FROM place_hierarchy c WHERE c.parent_id = d.leaf_id)
  )
  """

  @columns ~w(gall_id name cause decision note decided_by suggested places place_count range_confirmed range_computed_at)

  @typedoc """
  A decision row. `scope` is its place codes (`[]`: every place); `within`
  the leaf place IDs they cover — `:all` for no scope, `nil` until `check/1`
  resolves a scope.
  """
  @type decision :: %{
          gall_id: integer() | :confirmed | :any,
          cause: String.t(),
          decision: String.t(),
          scope: [String.t()],
          within: :all | MapSet.t(integer()) | nil,
          note: String.t(),
          line: pos_integer()
        }

  @type decisions :: %{{integer() | :confirmed | :any, String.t()} => decision()}

  @doc "Reads the decisions, by `{gall_id | :confirmed | :any, cause}`."
  @spec load(String.t()) :: {:ok, decisions()} | {:error, String.t()}
  def load(path) do
    with {:ok, rows} <- Curated.read(path, ~w(gall_id cause decision), ~w(scope note)),
         {:ok, parsed} <- Curated.parse_rows(path, rows, &parse/1) do
      parsed = Enum.map(parsed, fn {line, decision} -> {line, %{decision | line: line}} end)
      Curated.index(path, parsed, &{&1.gall_id, &1.cause})
    end
  end

  defp parse(row) do
    with {:ok, id} <- gall_id(row["gall_id"]),
         {:ok, allowed} <- cause(row["cause"]),
         :ok <- decision(row["decision"], row["cause"], allowed) do
      scope = String.split(row["scope"])

      {:ok,
       %{
         gall_id: id,
         cause: row["cause"],
         decision: row["decision"],
         scope: scope,
         within: if(scope == [], do: :all),
         note: row["note"],
         line: 1
       }}
    end
  end

  defp gall_id("*"), do: {:ok, :any}
  defp gall_id("confirmed"), do: {:ok, :confirmed}

  defp gall_id(text) do
    case Integer.parse(text) do
      {n, ""} -> {:ok, n}
      _ -> {:error, "gall_id must be a Gall ID, * or confirmed, got #{inspect(text)}"}
    end
  end

  @doc """
  Resolves each decision's scope against today's places: `within` becomes
  the leaf place IDs its codes cover. An unknown code is
  `{:error, "range_decisions.csv row N: ..."}`.
  """
  @spec check(decisions()) :: {:ok, decisions()} | {:error, String.t()}
  def check(decisions) do
    codes = decisions |> Map.values() |> Enum.flat_map(& &1.scope) |> Enum.uniq()
    leaves = scope_leaves(codes)

    decisions
    |> Enum.sort_by(fn {_key, d} -> d.line end)
    |> Enum.reduce_while({:ok, %{}}, fn {key, d}, {:ok, acc} ->
      case Enum.reject(d.scope, &Map.has_key?(leaves, &1)) do
        [] ->
          {:cont, {:ok, Map.put(acc, key, %{d | within: within(d.scope, leaves)})}}

        unknown ->
          message = "scope has unknown place codes: #{Enum.join(unknown, " ")}"
          {:halt, Curated.row_error(@input, d.line, message)}
      end
    end)
  end

  defp within([], _leaves), do: :all

  defp within(scope, leaves),
    do: Enum.reduce(scope, MapSet.new(), &MapSet.union(leaves[&1], &2))

  # Place code → the leaf place IDs it covers, for the codes that exist.
  defp scope_leaves([]), do: %{}

  defp scope_leaves(codes) do
    (@leaf_ctes <>
       """
       SELECT p.code, l.leaf_id FROM place p JOIN leaf l ON l.place_id = p.id
       WHERE p.code = ANY($1::text[])
       """)
    |> Old.rows([codes])
    |> Enum.group_by(& &1.code, & &1.leaf_id)
    |> Map.new(fn {code, ids} -> {code, MapSet.new(ids)} end)
  end

  defp cause(cause) do
    case Map.fetch(@decisions, cause) do
      {:ok, allowed} ->
        {:ok, allowed}

      :error ->
        {:error, "cause must be one of #{Enum.join(@causes, ", ")}, got #{inspect(cause)}"}
    end
  end

  defp decision(decision, cause, allowed) do
    if decision in allowed,
      do: :ok,
      else:
        {:error,
         "a #{cause} row's decision must be #{Enum.join(allowed, " or ")}, got #{inspect(decision)}"}
  end

  @doc """
  Classifies the migrated Galls' stored ranges and plans the range Facts
  the decisions make. `taxa` is the taxa step's crosswalk, `galls` the
  Galls as migrated; `attribution` holds the legacy Source's attribution
  (`:legacy`) and the Gallformers Source (`:gallformers`, or nil). Returns
  the assertions (`Gallformers.CatalogMigration.LegacyFacts` makes them).
  """
  @spec run(decisions(), map(), [map()], %{legacy: map(), gallformers: map() | nil}, Report.t()) ::
          {[tuple()], Report.t()}
  def run(decisions, taxa, galls, attribution, report) do
    gall_ids = Enum.map(galls, & &1.id)
    names = Map.new(galls, &{&1.id, &1.name})
    {host_species, host_taxa} = host_map(taxa)
    params = [gall_ids, host_species, host_taxa]

    differences = Old.rows(differences_sql(), params)
    [stored] = Old.rows(stored_sql(), params)
    codes = place_codes()
    traits = gall_traits(gall_ids)

    rows =
      differences
      |> Enum.group_by(&{&1.gall_id, &1.cause}, & &1.leaf_id)
      |> Enum.map(fn {{id, cause}, leaves} ->
        leaves = Enum.sort_by(leaves, &codes[&1])
        traits = Map.get(traits, id, %{})
        confirmed = traits[:range_confirmed] == true
        {groups, undecided} = decide(decisions, id, cause, confirmed, leaves)

        %{
          gall_id: id,
          name: names[id],
          cause: cause,
          leaves: leaves,
          confirmed: confirmed,
          groups:
            Enum.map(groups, fn {d, ls} ->
              %{decision: d, leaves: ls, places: Enum.map(ls, &codes[&1])}
            end),
          undecided: Enum.map(undecided, &codes[&1]),
          places: Enum.map(leaves, &codes[&1]),
          traits: traits
        }
      end)
      |> Enum.sort_by(&{&1.gall_id, Enum.find_index(@causes, fn c -> c == &1.cause end)})

    {assertions, unattributable} = assertions(rows, attribution)

    report =
      report
      |> Report.curation("ranges", @columns, Enum.map(rows, &worksheet_row/1))
      |> Report.pending(@input, pending(rows) ++ unattributable)
      |> counts(rows, stored, assertions)

    {assertions, report}
  end

  @doc "Reconciles the planned range Facts with those now held."
  @spec reconcile([tuple()], Report.t()) :: Report.t()
  def reconcile(assertions, report) do
    planned = Enum.count(assertions, &match?({:range, _key, _attribution}, &1))

    Report.reconcile(
      report,
      "Range Facts (range_decisions.csv)",
      planned,
      Old.count("SELECT count(*) FROM range_facts")
    )
  end

  # Plant species (and genus placeholders) → their Host taxa in Plantae.
  defp host_map(taxa) do
    for {species_id, taxon_id} <- taxa.plants,
        taxon_id != nil,
        match?(%{kingdom: "Plantae"}, taxa.taxa[taxon_id]) do
      {species_id, taxon_id}
    end
    |> Enum.unzip()
  end

  # -- SQL -------------------------------------------------------------------------
  # $1 the migrated Gall IDs; $2, $3 plant species ID → Host taxon ID.

  @ctes """
  #{@leaf_ctes},
  hostmap AS (SELECT * FROM unnest($2::bigint[], $3::bigint[]) AS m(species_id, taxon_id)),
  stored AS (
    SELECT DISTINCT gr.species_id AS gall_id, l.leaf_id
    FROM gall_range gr JOIN leaf l ON l.place_id = gr.place_id
    WHERE gr.species_id = ANY($1::bigint[])
  ),
  ranged AS (SELECT DISTINCT gall_id FROM stored),
  links AS (
    SELECT gh.gall_species_id AS gall_id, m.taxon_id,
           min(gh.inserted_at) AS linked_at, max(ht.wcvp_synced_at) AS synced_at
    FROM gallhost gh
    JOIN ranged r ON r.gall_id = gh.gall_species_id
    JOIN hostmap m ON m.species_id = gh.host_species_id
    LEFT JOIN host_traits ht ON ht.species_id = gh.host_species_id
    GROUP BY 1, 2
  ),
  contrib AS (
    SELECT lk.gall_id, lk.taxon_id, l.leaf_id, bool_or(hr.distribution_type = 'native') AS native
    FROM links lk
    JOIN host_range hr ON hr.taxon_id = lk.taxon_id
    JOIN leaf l ON l.place_id = hr.place_id
    GROUP BY 1, 2, 3
  ),
  union_leaves AS (
    SELECT DISTINCT gall_id, leaf_id FROM contrib
  )
  """

  # Joins only (no per-row sub-selects): production has ~230k stored range
  # rows and ~1M host range rows.

  defp stored_sql do
    @ctes <>
      """
      SELECT count(DISTINCT s.gall_id) AS galls,
             count(u.gall_id) AS redundant
      FROM stored s
      LEFT JOIN union_leaves u ON u.gall_id = s.gall_id AND u.leaf_id = s.leaf_id
      """
  end

  defp differences_sql do
    @ctes <>
      """
      ,
      union_galls AS (SELECT DISTINCT gall_id FROM contrib),
      covered AS (
        SELECT DISTINCT c.gall_id, c.taxon_id
        FROM contrib c JOIN stored s ON s.gall_id = c.gall_id AND s.leaf_id = c.leaf_id
        WHERE c.native
      ),
      hosts AS (
        SELECT lk.gall_id, lk.taxon_id,
          (cv.taxon_id IS NULL
           OR COALESCE(lk.linked_at > gt.range_computed_at, false)) AS late,
          COALESCE(lk.synced_at > gt.range_computed_at, false) AS widened
        FROM links lk
        LEFT JOIN covered cv ON cv.gall_id = lk.gall_id AND cv.taxon_id = lk.taxon_id
        LEFT JOIN gall_traits gt ON gt.species_id = lk.gall_id
      ),
      causes AS (
        SELECT c.gall_id, c.leaf_id,
          bool_or(c.native) AS any_native,
          bool_and(h.late) FILTER (WHERE c.native) AS all_late,
          bool_and(h.late OR h.widened) FILTER (WHERE c.native) AS all_late_or_widened
        FROM contrib c JOIN hosts h ON h.gall_id = c.gall_id AND h.taxon_id = c.taxon_id
        GROUP BY 1, 2
      )
      SELECT c.gall_id, c.leaf_id,
        CASE WHEN NOT c.any_native THEN 'introduced'
             WHEN c.all_late THEN 'host_added_later'
             WHEN c.all_late_or_widened THEN 'host_range_widened'
             ELSE 'removed' END AS cause
      FROM causes c
      LEFT JOIN stored s ON s.gall_id = c.gall_id AND s.leaf_id = c.leaf_id
      WHERE s.gall_id IS NULL
      UNION ALL
      SELECT s.gall_id, s.leaf_id,
        CASE WHEN ug.gall_id IS NOT NULL THEN 'outside' ELSE 'no_host_range' END
      FROM stored s
      LEFT JOIN union_leaves u ON u.gall_id = s.gall_id AND u.leaf_id = s.leaf_id
      LEFT JOIN union_galls ug ON ug.gall_id = s.gall_id
      WHERE u.gall_id IS NULL
      """
  end

  defp place_codes, do: "SELECT id, code FROM place" |> Old.rows() |> Map.new(&{&1.id, &1.code})

  defp gall_traits(gall_ids) do
    """
    SELECT species_id, range_confirmed, range_computed_at
    FROM gall_traits WHERE species_id = ANY($1::bigint[])
    """
    |> Old.rows([gall_ids])
    |> Map.new(&{&1.species_id, &1})
  end

  # -- decisions -------------------------------------------------------------------

  # Each place goes to the first row covering it: the Gall's own, then
  # `confirmed` (a range-confirmed Gall), then `*`. Returns the
  # `{decision, leaves}` groups in that order and the leaves none covers.
  defp decide(decisions, gall_id, cause, confirmed, leaves) do
    candidates =
      [
        decisions[{gall_id, cause}],
        if(confirmed, do: decisions[{:confirmed, cause}]),
        decisions[{:any, cause}]
      ]
      |> Enum.reject(&is_nil/1)

    {groups, rest} =
      Enum.reduce(candidates, {[], leaves}, fn decision, {groups, rest} ->
        case Enum.split_with(rest, &covers?(decision.within, &1)) do
          {[], rest} -> {groups, rest}
          {mine, rest} -> {[{decision, mine} | groups], rest}
        end
      end)

    {Enum.reverse(groups), rest}
  end

  defp covers?(:all, _leaf), do: true
  defp covers?(%MapSet{} = within, leaf), do: MapSet.member?(within, leaf)

  defp assertions(rows, attribution) do
    groups =
      for row <- rows, %{decision: %{decision: d}} = group <- row.groups, d != "ignore" do
        {row, group}
      end

    {exclusions, onlys} =
      Enum.split_with(groups, fn {_row, group} -> group.decision.decision == "exclude" end)

    {excluded, unattributable} =
      case attribution.gallformers do
        nil ->
          missing =
            for {row, _group} <- exclusions do
              {{row.gall_id, row.cause},
               "#{label(row)}: exclude needs the Gallformers Source, and there is none"}
            end

          {[], missing}

        gallformers ->
          {Enum.flat_map(exclusions, fn {row, group} ->
             facts(row, group, :exclude, exclusion(gallformers, row))
           end), []}
      end

    # `only` (no_host_range) is the one other decision that makes Facts.
    restricted =
      Enum.flat_map(onlys, fn {row, group} -> facts(row, group, :only, attribution.legacy) end)

    {excluded ++ restricted, unattributable}
  end

  defp facts(row, group, adjustment, attribution) do
    for leaf <- group.leaves do
      {:range, %{gall_id: row.gall_id, adjustment: adjustment, place_id: leaf}, attribution}
    end
  end

  # The decision row's note is a curation record, not part of the statement.
  defp exclusion(gallformers, row) do
    text =
      if row.confirmed,
        do:
          "Not in this Gall's range: a Gallformers curator confirmed its range before the " <>
            "catalog migration, and the confirmed range left this region out.",
        else:
          "Not in this Gall's range: the range Gallformers curators stored for it before the " <>
            "catalog migration left this region out."

    %{source_id: gallformers.id, stance: :confirm, stated: nil, statement_text: text}
  end

  defp pending(rows) do
    for %{undecided: [_ | _] = places} = row <- rows do
      {{row.gall_id, row.cause}, "#{label(row)}: #{Enum.join(places, " ")}"}
    end
  end

  defp label(row), do: "#{row.gall_id} #{row.name} #{row.cause}"

  # The deciding row's decision and note when one row decided every place.
  defp sole_decision(%{groups: [%{decision: decision}], undecided: []}), do: decision
  defp sole_decision(_row), do: nil

  defp decided_by(%{groups: []}), do: nil

  defp decided_by(%{groups: groups, undecided: undecided}) do
    split = length(groups) > 1 or undecided != []

    parts =
      for %{decision: d, places: places} <- groups do
        scope = if d.scope == [], do: "", else: " [#{Enum.join(d.scope, " ")}]"
        selector = %{any: "*", confirmed: "confirmed"}[d.gall_id] || d.gall_id
        head = "#{selector}#{scope} #{d.decision}"
        if split, do: "#{head}: #{Enum.join(places, " ")}", else: head
      end

    pending = if undecided == [], do: [], else: ["pending: #{Enum.join(undecided, " ")}"]
    Enum.join(parts ++ pending, "; ")
  end

  defp worksheet_row(row) do
    decision = sole_decision(row)

    %{
      "gall_id" => row.gall_id,
      "name" => row.name,
      "cause" => row.cause,
      "decision" => decision && decision.decision,
      "note" => decision && decision.note,
      "decided_by" => decided_by(row),
      "suggested" => @suggested[row.cause],
      "places" => row.places,
      "place_count" => length(row.places),
      "range_confirmed" => row.traits[:range_confirmed],
      "range_computed_at" => row.traits[:range_computed_at]
    }
  end

  defp counts(report, rows, stored, assertions) do
    by_cause = Enum.group_by(rows, & &1.cause)
    adjustments = Enum.frequencies_by(assertions, fn {:range, key, _} -> key.adjustment end)

    report =
      report
      |> Report.count("Galls with a stored range", stored.galls)
      |> Report.count("Stored-range places also in the host union (dropped)", stored.redundant)

    @causes
    |> Enum.reduce(report, fn cause, acc ->
      rows = Map.get(by_cause, cause, [])

      acc
      |> Report.count("Stored-range differences, #{cause}: Galls", length(rows))
      |> Report.count(
        "Stored-range differences, #{cause}: places",
        Enum.sum(Enum.map(rows, &length(&1.leaves)))
      )
    end)
    |> Report.count("Range Facts planned: exclude", Map.get(adjustments, :exclude, 0))
    |> Report.count("Range Facts planned: only", Map.get(adjustments, :only, 0))
  end
end
