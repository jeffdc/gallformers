defmodule Gallformers.Import.Merge do
  @moduledoc """
  Merging a Gall or a plant recorded twice into the one the curator keeps
  (matter `ec2c`, "Deletes": "What a Gall merge does", "Plant merges").
  Both are editorial (Gall identity and plants are Gallformers'); merging
  other taxa is a synonymy, a Source's act (phase 2, `f923`), and is not
  done here.

  ## A Gall merge (`{:gall, absorbed_id, survivor_id}`)

    * Facts move with their attributions; the same Fact on both combines
      its Sources; standings are recomputed, so a single-valued
      disagreement follows recency, and a same-date tie becomes a curator
      question: an open `:same_date_conflict` queue item of no package
      (`Gallformers.Catalog.Records`, "Moving Facts").
    * Other Galls pointing at the absorbed one (an alternate generation)
      point at the survivor; a Relationship between the two is dropped.
    * The survivor keeps its name, code, completeness, abundance and
      default Source. The absorbed name becomes its alias (a former label);
      the absorbed ID and code redirect (`Gallformers.Catalog.gall_redirect/1`).
    * All images move over, after the survivor's own.
    * Gallformers notes: the absorbed note's versions move over; when both
      had a note, the absorbed one's text is appended to the survivor's
      under a heading ("From the merged X gall") as a new version.
    * The import rows naming the absorbed Gall or its Facts are re-pointed
      (`Gallformers.Import.RecordRefs.repoint/3`); an open question or a
      package under review naming them blocks the merge.

  ## A plant merge (`{:plant, absorbed_id, survivor_id}`)

  Both plants at species rank or below. The absorbed plant's accepted name
  and synonyms become the survivor's synonyms, its common names, crosswalk
  entries and notes move over, the Host Facts naming it (and its other
  gall Facts) move as a Gall's do, the Galls its name qualifies are
  re-qualified, its images move over, its range is dropped (the range is
  the survivor's), its ID redirects (`Gallformers.Taxa.taxon_redirect/1`)
  and it is deleted. A plant with taxa under it, a real Source's
  taxonomic-act Fact about it, a generation group listing it, an open
  question or a package under review naming it blocks the merge.

  ## Preview and record

  `preview/1` runs the merge in a transaction it rolls back, so it shows
  exactly what `record/2` would do, blockers included, and writes
  nothing (no note version is stored either). `record/2` refuses when
  anything blocks, logs a `:merge` replay entry by stable references,
  and after the commit broadcasts `{:records_merged, %{type, absorbed_id,
  survivor_id, by}}` on `"catalog:records"`.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Facts
  alias Gallformers.Facts.Fact
  alias Gallformers.Images
  alias Gallformers.Import.Deletion
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.RecordRefs
  alias Gallformers.Import.ReplayLog
  alias Gallformers.Import.StableRef
  alias Gallformers.Ranges
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon

  @type spec :: {:gall | :plant, integer(), integer()}

  @type error :: :not_found | :same_record | :not_a_plant | {:blocked, [Deletion.blocker()]}

  @typedoc """
  What a merge does (`preview/1`) or did (`record/2`): see `Gallformers.Import`'s
  `record_merge/2` for the shape.
  """
  @type result :: map()

  @doc """
  What merging would do, writing nothing. `actor` is whom the rolled-back
  transaction is audited as (by default a system actor).
  """
  @spec preview(spec(), Actor.t()) :: {:ok, result()} | {:error, error() | term()}
  def preview(spec, %Actor{} = actor \\ Actor.system("merge preview")) do
    case run(actor, spec, true) do
      {:error, {:preview, result}} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Merges (see the module doc)."
  @spec record(Actor.t(), spec()) :: {:ok, result()} | {:error, error() | term()}
  def record(%Actor{} = actor, {type, absorbed_id, survivor_id} = spec) do
    case run(actor, spec, false) do
      {:ok, result} ->
        Deletion.broadcast(
          {:records_merged,
           %{type: type, absorbed_id: absorbed_id, survivor_id: survivor_id, by: actor.name}}
        )

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run(actor, {type, absorbed_id, survivor_id} = spec, dry_run?) do
    Audit.transaction(actor, "import.record_merge", fn ->
      check(spec) |> ok_or_rollback()
      Taxa.lock_tree()
      lock(type, absorbed_id)
      lock(type, survivor_id)
      key = replay_key(spec)

      result = merge(actor, spec, dry_run?)

      if dry_run? do
        Repo.rollback({:preview, result})
      else
        ReplayLog.append!(:merge, key, %{})
        result
      end
    end)
  end

  defp check({_type, id, id}), do: {:error, :same_record}

  defp check({:gall, absorbed_id, survivor_id}) do
    if Catalog.get_gall(absorbed_id) && Catalog.get_gall(survivor_id),
      do: {:ok, :ok},
      else: {:error, :not_found}
  end

  defp check({:plant, absorbed_id, survivor_id}) do
    case {Taxa.get_taxon(absorbed_id), Taxa.get_taxon(survivor_id)} do
      {%Taxon{} = a, %Taxon{} = s} ->
        if plant?(a) and plant?(s), do: {:ok, :ok}, else: {:error, :not_a_plant}

      _ ->
        {:error, :not_found}
    end
  end

  defp plant?(%Taxon{kingdom: "Plantae", rank: rank}), do: rank in Rank.species_and_below()
  defp plant?(_taxon), do: false

  defp lock(:gall, id), do: Repo.one!(from(g in Gall, where: g.id == ^id, lock: "FOR UPDATE"))
  defp lock(:plant, id), do: Repo.one!(from(t in Taxon, where: t.id == ^id, lock: "FOR UPDATE"))

  # -- replay ----------------------------------------------------------------------

  @doc "The replay log key of a merge, by stable references (taken before it)."
  @spec replay_key(spec()) :: map()
  def replay_key({:gall, absorbed_id, survivor_id}) do
    %{
      "type" => "gall",
      "absorbed" => StableRef.gall(absorbed_id),
      "survivor" => StableRef.gall(survivor_id)
    }
  end

  def replay_key({:plant, absorbed_id, survivor_id}) do
    %{
      "type" => "plant",
      "absorbed" => StableRef.taxon(absorbed_id),
      "survivor" => StableRef.taxon(survivor_id)
    }
  end

  @doc "The merge a logged key names; `:done` when the absorbed record is gone already."
  @spec decode(map()) :: {:ok, spec()} | :done | {:error, term()}
  def decode(%{"type" => "gall", "absorbed" => absorbed, "survivor" => survivor}) do
    with {:ok, absorbed_id} <- StableRef.resolve_gall(absorbed),
         {:ok, survivor_id} <- StableRef.resolve_gall(survivor) do
      {:ok, {:gall, absorbed_id, survivor_id}}
    else
      {:error, _} = error -> if gone?(absorbed, &StableRef.resolve_gall/1), do: :done, else: error
    end
  end

  def decode(%{"type" => "plant", "absorbed" => absorbed, "survivor" => survivor}) do
    with {:ok, absorbed_id} <- StableRef.resolve_taxon(absorbed),
         {:ok, survivor_id} <- StableRef.resolve_taxon(survivor) do
      {:ok, {:plant, absorbed_id, survivor_id}}
    else
      {:error, _} = error ->
        if gone?(absorbed, &StableRef.resolve_taxon/1), do: :done, else: error
    end
  end

  def decode(key), do: {:error, {:unknown_merge, key}}

  # A merged plant's accepted name is the survivor's synonym, so it no
  # longer resolves as accepted: the merge is done.
  defp gone?(ref, resolve), do: match?({:error, _}, resolve.(ref))

  # -- merging Galls ---------------------------------------------------------------

  defp merge(actor, {:gall, a, s}, dry_run?), do: merge_galls(actor, a, s, dry_run?)
  defp merge(actor, {:plant, a, s}, dry_run?), do: merge_plants(actor, a, s, dry_run?)

  defp merge_galls(actor, a, s, dry_run?) do
    absorbed = Catalog.get_gall!(a)
    survivor = Catalog.get_gall!(s)
    absorbed_name = Gall.display_name(absorbed)

    rows = Catalog.facts_about_galls([a])
    refs = RecordRefs.find([a], Enum.map(rows, & &1.fact_id), [a], for: :merge)
    blockers = RecordRefs.blockers(refs, {:gall, a}, absorbed_name)
    if blockers != [] and not dry_run?, do: Repo.rollback({:blocked, blockers})

    before = standings(Enum.map(Catalog.facts_about_galls([s]), & &1.fact_id))
    {:ok, %{moves: moves, conflicts: conflicts}} = Catalog.move_gall_facts(actor, a, s)
    fact_map = Map.new(moves, &{&1.from, &1.to})

    :ok = RecordRefs.repoint(all_history(refs, dry_run?), %{a => s}, fact_map)
    {:ok, _} = Catalog.delete_gall_facts(actor, Enum.map(moves, & &1.from))

    note = merge_notes(actor, absorbed, survivor, dry_run?)
    images = Images.move_images({:gall, a}, {:gall, s})
    %{alias: alias_name} = actor |> Catalog.absorb_gall(a, s) |> ok_or_rollback()

    after_rows = Catalog.facts_about_galls([s])
    conflicts = live_conflicts(conflicts, after_rows)
    merge_info = %{"type" => "gall", "absorbed_id" => a, "survivor_id" => s}

    %{
      type: :gall,
      absorbed: %{id: a, name: absorbed_name, code: absorbed.gallformers_code},
      survivor: %{id: s, name: Gall.display_name(survivor), code: survivor.gallformers_code},
      facts: with_sources(moves),
      standings: standing_changes(before, after_rows),
      conflicts: Enum.map(conflicts, &conflict_entry(&1, after_rows)),
      queued:
        if(dry_run?,
          do: [],
          else:
            queue(
              conflicts,
              after_rows,
              fn _fact -> s end,
              merge_info,
              absorbed_name,
              Gall.display_name(survivor)
            )
        ),
      alias: alias_name,
      redirects: %{id: a, code: absorbed.gallformers_code},
      images: images,
      note: note,
      repointed:
        for(
          m <- moves,
          m.with_gall && m.outcome != :dropped,
          do: %{gall_id: m.with_gall, text: m.text}
        ),
      cleanup: RecordRefs.cleanup(refs),
      blockers: blockers
    }
  end

  # In a preview the blocking rows are re-pointed too (and rolled back), so
  # the Facts they name can go.
  defp all_history(refs, false), do: refs

  defp all_history(%{blocking: b, history: h}, true) do
    empty = %{items: [], edits: [], statements: []}

    %{
      blocking: empty,
      history: %{
        items: h.items ++ Enum.map(b.items, &%{&1 | status: :decided}),
        edits: h.edits ++ b.edits,
        statements: h.statements ++ b.statements
      }
    }
  end

  defp merge_notes(actor, absorbed, survivor, dry_run?) do
    survivor_text = Sources.gall_note_text(survivor.id)
    absorbed_text = Sources.gall_note_text(absorbed.id)

    {:ok, moved} = Sources.move_gall_notes(actor, absorbed.id, survivor.id)
    items = Enum.reduce(moved.duplicates, %{}, &Map.merge(&2, &1.items))
    {:ok, _} = Facts.repoint_evidence_items(actor, items)
    {:ok, _} = Sources.delete_note_documents(actor, Enum.map(moved.duplicates, & &1.document_id))

    cond do
      absorbed_text == nil ->
        :none

      survivor_text == nil ->
        :moved

      survivor_text == absorbed_text ->
        :kept

      dry_run? ->
        :appended

      true ->
        gallformers = Sources.get_gallformers_source() || Repo.rollback(:no_gallformers_source)

        text =
          survivor_text <>
            "\n\n## From the merged #{Gall.display_name(absorbed)} gall\n\n" <> absorbed_text

        actor
        |> Sources.store_note(gallformers, survivor.id, text, Date.utc_today())
        |> ok_or_rollback()

        :appended
    end
  end

  # -- merging plants --------------------------------------------------------------

  defp merge_plants(actor, a, s, dry_run?) do
    absorbed = Taxa.get_taxon!(a)
    survivor = Taxa.get_taxon!(s)
    absorbed_name = Taxa.accepted_name(absorbed)
    survivor_name = Taxa.accepted_name(survivor)

    rows = Catalog.facts_naming_taxa([a])
    acts = Taxa.act_facts_naming([a])
    refs = RecordRefs.find([a], Enum.map(rows ++ acts, & &1.fact_id), [], for: :merge)

    blockers =
      plant_blockers(absorbed, absorbed_name, acts) ++
        RecordRefs.blockers(refs, {:taxon, a}, absorbed_name)

    if blockers != [] and not dry_run?, do: Repo.rollback({:blocked, blockers})

    before = standings(Enum.map(Catalog.facts_naming_taxa([s]), & &1.fact_id))
    {:ok, %{moves: moves, conflicts: conflicts}} = Catalog.move_taxon_facts(actor, a, s)
    requalified = actor |> Catalog.requalify_galls(a, s) |> ok_or_rollback()
    fact_map = Map.new(moves, &{&1.from, &1.to})

    :ok = RecordRefs.repoint(all_history(refs, dry_run?), %{a => s}, fact_map)
    {:ok, _} = Catalog.delete_gall_facts(actor, Enum.map(moves, & &1.from))
    {:ok, _} = Taxa.delete_act_facts(actor, Enum.map(acts, & &1.fact_id))
    {:ok, _} = Facts.repoint_attribution_names(actor, a, s)

    images = Images.move_images({:taxon, a}, {:taxon, s})
    dropped_range = length(Ranges.get_places_for_taxon_with_precision(a))
    {:ok, _} = Ranges.update_taxon_places(actor, a, [])
    {:ok, names} = Taxa.merge_names(actor, a, s)
    {:ok, _} = Taxa.add_taxon_redirect(actor, a, s)
    actor |> Taxa.delete_taxon(a) |> ok_or_rollback()

    after_rows = Catalog.facts_naming_taxa([s])
    conflicts = live_conflicts(conflicts, after_rows)
    merge_info = %{"type" => "plant", "absorbed_id" => a, "survivor_id" => s}
    about = Map.new(after_rows, &{&1.fact_id, &1.about})

    gall_of = fn fact_id ->
      case about[fact_id] do
        {:gall, id} -> id
        _ -> nil
      end
    end

    %{
      type: :plant,
      absorbed: %{id: a, name: absorbed_name, rank: absorbed.rank},
      survivor: %{id: s, name: survivor_name, rank: survivor.rank},
      synonyms: names.synonyms,
      common_names: names.common_names,
      facts: with_sources(moves),
      standings: standing_changes(before, after_rows),
      conflicts: Enum.map(conflicts, &conflict_entry(&1, after_rows)),
      queued:
        if(dry_run?,
          do: [],
          else: queue(conflicts, after_rows, gall_of, merge_info, absorbed_name, survivor_name)
        ),
      galls_requalified: requalified,
      images: images,
      range: %{dropped: dropped_range},
      redirects: %{id: a},
      cleanup: RecordRefs.cleanup(refs),
      blockers: blockers
    }
  end

  defp plant_blockers(absorbed, name, acts) do
    children = Repo.all(from(t in Taxon, where: t.parent_id == ^absorbed.id, select: t.id))
    own = MapSet.new(Sources.own_source_ids())
    by_fact = Facts.source_ids_by_fact(Enum.map(acts, & &1.fact_id))
    record = {:taxon, absorbed.id}

    has_children =
      if children == [],
        do: [],
        else: [
          %{
            kind: :has_children,
            record: record,
            record_name: name,
            source: nil,
            count: length(children),
            text: "#{name} has #{length(children)} taxa under it",
            action: "Move them under the plant it is merged into first."
          }
        ]

    real =
      for act <- acts,
          source_id <- Map.get(by_fact, act.fact_id, []),
          not MapSet.member?(own, source_id),
          uniq: true,
          do: source_id

    sources = Deletion.sources(real)

    act_blockers =
      for source_id <- real do
        source = sources[source_id]

        %{
          kind: :source_facts,
          record: record,
          record_name: name,
          source: source,
          count: Enum.count(acts, &(source_id in Map.get(by_fact, &1.fact_id, []))),
          text: "#{source.name}'s taxonomic statements name #{name}",
          action:
            "A plant a Source treats taxonomically is not merged by hand: correct the statements first."
        }
      end

    groups =
      for %{group: group} <- Catalog.generation_groups_naming([absorbed.id]) do
        %{
          kind: :generation_group,
          record: record,
          record_name: name,
          source: nil,
          count: 1,
          text: "#{name} is in the #{group} generation group",
          action: "Take it out of the group first."
        }
      end

    has_children ++ act_blockers ++ groups
  end

  # -- a lump's absorbed taxon (`f923`) --------------------------------------------

  @doc """
  Moves what the Catalog and the import tables hold of taxon `absorbed_id`
  onto `survivor_id`, inside `Gallformers.Taxa.merge/3`'s transaction (a
  lump; `Gallformers.Import.TaxonMerges` calls it on the `:merge` event):
  the gall Facts naming it (its Inducer Facts above all) move as a plant
  merge's do, keeping their attributions and `name_as_written` and
  combining with the survivor's same Fact; same-date ties that brings
  about become curator questions; the import rows naming it or its Facts
  (`act_fact_map`: its taxonomic-act Facts to the survivor's) are
  re-pointed; its images move over.

  `{:error, {:blocked, blockers}}` when an open question or a package
  under review names it (`Gallformers.Import.RecordRefs`): nothing is moved.
  """
  @spec repoint_lumped_taxon(Actor.t(), integer(), integer(), map(), map()) ::
          :ok | {:error, {:blocked, [Deletion.blocker()]}}
  def repoint_lumped_taxon(%Actor{} = actor, absorbed_id, survivor_id, act_fact_map, names) do
    rows = Catalog.facts_naming_taxa([absorbed_id])
    fact_ids = Enum.map(rows, & &1.fact_id) ++ Map.keys(act_fact_map)
    refs = RecordRefs.find([absorbed_id], fact_ids, [], for: :merge)

    case RecordRefs.blockers(refs, {:taxon, absorbed_id}, names.absorbed) do
      [] -> move_lumped(actor, refs, {absorbed_id, survivor_id}, act_fact_map, names)
      blockers -> {:error, {:blocked, blockers}}
    end
  end

  defp move_lumped(actor, refs, {absorbed_id, survivor_id}, act_fact_map, names) do
    {:ok, %{moves: moves, conflicts: conflicts}} =
      Catalog.move_taxon_facts(actor, absorbed_id, survivor_id)

    fact_map = moves |> Map.new(&{&1.from, &1.to}) |> Map.merge(act_fact_map)
    :ok = RecordRefs.repoint(refs, %{absorbed_id => survivor_id}, fact_map)
    {:ok, _} = Catalog.delete_gall_facts(actor, Enum.map(moves, & &1.from))
    _images = Images.move_images({:taxon, absorbed_id}, {:taxon, survivor_id})

    after_rows = Catalog.facts_naming_taxa([survivor_id])
    merge_info = %{"type" => "lump", "absorbed_id" => absorbed_id, "survivor_id" => survivor_id}

    conflicts
    |> live_conflicts(after_rows)
    |> queue(after_rows, gall_of(after_rows), merge_info, names.absorbed, names.survivor)

    :ok
  end

  # The Gall each Fact among `rows` is about, by Fact ID (nil for none).
  defp gall_of(rows) do
    about = Map.new(rows, &{&1.fact_id, &1.about})

    fn fact_id ->
      case about[fact_id] do
        {:gall, id} -> id
        _ -> nil
      end
    end
  end

  # -- shared ----------------------------------------------------------------------

  defp with_sources(moves) do
    sources =
      moves
      |> Enum.flat_map(& &1.sources)
      |> Enum.map(& &1.id)
      |> Enum.uniq()
      |> Deletion.sources()

    Enum.map(moves, fn move ->
      %{
        move
        | sources: Enum.map(move.sources, &Map.merge(sources[&1.id], %{outcome: &1.outcome}))
      }
    end)
  end

  defp standings([]), do: %{}

  defp standings(fact_ids),
    do: Map.new(Repo.all(from(f in Fact, where: f.id in ^fact_ids, select: {f.id, f.standing})))

  # The survivor's Facts whose standing the merge changed (recency).
  defp standing_changes(before, after_rows) do
    now = standings(Enum.map(after_rows, & &1.fact_id))

    for row <- after_rows,
        from = before[row.fact_id],
        from != nil and from != now[row.fact_id] do
      %{fact_id: row.fact_id, text: row.text, from: from, to: now[row.fact_id]}
    end
  end

  defp live_conflicts(conflicts, after_rows) do
    live = MapSet.new(after_rows, & &1.fact_id)

    conflicts
    |> Enum.uniq_by(&{&1.type, Enum.sort(&1.fact_ids)})
    |> Enum.filter(fn c -> Enum.all?(c.fact_ids, &MapSet.member?(live, &1)) end)
  end

  defp conflict_entry(conflict, rows) do
    %{type: conflict.type, fact_ids: conflict.fact_ids, text: conflict_text(conflict, rows)}
  end

  defp conflict_text(conflict, rows) do
    texts = Map.new(rows, &{&1.fact_id, &1.text})
    conflict.fact_ids |> Enum.map(&(texts[&1] || "Fact #{&1}")) |> Enum.sort() |> Enum.join(" | ")
  end

  @doc false
  @spec statement_ref(String.t()) :: String.t()
  def statement_ref(text), do: "merge:" <> text

  @doc "The same-date conflict a merge brought about, by its Gall (or nil) and statement ref."
  @spec find_conflict(integer() | nil, String.t()) :: QueueItem.t() | nil
  def find_conflict(gall_id, statement_ref) do
    from(q in QueueItem,
      where:
        q.kind == :same_date_conflict and is_nil(q.package_id) and
          q.statement_ref == ^statement_ref,
      order_by: [desc: q.id]
    )
    |> Repo.all()
    |> Enum.find(&(&1.subject["gall_id"] == gall_id))
  end

  # Same-date ties the merge brought about, as open curator questions of no
  # package (decided like any same-date conflict).
  defp queue(conflicts, rows, gall_of, merge_info, absorbed_name, survivor_name) do
    for conflict <- conflicts do
      %QueueItem{}
      |> QueueItem.create_changeset(%{
        kind: :same_date_conflict,
        statement_ref: statement_ref(conflict_text(conflict, rows)),
        subject: %{
          "type" => Atom.to_string(conflict.type),
          "fact_id" => hd(conflict.fact_ids),
          "fact_ids" => conflict.fact_ids,
          "gall_id" => gall_of.(hd(conflict.fact_ids)),
          "merge" => merge_info
        },
        proposal: %{},
        reason:
          "Merging #{absorbed_name} into #{survivor_name}: Sources with the same date disagree; " <>
            "the Fact keeps its standing until decided (a dated Gallformers statement settles it)"
      })
      |> Repo.insert()
      |> ok_or_rollback()
      |> Map.fetch!(:id)
    end
  end

  defp ok_or_rollback({:ok, value}), do: value
  defp ok_or_rollback({:error, reason}), do: Repo.rollback(reason)
end
