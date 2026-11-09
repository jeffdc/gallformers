defmodule Gallformers.Import.InatTaxa do
  @moduledoc """
  Bringing a taxon in from iNaturalist (matter `cb28`): what it would do,
  beside our tree (`plan/2`), and doing it (`carry_out/3`). Called through
  `Gallformers.Import` (`plan_inat_taxon/2`, `record_inat_taxon/3`).

  ## The plan

  For an iNaturalist taxon (`Gallformers.INaturalist.Taxon`) and the name
  that matched the search (nil when none did):

    * `held` — the taxon we hold, `%{id, rank, parent_id, parent}`: the one
      linked to its iNaturalist ID, else the one of its name at its rank in
      its kingdom (`Gallformers.Taxa.resolve_name/2`; a taxon with no
      kingdom recorded counts), else nil. `ours` is its rank as one of ours
      (`Gallformers.Taxa.Rank`), nil for a rank we don't use ("complex"):
      the curator picks one.
    * `lineage` — its ancestors, highest first, each a row (`%{key, inat_id,
      name, rank, ours, held, state}`) whose `state` is `:held`, `:needed`
      (a missing rank between it and the nearest one we hold: ticked),
      `:higher` (above the nearest one we hold, or with nothing held above
      it at all: not ticked) or `:skipped` (a rank we don't use).
    * `children` — its active children, the held ones first: `:held` (under
      it already), `:move` (held under another parent, named in
      `held.parent`), `:add`, or `:skipped` (a rank we don't use); none
      ticked.
    * `synonyms` (its other scientific names, the one that matched ticked)
      and `commons` (its English common names, iNaturalist's preferred one
      ticked), each `%{key, name}`, leaving out the names a held taxon has.
    * `authorship` — for a plant, WCVP's authorship of each taxon it could
      add (`"t"`, the taxon, and row keys), where WCVP holds the name at
      that rank (accepted or unplaced); iNaturalist gives none.
    * `ticked` — the keys ticked to start with.
  """
  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Import
  alias Gallformers.Import.SourceEdits
  alias Gallformers.Import.TaxonomyAdmin
  alias Gallformers.Import.TaxonomyStatements
  alias Gallformers.INaturalist.Taxon, as: InatTaxon
  alias Gallformers.Ranges.Wcvp, as: WcvpLinks
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer
  alias Gallformers.Taxa.Rank

  @typedoc "A taxon we hold, as a plan names it."
  @type held :: %{
          id: integer(),
          rank: Rank.t(),
          parent_id: integer() | nil,
          parent: String.t() | nil
        }

  @typedoc "A rank of the taxon's lineage, or one of its children."
  @type row :: %{
          key: String.t(),
          inat_id: integer(),
          name: String.t(),
          rank: String.t(),
          ours: Rank.t() | nil,
          held: held() | nil,
          state: :held | :needed | :higher | :skipped | :move | :add
        }

  @typedoc "What bringing a taxon in would do (see the module doc)."
  @type plan :: %{
          inat: InatTaxon.t(),
          name: String.t(),
          rank: String.t(),
          ours: Rank.t() | nil,
          kingdom: String.t() | nil,
          plant?: boolean(),
          active?: boolean(),
          replaced_by: [integer()],
          held: held() | nil,
          held_any?: boolean(),
          lineage: [row()],
          children: [row()],
          synonyms: [%{key: String.t(), name: String.t(), matched?: boolean()}],
          commons: [%{key: String.t(), name: String.t(), preferred?: boolean()}],
          authorship: %{String.t() => String.t()},
          ticked: MapSet.t(String.t())
        }

  @doc "The key of the taxon itself in a plan's `authorship` and choices."
  @spec taxon_key() :: String.t()
  def taxon_key, do: "t"

  # -- the plan ------------------------------------------------------------------

  @doc "What bringing `taxon` in would do, beside our tree (see the module doc)."
  @spec plan(InatTaxon.t(), String.t() | nil) :: plan()
  def plan(%InatTaxon{} = taxon, matched) do
    kingdom = taxon.kingdom
    ours = our_rank(taxon.rank)
    held = held(taxon.id, taxon.name, ours, kingdom)

    lineage =
      taxon.ancestors
      |> Enum.map(&row("a", &1, kingdom))
      |> lineage_states()

    children =
      taxon.children
      |> Enum.filter(& &1.active?)
      |> Enum.map(&row("c", &1, kingdom))
      |> Enum.map(&child_state(&1, held))
      |> Enum.sort_by(&if(&1.state in [:held, :move], do: 0, else: 1))

    held_names = if held, do: held_names(held.id), else: %{scientific: [], common: []}
    synonyms = synonyms(taxon, matched, held_names.scientific)
    commons = commons(taxon, held_names.common)
    plant? = kingdom == "Plantae"

    %{
      inat: taxon,
      name: taxon.name,
      rank: taxon.rank,
      ours: ours || (held && held.rank),
      kingdom: kingdom,
      plant?: plant?,
      active?: taxon.active?,
      replaced_by: taxon.replaced_by,
      held: held,
      held_any?: Enum.any?(lineage, &(&1.state == :held)),
      lineage: lineage,
      children: children,
      synonyms: synonyms,
      commons: commons,
      authorship: if(plant?, do: authorship(taxon, ours, held, lineage, children), else: %{}),
      ticked:
        MapSet.new(
          for(r <- lineage, r.state == :needed, do: r.key) ++
            for(s <- synonyms, s.matched?, do: s.key) ++
            for(c <- commons, c.preferred?, do: c.key)
        )
    }
  end

  defp row(prefix, relative, kingdom) do
    ours = our_rank(relative.rank)

    %{
      key: "#{prefix}#{relative.id}",
      inat_id: relative.id,
      name: relative.name,
      rank: relative.rank,
      ours: ours,
      held: ours && held(relative.id, relative.name, ours, kingdom),
      state: nil
    }
  end

  # Below the nearest rank we hold, the missing ones are needed to attach
  # the taxon; above it (or when we hold none), they are only offered.
  defp lineage_states(rows) do
    last_held =
      rows
      |> Enum.with_index()
      |> Enum.filter(fn {r, _i} -> r.held end)
      |> List.last()

    held_at = if last_held, do: elem(last_held, 1), else: length(rows)

    for {r, i} <- Enum.with_index(rows) do
      state =
        cond do
          r.ours == nil -> :skipped
          r.held -> :held
          i > held_at -> :needed
          true -> :higher
        end

      %{r | state: state}
    end
  end

  defp child_state(%{ours: nil} = row, _held), do: %{row | state: :skipped}
  defp child_state(%{held: nil} = row, _held), do: %{row | state: :add}

  defp child_state(%{held: %{parent_id: parent_id}} = row, %{id: parent_id}),
    do: %{row | state: :held}

  defp child_state(row, _held), do: %{row | state: :move}

  @doc "One of our ranks for iNaturalist's `rank` (`\"section\"`), or nil for one we don't use."
  @spec our_rank(String.t() | nil) :: Rank.t() | nil
  def our_rank(rank) when is_binary(rank),
    do: Enum.find(Rank.all(), &(Atom.to_string(&1) == rank))

  def our_rank(_rank), do: nil

  # The taxon we hold for an iNaturalist taxon: linked by its ID, else by
  # its name at its rank (any rank, for one we don't use) in its kingdom.
  defp held(inat_id, name, rank, kingdom) do
    case Taxa.get_by_inat_id(inat_id) do
      %Taxa.Taxon{} = taxon -> held_info(taxon)
      nil -> by_name(name, rank, kingdom)
    end
  end

  defp by_name(name, rank, kingdom) do
    opts = if rank, do: [rank: rank], else: []

    found =
      case Taxa.resolve_name(name, opts) do
        {:ok, taxon} -> [taxon]
        {:ambiguous, taxa} -> taxa
        :none -> []
      end

    found
    |> Enum.filter(&(&1.kingdom in [kingdom, nil]))
    |> Enum.sort_by(&if(&1.matched_name.status == :accepted, do: 0, else: 1))
    |> case do
      [taxon | _] -> held_info(taxon)
      [] -> nil
    end
  end

  defp held_info(taxon) do
    %{
      id: taxon.id,
      rank: taxon.rank,
      parent_id: taxon.parent_id,
      parent: taxon.parent_id && Taxa.accepted_name(taxon.parent_id)
    }
  end

  defp held_names(taxon_id) do
    taxon = Taxa.get_taxon!(taxon_id)

    %{
      scientific: Enum.map(taxon.names, & &1.normalized_name),
      common: Enum.map(Taxa.list_common_names(taxon_id), &String.downcase(&1.name))
    }
  end

  defp synonyms(taxon, matched, held) do
    own = NameNormalizer.normalize(taxon.name)
    matched = matched && NameNormalizer.normalize(matched)

    for %{lexicon: "scientific-names", name: name} <- taxon.names,
        normalized = NameNormalizer.normalize(name),
        normalized != own,
        normalized not in held,
        uniq: true,
        do: %{key: "s:" <> name, name: name, matched?: normalized == matched}
  end

  defp commons(taxon, held) do
    taxon.names
    |> Enum.filter(&(&1.lexicon == "english"))
    |> Enum.uniq_by(&String.downcase(&1.name))
    |> Enum.reject(&(String.downcase(&1.name) in held))
    |> Enum.map(&%{key: "e:" <> &1.name, name: &1.name, preferred?: &1.name == taxon.common})
  end

  # WCVP's authorship of each plant the import could add, where WCVP holds
  # the name at that rank, accepted or unplaced.
  defp authorship(taxon, ours, held, lineage, children) do
    candidates =
      if(held == nil and ours, do: [{taxon_key(), taxon.name, ours}], else: []) ++
        for(
          r <- lineage ++ children,
          r.state in [:needed, :higher, :add],
          do: {r.key, r.name, r.ours}
        )

    records =
      candidates
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> wcvp_lookup().find_names()
      |> Enum.filter(
        &(&1.taxon_status in ["Accepted", "Unplaced"] and &1.taxon_authors not in [nil, ""])
      )

    for {key, name, rank} <- candidates,
        record = Enum.find(records, &(&1.taxon_name == name and WcvpLinks.rank(&1) == rank)),
        into: %{},
        do: {key, record.taxon_authors}
  rescue
    # WCVP's database not available: no authorship to offer.
    DBConnection.ConnectionError -> %{}
    Postgrex.Error -> %{}
  end

  defp wcvp_lookup, do: Application.get_env(:gallformers, :wcvp_lookup, Gallformers.Wcvp.Lookup)

  # -- what the choices add ------------------------------------------------------

  @typedoc """
  The curator's choices: the keys `ticked`, the `rank` to add a taxon of a
  rank we don't use as, and the `authorship` typed for each taxon added
  (by key; `"t"` the taxon).
  """
  @type choices :: %{
          ticked: MapSet.t(String.t()),
          rank: Rank.t() | nil,
          authorship: %{String.t() => String.t()}
        }

  @doc """
  The lineage row the taxon goes under with `ticked`: the nearest rank
  above it held or ticked to add, or nil (it goes in at the top).
  """
  @spec attach_row(plan(), MapSet.t(String.t())) :: row() | nil
  def attach_row(plan, ticked),
    do: plan.lineage |> Enum.filter(&(&1.state == :held or added?(&1, ticked))) |> List.last()

  @doc """
  The ranks a taxon of a rank we don't use may be added as, with `ticked`:
  ours below the rank it goes under.
  """
  @spec rank_choices(plan(), MapSet.t(String.t())) :: [Rank.t()]
  def rank_choices(plan, ticked) do
    case attach_row(plan, ticked) do
      nil -> Rank.all()
      row -> Enum.filter(Rank.all(), &Rank.below?(&1, row.ours))
    end
  end

  @doc """
  The taxa `ticked` adds, highest first, each `%{key, name, rank}` (`rank`
  ours; the taxon's is `rank` when it has none of ours): the lineage
  ranks, the taxon, its children.
  """
  @spec additions(plan(), MapSet.t(String.t()), Rank.t() | nil) :: [map()]
  def additions(plan, ticked, rank \\ nil) do
    lineage =
      for r <- plan.lineage, added?(r, ticked), do: %{key: r.key, name: r.name, rank: r.ours}

    me =
      if plan.held,
        do: [],
        else: [%{key: taxon_key(), name: plan.name, rank: plan.ours || rank}]

    children =
      for c <- plan.children,
          c.state == :add,
          c.key in ticked,
          do: %{key: c.key, name: c.name, rank: c.ours}

    lineage ++ me ++ children
  end

  @doc "How many taxa `ticked` adds and moves, and names it adds: `{added, moved, names}`."
  @spec counts(plan(), MapSet.t(String.t())) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  def counts(plan, ticked) do
    added = length(additions(plan, ticked))
    moved = Enum.count(plan.children, &(&1.state == :move and &1.key in ticked))
    names = Enum.count(plan.synonyms ++ plan.commons, &(&1.key in ticked))
    {added, moved, names}
  end

  defp added?(row, ticked), do: row.state in [:needed, :higher] and row.key in ticked

  # -- carrying it out -----------------------------------------------------------

  @doc """
  Brings the taxon in as `choices` say, in one transaction audited as
  `actor`: the lineage ranks ticked (each under the nearest one held or
  added), the taxon (unless held) under the nearest, the children ticked
  added under it or moved there, the names ticked; every taxon added or
  held linked to its iNaturalist taxon. A plant is edited directly
  (`Gallformers.Import.TaxonomyAdmin`, origin `:inaturalist`); any other
  taxon's changes are the day's iNaturalist Source's statements, accepted
  by `actor` (`Gallformers.Import.TaxonomyStatements`). All of it or
  nothing, every edit in the replay log.

  `{:ok, %{taxon_id, added, moved}}`; `{:error, :inactive}` for a taxon
  iNaturalist no longer uses, `{:error, :rank_required}` when its rank is
  one we don't use and none was chosen, or the error of the edit refused.
  """
  @spec carry_out(Actor.t(), plan(), choices()) ::
          {:ok, %{taxon_id: integer(), added: non_neg_integer(), moved: non_neg_integer()}}
          | {:error, term()}
  def carry_out(%Actor{} = actor, plan, choices) do
    ticked = choices.ticked
    rank = plan.ours || choices[:rank]

    cond do
      not plan.active? ->
        {:error, :inactive}

      plan.held == nil and rank == nil ->
        {:error, :rank_required}

      true ->
        Audit.transaction(actor, "import.record_inat_taxon", fn ->
          ctx = %{
            actor: actor,
            plan: plan,
            authorship: Map.get(choices, :authorship, %{}),
            basis: basis(actor, plan, ticked)
          }

          {parent_id, added} = lineage!(ctx, ticked)
          {taxon_id, added} = taxon!(ctx, parent_id, rank, added)
          {added, moved} = children!(ctx, taxon_id, ticked, added)
          names!(ctx, taxon_id, ticked)
          %{taxon_id: taxon_id, added: added, moved: moved}
        end)
    end
  end

  # Plants are edited directly; any other taxon's changes are the day's
  # iNaturalist Source's statements.
  # Nothing to state (a second import of a taxon held), no Source.
  defp basis(_actor, %{plant?: true}, _ticked), do: :editorial

  defp basis(actor, plan, ticked) do
    if counts(plan, ticked) == {0, 0, 0},
      do: :none,
      else: {:source, ok!(SourceEdits.record_inaturalist(actor, Date.utc_today())).id}
  end

  defp lineage!(ctx, ticked) do
    Enum.reduce(ctx.plan.lineage, {nil, 0}, fn row, {parent_id, added} ->
      cond do
        row.state == :held ->
          link!(ctx, row.held.id, row.inat_id)
          {row.held.id, added}

        added?(row, ticked) ->
          id = create!(ctx, row.key, %{name: row.name, rank: row.ours, parent_id: parent_id})
          link!(ctx, id, row.inat_id)
          {id, added + 1}

        true ->
          {parent_id, added}
      end
    end)
  end

  defp taxon!(%{plan: %{held: %{id: id}} = plan} = ctx, _parent_id, _rank, added) do
    link!(ctx, id, plan.inat.id)
    {id, added}
  end

  defp taxon!(%{plan: plan} = ctx, parent_id, rank, added) do
    id = create!(ctx, taxon_key(), %{name: plan.name, rank: rank, parent_id: parent_id})
    link!(ctx, id, plan.inat.id)
    {id, added + 1}
  end

  defp children!(ctx, taxon_id, ticked, added) do
    Enum.reduce(ctx.plan.children, {added, 0}, fn child, {added, moved} ->
      case {child.state, child.key in ticked} do
        {:add, true} ->
          id = create!(ctx, child.key, %{name: child.name, rank: child.ours, parent_id: taxon_id})
          link!(ctx, id, child.inat_id)
          {added + 1, moved}

        {:move, true} ->
          place!(ctx, child.held.id, taxon_id)
          link!(ctx, child.held.id, child.inat_id)
          {added, moved + 1}

        _ ->
          {added, moved}
      end
    end)
  end

  defp names!(ctx, taxon_id, ticked) do
    for s <- ctx.plan.synonyms, s.key in ticked, do: synonym!(ctx, taxon_id, s.name)
    for c <- ctx.plan.commons, c.key in ticked, do: common!(ctx, taxon_id, c.name)
    :ok
  end

  # -- the edits, a plant's or a statement --------------------------------------------

  defp create!(%{basis: :editorial} = ctx, key, attrs) do
    authorship = authorship_for(ctx, key)

    attrs =
      Map.merge(attrs, %{kingdom: "Plantae", origin: :inaturalist, authorship: authorship})

    taxon = ok!(TaxonomyAdmin.create_taxon(ctx.actor, attrs, [], []))

    # Only a species or below takes its authorship as it is made.
    if authorship && Enum.find(taxon.names, &(&1.status == :accepted)).authorship != authorship,
      do: ok!(Import.record_taxonomy_edit(ctx.actor, {:set_authorship, taxon.id, authorship}))

    taxon.id
  end

  defp create!(%{basis: basis} = ctx, key, attrs) do
    attrs =
      Map.merge(attrs, %{kingdom: ctx.plan.kingdom, authorship: authorship_for(ctx, key)})

    ok!(TaxonomyStatements.record(ctx.actor, basis, {:create_taxon, attrs, []})).id
  end

  defp place!(%{basis: :editorial} = ctx, id, parent_id),
    do: ok!(Import.record_taxonomy_edit(ctx.actor, {:place, id, parent_id}))

  defp place!(%{basis: basis} = ctx, id, parent_id),
    do: ok!(TaxonomyStatements.record(ctx.actor, basis, {:place, id, parent_id}))

  defp synonym!(%{basis: :editorial} = ctx, id, name),
    do: ok!(Import.record_synonym_added(ctx.actor, id, name))

  defp synonym!(%{basis: basis} = ctx, id, name),
    do: ok!(TaxonomyStatements.record(ctx.actor, basis, {:add_synonym, id, name}))

  defp common!(%{basis: :editorial} = ctx, id, name),
    do: ok!(Import.record_taxonomy_edit(ctx.actor, {:add_common_name, id, name}))

  defp common!(%{basis: basis} = ctx, id, name),
    do: ok!(TaxonomyStatements.record(ctx.actor, basis, {:add_common_name, id, name}))

  # Links a taxon to its iNaturalist taxon, unless either is linked already.
  defp link!(ctx, taxon_id, inat_id) do
    if Taxa.inat_id(taxon_id) == nil and Taxa.get_by_inat_id(inat_id) == nil,
      do: ok!(Import.record_taxonomy_edit(ctx.actor, {:set_inat, taxon_id, inat_id}))

    :ok
  end

  defp authorship_for(ctx, key) do
    case Map.get(ctx.authorship, key) do
      text when is_binary(text) -> if String.trim(text) == "", do: nil, else: String.trim(text)
      _ -> nil
    end
  end

  defp ok!({:ok, value}), do: value
  defp ok!({:error, reason}), do: Repo.rollback(reason)
end
