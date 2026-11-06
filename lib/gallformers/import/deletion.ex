defmodule Gallformers.Import.Deletion do
  @moduledoc """
  Deleting a Gall or a taxon (matter `ec2c`, "Deletes"): for a record that
  should never have existed (a test entry, a duplicate typed by mistake, a
  misspelled genus, an empty placeholder). A record the same as another is
  merged instead (`Gallformers.Import.Merge`).

  ## The rule

  A record may be deleted only when nothing from a real Source rests on
  it: every Fact that goes with it is attributed only by Gallformers' own
  Sources (`Gallformers.Sources.own_source_ids/0`: the "Gallformers legacy
  data" Source and the Gallformers Source). Besides a real Source's Facts,
  a delete is blocked by a real Source naming a taxon in its statements, a
  real Source's Trait terms waiting on a Gall, a Gall whose name a plant
  qualifies, a generation group listing a taxon, and an open review
  question or a package under review naming any of them
  (`Gallformers.Import.RecordRefs`; IDs held in JSON count). Each blocker
  says what to do instead.

  ## What goes, by operation

    * `:delete` — a Gall: its Facts (and the Relationships it is in, with
      their qualifiers), images, Gallformers note versions, legacy
      citations and Trait terms waiting on it.
    * `:cascade` — a family or genus (and a species or below, with its
      infraspecific taxa): every taxon under it, the Galls named after any
      of them (an Inducer Fact naming one), and all of their Facts, the
      taxa's images and Host ranges. All or nothing: a blocker anywhere
      blocks the whole delete.
    * `:collapse` — any other rank (subfamily, tribe, subgenus, …): its
      children are re-placed under its parent (`Gallformers.Taxa.place/3`,
      as the taxonomy admin's edits are in phase 1), then it goes.
    * `:blocked` — a plant section with species under it: they must be
      moved first.

  ## Deleting

  `record/2` takes the tree lock and locks the record, works the impact
  out again and refuses if anything blocks; then cleans up the import rows
  that name it (`Gallformers.Import.RecordRefs.clean_up/3`), deletes, logs
  a `:deletion` replay entry by stable reference, and — after the commit —
  removes the images' stored files and broadcasts
  `{:records_deleted, %{galls, taxa, by}}` on `"catalog:records"`.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Facts
  alias Gallformers.Images
  alias Gallformers.Import.RecordRefs
  alias Gallformers.Import.ReplayLog
  alias Gallformers.Import.StableRef
  alias Gallformers.Ranges
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon

  @topic "catalog:records"

  @type subject :: {:gall, integer()} | {:taxon, integer()}

  @typedoc "A Source as the impact names it: its title and short name (\"Weld 1959\")."
  @type source :: %{id: integer(), title: String.t(), name: String.t()}

  @typedoc "Something that blocks a delete or merge, with what to do instead."
  @type blocker :: %{
          kind:
            :source_facts
            | :source_names
            | :waiting_terms
            | :host_qualifier
            | :generation_group
            | :section_has_species
            | :has_children
            | :open_question
            | :package_under_review,
          record: subject(),
          record_name: String.t(),
          source: source() | nil,
          count: non_neg_integer(),
          text: String.t(),
          action: String.t()
        }

  @typedoc "What deleting a record would do (`impact/1`); see the module doc."
  @type impact :: %{
          subject: %{
            required(:type) => :gall | :taxon,
            required(:id) => integer(),
            required(:name) => String.t(),
            optional(:rank) => Rank.t(),
            optional(:kingdom) => String.t() | nil
          },
          operation: :delete | :cascade | :collapse | :blocked,
          deletable: boolean(),
          galls: [%{id: integer(), name: String.t()}],
          taxa: [%{id: integer(), name: String.t(), rank: Rank.t()}],
          children: [%{id: integer(), name: String.t(), rank: Rank.t()}],
          parent: %{id: integer(), name: String.t(), rank: Rank.t()} | nil,
          facts: [
            %{
              fact_id: integer(),
              kind: String.t(),
              about: subject(),
              rests_on: subject(),
              text: String.t(),
              sources: [source()]
            }
          ],
          sources: [
            %{
              id: integer(),
              title: String.t(),
              name: String.t(),
              own: boolean(),
              facts: pos_integer()
            }
          ],
          images: [%{id: integer(), path: String.t(), owner: subject()}],
          notes: [%{gall_id: integer(), versions: pos_integer()}],
          legacy_citations: [%{gall_id: integer(), source: source()}],
          cleanup: [%{kind: atom(), count: pos_integer(), text: String.t()}],
          blockers: [blocker()]
        }

  @doc "The PubSub topic deletes and merges are broadcast on."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc "What deleting `subject` would do and what blocks it, or `{:error, :not_found}`."
  @spec impact(subject()) :: {:ok, impact()} | {:error, :not_found}
  def impact(subject) do
    with {:ok, plan} <- plan(subject), do: {:ok, plan |> work_out() |> Map.fetch!(:impact)}
  end

  @doc """
  Deletes `subject` (see the module doc). `{:error, :not_found}` when it is
  gone already (deleted by someone else); `{:error, {:blocked, blockers}}`
  when something blocks it now, nothing deleted.
  """
  @spec record(Actor.t(), subject()) ::
          {:ok, %{impact: impact(), storage_errors: [{String.t(), term()}]}}
          | {:error, :not_found | {:blocked, [blocker()]} | term()}
  def record(%Actor{} = actor, subject) do
    Audit.transaction(actor, "import.record_deletion", fn ->
      Taxa.lock_tree()
      lock(subject) || Repo.rollback(:not_found)
      key = replay_key(subject)
      {:ok, plan} = plan(subject)
      work = work_out(plan)

      if not work.impact.deletable, do: Repo.rollback({:blocked, work.impact.blockers})

      images = carry_out(actor, plan, work)
      ReplayLog.append!(:deletion, key, %{})
      {work.impact, images}
    end)
    |> case do
      {:ok, {impact, images}} ->
        errors = images |> Enum.map(& &1.path) |> Images.delete_files()

        broadcast(
          {:records_deleted,
           %{
             galls: Enum.map(impact.galls, & &1.id),
             taxa: Enum.map(impact.taxa, & &1.id),
             by: actor.name
           }}
        )

        {:ok, %{impact: impact, storage_errors: errors}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  @spec broadcast(term()) :: :ok
  def broadcast(message), do: Phoenix.PubSub.broadcast(Gallformers.PubSub, @topic, message)

  # -- replay ----------------------------------------------------------------------

  @doc "The replay log key of deleting `subject`, by stable reference (taken before the delete)."
  @spec replay_key(subject()) :: map()
  def replay_key({:gall, id}), do: %{"type" => "gall", "gall" => StableRef.gall(id)}
  def replay_key({:taxon, id}), do: %{"type" => "taxon", "taxon" => StableRef.taxon(id)}

  @doc "The subject a logged key names; `:done` when it is gone already."
  @spec decode(map()) :: {:ok, subject()} | :done | {:error, term()}
  def decode(%{"type" => "gall", "gall" => ref}) do
    case StableRef.resolve_gall(ref) do
      {:ok, id} -> {:ok, {:gall, id}}
      {:error, _not_found} -> :done
    end
  end

  def decode(%{"type" => "taxon", "taxon" => ref}) do
    case StableRef.resolve_taxon(ref) do
      {:ok, id} -> {:ok, {:taxon, id}}
      {:error, {:taxon_not_found, _}} -> :done
      {:error, reason} -> {:error, reason}
    end
  end

  def decode(key), do: {:error, {:unknown_deletion, key}}

  # -- the plan --------------------------------------------------------------------

  defp lock({:gall, id}), do: Repo.one(from(g in Gall, where: g.id == ^id, lock: "FOR UPDATE"))
  defp lock({:taxon, id}), do: Repo.one(from(t in Taxon, where: t.id == ^id, lock: "FOR UPDATE"))

  defp plan({:gall, id}) do
    case Catalog.get_gall(id) do
      nil ->
        {:error, :not_found}

      gall ->
        {:ok,
         %{
           subject: {:gall, id},
           info: %{type: :gall, id: id, name: Gall.display_name(gall)},
           operation: :delete,
           gall_ids: [id],
           taxa: [],
           children: [],
           parent: nil,
           section_species: []
         }}
    end
  end

  defp plan({:taxon, id}) do
    case Taxa.get_taxon(id) do
      nil ->
        {:error, :not_found}

      taxon ->
        descendants = Taxa.descendants(taxon)
        operation = operation(taxon, descendants)
        taxa = if operation == :cascade, do: [taxon | descendants], else: [taxon]

        {:ok,
         %{
           subject: {:taxon, id},
           info: %{
             type: :taxon,
             id: id,
             name: Taxa.accepted_name(taxon),
             rank: taxon.rank,
             kingdom: taxon.kingdom
           },
           operation: operation,
           gall_ids:
             if(operation == :blocked,
               do: [],
               else: taxa |> Enum.map(& &1.id) |> Catalog.galls_named_after()
             ),
           taxa: taxa,
           children: Enum.filter(descendants, &(&1.parent_id == id)),
           parent: taxon.parent_id && Taxa.get_taxon(taxon.parent_id),
           section_species:
             if(operation == :blocked,
               do: Enum.filter(descendants, &(&1.rank in Rank.species_and_below())),
               else: []
             )
         }}
    end
  end

  defp operation(%Taxon{kingdom: "Plantae", rank: :section}, descendants) do
    if Enum.any?(descendants, &(&1.rank in Rank.species_and_below())),
      do: :blocked,
      else: :collapse
  end

  defp operation(%Taxon{rank: rank}, _descendants) do
    if rank in [:family, :genus] or rank in Rank.species_and_below(),
      do: :cascade,
      else: :collapse
  end

  # Everything the plan touches, worked out: the impact, and what carrying
  # it out needs.
  defp work_out(plan) do
    gall_ids = plan.gall_ids
    taxon_ids = Enum.map(plan.taxa, & &1.id)

    rows =
      (Catalog.facts_about_galls(gall_ids) ++
         Catalog.facts_naming_taxa(taxon_ids) ++
         Enum.map(Taxa.act_facts_naming(taxon_ids), &act_row/1))
      |> Enum.uniq_by(& &1.fact_id)

    fact_ids = Enum.map(rows, & &1.fact_id)
    by_fact = Facts.source_ids_by_fact(fact_ids)
    own = MapSet.new(Sources.own_source_ids())
    deleted_facts = MapSet.new(fact_ids)

    names =
      Enum.reject(Facts.names_of_taxa(taxon_ids), &MapSet.member?(deleted_facts, &1.fact_id))

    records = Catalog.gall_records(gall_ids)
    refs = RecordRefs.find(gall_ids ++ taxon_ids, fact_ids, gall_ids)

    owners = Enum.map(gall_ids, &{:gall, &1}) ++ Enum.map(taxon_ids, &{:taxon, &1})

    images =
      Enum.flat_map(owners, fn owner -> Enum.map(Images.list_images(owner), &{owner, &1}) end)

    source_ids =
      Enum.uniq(
        List.flatten(Map.values(by_fact)) ++
          Enum.map(names, & &1.source_id) ++
          Enum.map(records.legacy_citations, & &1.source_id) ++
          Enum.map(records.waiting_terms, & &1.source_id)
      )

    sources = sources(source_ids)
    record_names = record_names(gall_ids, plan.taxa ++ plan.children ++ List.wrap(plan.parent))

    facts =
      Enum.map(rows, fn row ->
        Map.put(row, :sources, Enum.map(Map.get(by_fact, row.fact_id, []), &sources[&1]))
      end)

    blockers =
      section_blockers(plan, record_names) ++
        fact_blockers(plan, facts, own, record_names) ++
        name_blockers(names, own, sources, record_names) ++
        term_blockers(plan, records.waiting_terms, own, sources, record_names) ++
        qualifier_blockers(taxon_ids, gall_ids, record_names) ++
        group_blockers(taxon_ids, record_names) ++
        RecordRefs.blockers(refs, plan.subject, plan.info.name)

    own_names = Enum.filter(names, &MapSet.member?(own, &1.source_id))

    name_cleanup =
      if own_names == [],
        do: [],
        else: [
          %{
            kind: :attribution_name,
            count: length(own_names),
            text: "#{length(own_names)} Gallformers statement name(s) of it"
          }
        ]

    impact = %{
      subject: plan.info,
      operation: plan.operation,
      deletable: blockers == [] and plan.operation != :blocked,
      galls:
        Enum.map(gall_ids, &%{id: &1, name: record_names[{:gall, &1}]})
        |> Enum.sort_by(&{&1.name, &1.id}),
      taxa: Enum.map(plan.taxa, &taxon_entry(&1, record_names)),
      children: Enum.map(plan.children, &taxon_entry(&1, record_names)),
      parent: plan.parent && taxon_entry(plan.parent, record_names),
      facts: facts,
      sources: source_summary(facts, sources, own),
      images: Enum.map(images, fn {owner, i} -> %{id: i.id, path: i.path, owner: owner} end),
      notes:
        for(
          id <- gall_ids,
          n = length(Sources.list_gall_notes(id)),
          n > 0,
          do: %{gall_id: id, versions: n}
        ),
      legacy_citations:
        Enum.map(records.legacy_citations, &%{gall_id: &1.gall_id, source: sources[&1.source_id]}),
      cleanup: RecordRefs.cleanup(refs) ++ name_cleanup,
      blockers: blockers
    }

    %{impact: impact, refs: refs, rows: rows, own_names: own_names, owners: owners}
  end

  defp act_row(%{fact_id: id, kind: kind, taxon_id: taxon_id, text: text}),
    do: %{
      fact_id: id,
      kind: kind,
      about: {:taxon, taxon_id},
      rests_on: {:taxon, taxon_id},
      text: text
    }

  defp taxon_entry(taxon, names),
    do: %{id: taxon.id, name: names[{:taxon, taxon.id}], rank: taxon.rank}

  @doc false
  @spec sources([integer()]) :: %{integer() => source()}
  def sources(ids) do
    ids
    |> Sources.list_sources_by_id()
    |> Map.new(&{&1.id, %{id: &1.id, title: &1.title, name: Sources.short_name(&1) || &1.title}})
  end

  @doc false
  @spec record_names([integer()], [Taxon.t()]) :: %{subject() => String.t()}
  def record_names(gall_ids, taxa) do
    galls =
      for g <- Catalog.list_galls_by_id(gall_ids),
          into: %{},
          do: {{:gall, g.id}, Gall.display_name(g)}

    taxa =
      taxa
      |> Enum.map(& &1.id)
      |> Enum.uniq()
      |> Taxa.lineages()
      |> Map.new(fn {id, lineage} ->
        {{:taxon, id}, lineage |> List.last() |> Map.fetch!(:name)}
      end)

    Map.merge(galls, taxa)
  end

  defp record_name(names, {type, id} = record) do
    names[record] ||
      case type do
        :gall ->
          with(%Gall{} = g <- Catalog.get_gall(id), do: Gall.display_name(g)) || "Gall #{id}"

        :taxon ->
          Taxa.accepted_name(id) || "taxon #{id}"
      end
  end

  defp source_summary(facts, sources, own) do
    facts
    |> Enum.flat_map(& &1.sources)
    |> Enum.frequencies_by(& &1.id)
    |> Enum.map(fn {id, n} ->
      Map.merge(sources[id], %{own: MapSet.member?(own, id), facts: n})
    end)
    |> Enum.sort_by(&{&1.own, &1.name})
  end

  # -- blockers --------------------------------------------------------------------

  defp section_blockers(%{operation: :blocked} = plan, _names) do
    n = length(plan.section_species)

    [
      %{
        kind: :section_has_species,
        record: plan.subject,
        record_name: plan.info.name,
        source: nil,
        count: n,
        text: "#{plan.info.name} has #{plural(n, "species", "species")} in it",
        action:
          "Move #{if n == 1, do: "it", else: "them"} to another section or to the genus first."
      }
    ]
  end

  defp section_blockers(_plan, _names), do: []

  defp fact_blockers(plan, facts, own, names) do
    for fact <- facts,
        source <- fact.sources,
        not MapSet.member?(own, source.id) do
      {fact.rests_on, source}
    end
    |> Enum.frequencies()
    |> Enum.sort_by(fn {{record, source}, _n} -> {record, source.name} end)
    |> Enum.map(fn {{record, source}, n} ->
      name = record_name(names, record)

      action =
        if record == plan.subject and plan.operation == :delete,
          do:
            "To delete it, merge it into the right Gall, or correct where " <>
              "#{source.name}'s statements were attached.",
          else:
            "To delete it, merge it or move it first, or correct where " <>
              "#{source.name}'s statements were attached."

      %{
        kind: :source_facts,
        record: record,
        record_name: name,
        source: source,
        count: n,
        text: "#{plural(n, "Fact", "Facts")} from #{source.name} rest on #{name}",
        action: action
      }
    end)
  end

  defp name_blockers(names, own, sources, record_names) do
    names
    |> Enum.reject(&MapSet.member?(own, &1.source_id))
    |> Enum.frequencies_by(&{&1.taxon_id, &1.source_id})
    |> Enum.sort()
    |> Enum.map(fn {{taxon_id, source_id}, n} ->
      source = sources[source_id]
      name = record_name(record_names, {:taxon, taxon_id})

      %{
        kind: :source_names,
        record: {:taxon, taxon_id},
        record_name: name,
        source: source,
        count: n,
        text: "#{source.name} names #{name} in #{plural(n, "statement", "statements")}",
        action:
          "Merge it or move it first, or correct where #{source.name}'s statements were attached."
      }
    end)
  end

  defp term_blockers(_plan, terms, own, sources, record_names) do
    for %{gall_id: gall_id, source_id: source_id, count: n} <- terms,
        not MapSet.member?(own, source_id) do
      source = sources[source_id]
      name = record_name(record_names, {:gall, gall_id})

      %{
        kind: :waiting_terms,
        record: {:gall, gall_id},
        record_name: name,
        source: source,
        count: n,
        text: "#{plural(n, "Trait term", "Trait terms")} of #{source.name} wait on #{name}",
        action: "Merge it into the right Gall, or settle the terms first."
      }
    end
  end

  defp qualifier_blockers(taxon_ids, gall_ids, record_names) do
    for gall <- Catalog.galls_qualified_by(taxon_ids), gall.id not in gall_ids do
      plant = record_name(record_names, {:taxon, gall.taxon_id})

      %{
        kind: :host_qualifier,
        record: {:taxon, gall.taxon_id},
        record_name: plant,
        source: nil,
        count: 1,
        text: "#{gall.name} is named for #{plant}",
        action: "Change that Gall's name parts first."
      }
    end
  end

  defp group_blockers(taxon_ids, record_names) do
    for %{group: group, taxon_id: id} <- Catalog.generation_groups_naming(taxon_ids) do
      name = record_name(record_names, {:taxon, id})

      %{
        kind: :generation_group,
        record: {:taxon, id},
        record_name: name,
        source: nil,
        count: 1,
        text: "#{name} is in the #{group} generation group",
        action: "Take it out of the group first."
      }
    end
  end

  defp plural(1, one, _many), do: "1 #{one}"
  defp plural(n, _one, many), do: "#{n} #{many}"

  # -- carrying it out ---------------------------------------------------------------

  defp carry_out(actor, plan, work) do
    gall_ids = plan.gall_ids
    taxon_ids = Enum.map(plan.taxa, & &1.id)
    fact_ids = Enum.map(work.rows, & &1.fact_id)

    :ok = RecordRefs.clean_up(work.refs, gall_ids ++ taxon_ids, fact_ids)

    if plan.operation == :collapse do
      parent_id = plan.parent && plan.parent.id
      for child <- plan.children, do: actor |> Taxa.place(child.id, parent_id) |> ok_or_rollback()
    end

    {:ok, _} = Facts.delete_attribution_names(actor, Enum.map(work.own_names, & &1.id))

    {gall_facts, taxon_facts} =
      Enum.split_with(work.rows, &String.starts_with?(&1.kind, "gall_"))

    {:ok, _} = Catalog.delete_gall_facts(actor, Enum.map(gall_facts, & &1.fact_id))
    {:ok, _} = Taxa.delete_act_facts(actor, Enum.map(taxon_facts, & &1.fact_id))

    images = Images.delete_owner_images(work.owners)
    {:ok, _} = Sources.delete_gall_notes(actor, gall_ids)
    actor |> Catalog.delete_galls(gall_ids) |> ok_or_rollback()

    # The deepest first, so each has no children left when it goes.
    for taxon <- Enum.reverse(plan.taxa) do
      {:ok, _} = Ranges.update_taxon_places(actor, taxon.id, [])
      actor |> Taxa.delete_taxon(taxon.id) |> ok_or_rollback()
    end

    images
  end

  defp ok_or_rollback({:ok, value}), do: value
  defp ok_or_rollback({:error, reason}), do: Repo.rollback(reason)
end
