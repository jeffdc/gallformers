defmodule Gallformers.Taxa.Lump do
  @moduledoc """
  A lump (matter `f923` Task 4, "Lumps"): taxon B, now a synonym of taxon
  A, is merged into A. Called through `Gallformers.Taxa.merge/3`; the tree's
  sync calls it when a synonymy of B's accepted name into A comes into
  effect (`Gallformers.Taxa.Sync`).

  Within one audited transaction:

    1. **Names.** B's accepted name and synonyms become A's synonyms (one A
       holds already is dropped), and its common names, crosswalk entries
       and notes follow (`Gallformers.Taxa.Records.merge_names/3`); the
       Sources' names of B (`attribution_names`) name A, keeping
       `name_as_written`.
    2. **Taxonomic-act Facts naming B** move onto A's Fact with the same
       key (created when A has none), with their attributions untouched:
       a synonymy into B is one into A, a placement under B one under A.
       B's **own placement and name statements** become statements about
       A that must not move A: each one that would count, other than a
       confirmation of A's current placement or name, is declined
       ("<B> was merged into <A>"), so the Source's statement stays as
       history; the tree's own (Gallformers' Sources' statements of B,
       which count without acceptance) are removed (audit keeps them). A
       statement that would join A to itself (B placed under A) is
       removed.
    3. **The event.** `:merge` goes to the "taxon changed" listeners with
       the map of B's act Facts to A's (`Gallformers.Taxa.Event`): they
       move what their side holds of B (the Catalog's Facts about Galls,
       re-pointing B's Inducer Facts to A; the import tables; images) and
       propose the Gall renames that follow. A listener's error fails the
       merge with its reason.
    4. B's emptied act Facts are deleted, B's ID redirects to A
       (`Gallformers.Taxa.taxon_redirect/1`) and B is deleted
       (`Gallformers.Taxa.delete_taxon/2`); anything still naming it fails
       the merge with `{:referenced, references}`.

  Refused: merging a taxon into itself (`:same_taxon`), plants (`:plant`;
  plant merges are editorial, `Gallformers.Import.Merge`), and a B with
  taxa under it (`:has_children`: their own placements decide where they go).
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Facts
  alias Gallformers.Facts.Fact
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.ActFacts
  alias Gallformers.Taxa.ActFacts.NameFact
  alias Gallformers.Taxa.ActFacts.PlacementFact
  alias Gallformers.Taxa.ActFacts.SplitFact
  alias Gallformers.Taxa.Event
  alias Gallformers.Taxa.Events
  alias Gallformers.Taxa.Records
  alias Gallformers.Taxa.Sync
  alias Gallformers.Taxa.Taxon
  alias Gallformers.Taxa.Tree

  @type error :: :same_taxon | :plant | :has_children | :not_found | term()

  @doc "Merges `absorbed_id` into `survivor_id` (see the module doc)."
  @spec merge(Actor.t(), integer(), integer()) :: {:ok, Taxon.t()} | {:error, error()}
  def merge(%Actor{} = actor, absorbed_id, survivor_id) do
    # The survivor's slot winners stay as they are, so the tree follows no
    # Fact this moves (`Gallformers.Taxa.Sync`).
    Sync.without_following(fn -> run(actor, absorbed_id, survivor_id) end)
  end

  defp run(actor, absorbed_id, survivor_id) do
    Audit.transaction(actor, "taxa.merge", fn ->
      Tree.lock()

      case check(absorbed_id, survivor_id) do
        {:ok, absorbed, survivor} -> lump(actor, absorbed, survivor)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp lump(actor, absorbed, survivor) do
    absorbed_name = Taxa.accepted_name(absorbed)
    survivor_name = Taxa.accepted_name(survivor)
    reason = "#{absorbed_name} was merged into #{survivor_name}"
    winners = winners(survivor.id)

    {fact_map, created} = move_act_facts(actor, absorbed.id, survivor.id, winners, reason)
    {:ok, _} = Records.merge_names(actor, absorbed.id, survivor.id)
    {:ok, _} = Facts.repoint_attribution_names(actor, absorbed.id, survivor.id)

    :ok =
      Events.dispatch(%Event{
        type: :merge,
        taxon_id: absorbed.id,
        into_taxon_id: survivor.id,
        old_name: absorbed_name,
        new_name: survivor_name,
        fact_map: fact_map
      })

    {:ok, _} = Records.delete_act_facts(actor, Map.keys(fact_map) ++ emptied(created))
    {:ok, _} = Records.add_redirect(actor, absorbed.id, survivor.id)

    case Taxa.delete_taxon(actor, absorbed.id) do
      {:ok, _} -> Taxa.get_taxon!(survivor.id)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp check(id, id), do: {:error, :same_taxon}

  defp check(absorbed_id, survivor_id) do
    lock = fn id -> Repo.one(from(t in Taxon, where: t.id == ^id, lock: "FOR UPDATE")) end

    with %Taxon{} = absorbed <- lock.(absorbed_id),
         %Taxon{} = survivor <- lock.(survivor_id) do
      cond do
        "Plantae" in [absorbed.kingdom, survivor.kingdom] ->
          {:error, :plant}

        Repo.exists?(from(t in Taxon, where: t.parent_id == ^absorbed_id)) ->
          {:error, :has_children}

        true ->
          {:ok, absorbed, survivor}
      end
    else
      nil -> {:error, :not_found}
    end
  end

  # The survivor's current placement and name Facts.
  defp winners(survivor_id) do
    for slot <- ["placement", "name"], into: %{} do
      {slot,
       Repo.one(
         from(f in Fact,
           where: f.slot == ^"taxon:#{survivor_id}:#{slot}" and f.standing == :current,
           select: f.id
         )
       )}
    end
  end

  # Moves the statements of every act Fact naming the absorbed taxon onto
  # the survivor's Fact with the same key. Returns `{fact_map, created}`:
  # each moved Fact's target (nil when dropped) and the targets created.
  defp move_act_facts(actor, absorbed_id, survivor_id, winners, reason) do
    absorbed_id
    |> List.wrap()
    |> Records.act_facts()
    |> Enum.reduce({%{}, []}, fn %{fact_id: fact_id}, {map, created} ->
      ctx = %{actor: actor, absorbed_id: absorbed_id, winners: winners, reason: reason}

      case move_act_fact(ctx, fact_id, survivor_id) do
        {:dropped, nil} -> {Map.put(map, fact_id, nil), created}
        {:moved, target, true} -> {Map.put(map, fact_id, target), [target | created]}
        {:moved, target, false} -> {Map.put(map, fact_id, target), created}
      end
    end)
  end

  defp move_act_fact(ctx, fact_id, survivor_id) do
    %module{} = detail = ActFacts.get_detail(fact_id)
    key = rekey(module.key(detail), ctx.absorbed_id, survivor_id)
    attributions = Facts.list_attributions(fact_id)

    if joins_itself?(module, key) do
      Enum.each(attributions, &remove!(ctx.actor, fact_id, &1.source_id))
      {:dropped, nil}
    else
      {:ok, target, new?} = ActFacts.find_or_create(module, ctx.actor, key)
      own_slot = own_slot(module, detail, ctx.absorbed_id)
      Enum.each(attributions, &move_statement(ctx, &1, target.fact_id, own_slot, module.kind()))
      {:moved, target.fact_id, new?}
    end
  end

  # Moves one statement; one of the absorbed taxon's own that would compete
  # with the survivor's current placement or name is neutralized.
  defp move_statement(ctx, attribution, target_id, own_slot, kind) do
    {:ok, %{moved: moved}} = Facts.move_attribution(ctx.actor, attribution.id, target_id)
    keeps_winner? = attribution.stance == :confirm and target_id == ctx.winners[own_slot]

    if moved and own_slot != nil and not keeps_winner?,
      do: neutralize(ctx.actor, attribution, target_id, kind, ctx.reason),
      else: :ok
  end

  # The absorbed taxon's own placement or name: the survivor's slot it
  # would compete in.
  defp own_slot(PlacementFact, %{taxon_id: id}, id), do: "placement"
  defp own_slot(NameFact, %{taxon_id: id}, id), do: "name"
  defp own_slot(_module, _detail, _absorbed_id), do: nil

  # A statement moved onto the survivor that must not move it: declined
  # (kept as history), or removed when it is Gallformers' own (which
  # counts without acceptance and cannot be declined).
  defp neutralize(actor, attribution, target_fact_id, kind, reason) do
    cond do
      not Facts.needs_acceptance?(kind, attribution.source_id) ->
        remove!(actor, target_fact_id, attribution.source_id)

      attribution.declined_at != nil ->
        :ok

      true ->
        case Facts.decline(actor, attribution.id, reason) do
          {:ok, _} -> :ok
          {:error, other} -> Repo.rollback(other)
        end
    end
  end

  defp remove!(actor, fact_id, source_id) do
    case Facts.remove_attribution(actor, fact_id, source_id) do
      {:ok, _conflicts} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @taxon_fields [:taxon_id, :parent_id, :accepted_taxon_id]

  defp rekey(key, from, to) do
    key
    |> Map.new(fn
      {field, ^from} when field in @taxon_fields -> {field, to}
      {:into_taxon_ids, ids} -> {:into_taxon_ids, ids |> Enum.map(&swap(&1, from, to))}
      other -> other
    end)
  end

  defp swap(id, id, to), do: to
  defp swap(id, _from, _to), do: id

  defp joins_itself?(PlacementFact, %{taxon_id: id, parent_id: id}), do: true

  defp joins_itself?(SplitFact, %{taxon_id: id, into_taxon_ids: into}),
    do: id in into or length(Enum.uniq(into)) < 2

  defp joins_itself?(_module, _key), do: false

  # Targets the merge created that were left with no statement.
  defp emptied([]), do: []

  defp emptied(fact_ids) do
    held = fact_ids |> Facts.source_ids_by_fact() |> Map.keys() |> MapSet.new()
    Enum.reject(fact_ids, &MapSet.member?(held, &1))
  end
end
