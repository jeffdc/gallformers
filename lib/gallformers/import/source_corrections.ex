defmodule Gallformers.Import.SourceCorrections do
  @moduledoc """
  Corrections in place to a Source's applied Facts (matter `f14c`, "The
  Source's Facts after approval", agreed with Jeff 2026-11-04), for errors
  made in the original ingestion, the legacy data's included: retired
  (matter `87a1`, Jeff 2026-11-08). A fix today is a reading fix of the
  Source, a package of it through the one ingestion path
  (`Gallformers.Curation.fix_reading/3`,
  `Gallformers.Curation.fix_taxonomic_reading/6`). What stays is the
  replay: the corrections logged before still replay (`replay/3`), made
  again as they were, and are listed with the Source's fixes (`list/1`).

  A correction never edits a Fact: a Fact can hold several Sources'
  attributions. The curator **withdraws the Source's attribution** where
  the Source didn't say it (`Gallformers.Facts.remove_attribution/3`), and
  **states what it did say** as that Source's statement
  (`Gallformers.Catalog.assert_fact/4`, `Gallformers.Taxa.assert_act/4`),
  the Source's words carried over from the withdrawn statement (its stance,
  date, words as written, evidence, names with the corrected taxon, and
  Observations). Other Sources' statements of the Fact stay.

  ## Corrections

    * `:withdraw` — the Source didn't say it: its statement is removed. A
      Fact no Source states any more is no longer current.
    * `{:host, plant_id}` — a Host statement (`host_of`) moves to that
      plant (any rank).
    * `{:values, [value, ...]}` — a Trait statement moves to these values
      of its Trait, one statement each, the Source's term kept; a value it
      had stays.
    * `{:parent, taxon_id | nil}` — a placement statement moves to another
      parent (nil: at the root).
    * `{:accepted, taxon_id}` — a synonymy statement moves to another
      accepted taxon.

  The gall Facts that can be corrected are those with a stable key
  (`Gallformers.Import.CurationNotes.fact_key/1`): Inducers, Hosts,
  Traits, aliases, range adjustments and recorded occurrences; every
  taxonomic statement can. Where the Source already states the Fact a
  correction moves to, its statement there stands. A correction that
  changes nothing is `{:error, :unchanged}`.

  ## Taxonomic statements

  A taxonomic statement stated anew follows the acceptance rules
  (`Gallformers.Facts.needs_acceptance?/2`): a paper's awaits a curator
  and is asked in the taxonomy queue (`Gallformers.Import.TaxonomyQueue`),
  unless the correcting curator accepts it in the same step
  (`accept: true`, through `Gallformers.Import.TaxonomicDecisions`); one of
  Gallformers' own Sources counts at once. A withdrawn statement's open
  question goes with it.

  ## Recorded, audited, replayed

  Each correction runs in one transaction audited as the curator
  (`"import.correct_source_fact"`), with a required note of why. It is
  recorded (`Gallformers.Import.SourceCorrection`, which moves the Source's
  Updated date) and logged for replay (`:source_correction`), keyed by the
  Source (its title), the corrected Fact by stable references (a gall
  Fact's Gall and stable key; a taxonomic act's kind and natural key:
  `Gallformers.Import.TaxonomicDecisions.encode_key/2`), the payload the
  correction (`"op"`, `"to"`), the note and its author. Replay makes the
  correction again on the Fact found by those keys, carrying over the
  Source's words found there; a correction already made is done. An
  acceptance in the same step is the `:taxonomic_decision` entry after it.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Catalog.Facts.AliasFact
  alias Gallformers.Catalog.Facts.DescriptionFact
  alias Gallformers.Catalog.Facts.OccurrenceFact
  alias Gallformers.Catalog.Facts.RangeFact
  alias Gallformers.Catalog.Facts.RelationshipFact
  alias Gallformers.Catalog.Facts.TraitFact
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Facts.Fact
  alias Gallformers.Import.CurationNotes
  alias Gallformers.Import.FactsView
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.ReplayLog
  alias Gallformers.Import.SourceCorrection
  alias Gallformers.Import.StableRef
  alias Gallformers.Import.TaxonomicDecisions
  alias Gallformers.Import.TaxonomyQueue
  alias Gallformers.Places
  alias Gallformers.Repo
  alias Gallformers.Sources.PartialDate
  alias Gallformers.Taxa

  @typedoc "A correction to a Source's statement of a Fact."
  @type correction ::
          :withdraw
          | {:host, integer()}
          | {:values, [String.t()]}
          | {:parent, integer() | nil}
          | {:accepted, integer()}

  @typedoc "What a correction did."
  @type result :: %{
          correction: SourceCorrection.t(),
          withdrawn: [integer()],
          asserted: [integer()],
          conflicts: [Facts.Standing.Conflict.t()]
        }

  @typedoc "Why a correction was refused."
  @type error ::
          :note_required
          | :not_found
          | :not_correctable
          | :unchanged
          | String.t()
          | Ecto.Changeset.t()
          | term()

  # -- correcting ----------------------------------------------------------------

  @doc """
  Corrects Source `source_id`'s statement of Fact `fact_id` with
  `correction` (see the module doc), `note` saying why (required), as
  `actor`. Options: `accept: true` accepts a taxonomic statement stated
  anew in the same step; `author_name` the correction's author. Called by
  `replay/3` only: a fix today is a reading fix (matter `87a1`).
  """
  @spec correct(Actor.t(), integer(), integer(), correction(), String.t() | nil, keyword()) ::
          {:ok, result()} | {:error, error()}
  def correct(%Actor{} = actor, source_id, fact_id, correction, note, opts \\ [])
      when is_integer(source_id) and is_integer(fact_id) do
    case String.trim(note || "") do
      "" -> {:error, :note_required}
      note -> run(actor, source_id, fact_id, correction, note, opts)
    end
  end

  defp run(actor, source_id, fact_id, correction, note, opts) do
    Audit.transaction(actor, "import.correct_source_fact", fn ->
      with {:ok, attribution} <- attribution(fact_id, source_id),
           {:ok, subject} <- subject(source_id, fact_id),
           {:ok, plan} <- plan(subject, correction),
           :ok <- changes?(plan, source_id),
           key = replay_key(source_id, subject),
           summary = describe(subject, attribution),
           change = describe_change(correction),
           {:ok, done} <- carry_out(actor, attribution, subject, plan) do
        ReplayLog.append!(:source_correction, key, payload(correction, note, actor, opts))
        :ok = settle_acceptance(actor, subject, done.new_attributions, opts)

        record =
          actor
          |> SourceCorrection.create_changeset(
            %{
              source_id: source_id,
              kind: kind_of(correction),
              summary: summary,
              change: change,
              note: note
            },
            Keyword.take(opts, [:author_name])
          )
          |> Repo.insert()
          |> ok_or_rollback()

        %{
          correction: record,
          withdrawn: done.withdrawn,
          asserted: done.asserted,
          conflicts: done.conflicts
        }
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp attribution(fact_id, source_id) do
    case Facts.get_attribution(fact_id, source_id) do
      nil -> {:error, :not_found}
      attribution -> {:ok, Repo.preload(attribution, [:evidence, :names, :observations])}
    end
  end

  # -- what is corrected -----------------------------------------------------------

  # The Fact as a stable key: a gall Fact's Gall and Gall page key, or a
  # taxonomic act's kind and natural key.
  defp subject(source_id, fact_id) do
    case Repo.get(Fact, fact_id) do
      %Fact{kind: "taxon_" <> _} -> taxon_subject(fact_id)
      %Fact{kind: "gall_" <> _} -> gall_subject(source_id, fact_id)
      _ -> {:error, :not_correctable}
    end
  end

  defp taxon_subject(fact_id) do
    case Taxa.act_fact(fact_id) do
      {kind, key} -> {:ok, %{type: :taxon, fact_id: fact_id, kind: kind, key: key}}
      nil -> {:error, :not_correctable}
    end
  end

  defp gall_subject(source_id, fact_id) do
    with [entry] <- FactsView.entries(source_id, [fact_id]),
         gall_id when is_integer(gall_id) <- entry.gall,
         {:ok, gall_key} <- entry_key(entry) do
      {:ok, %{type: :gall, fact_id: fact_id, gall_id: gall_id, gall_key: gall_key}}
    else
      _ -> {:error, :not_correctable}
    end
  end

  @doc """
  The Gall page key (`Gallformers.Catalog.gall_fact_key/0`) of a gall
  Fact's entry in the Facts view (`Gallformers.Import.FactsView`), or
  `:error` for one with no stable key.
  """
  @spec entry_key(map()) :: {:ok, Gallformers.Catalog.gall_fact_key()} | :error
  def entry_key(%{kind: :relationship, value: %{type: "host_of", subject: %{taxon_id: id}}})
      when is_integer(id),
      do: {:ok, {:host, id}}

  def entry_key(%{kind: :relationship, value: %{type: "inducer_of", subject: %{taxon_id: id}}})
      when is_integer(id),
      do: {:ok, {:inducer, id}}

  def entry_key(%{kind: :trait, value: %{trait: trait, value: value}})
      when is_binary(trait) and is_binary(value),
      do: {:ok, {:trait, trait, value}}

  def entry_key(%{kind: :alias, value: %{name: name}}), do: {:ok, {:alias, name}}

  def entry_key(%{kind: :range, value: %{adjustment: adjustment, place: %{id: id}}}),
    do: {:ok, {:range, adjustment, id}}

  def entry_key(%{kind: :occurrence, value: %{place: %{id: id}}}), do: {:ok, {:occurrence, id}}
  def entry_key(_entry), do: :error

  # -- the plan ---------------------------------------------------------------------

  # What a correction does: whether the Source's statement here is
  # withdrawn, the Facts (by kind and natural key) it is stated on instead,
  # and how the names' taxa change.
  defp plan(_subject, :withdraw), do: {:ok, %{withdraw?: true, targets: [], swap: %{}}}

  defp plan(%{type: :gall, gall_key: {:host, old}} = s, {:host, plant}) when is_integer(plant) do
    if plant == old,
      do: {:error, :unchanged},
      else:
        {:ok,
         %{
           withdraw?: true,
           targets: [Catalog.gall_fact(s.gall_id, {:host, plant})],
           swap: %{old => plant}
         }}
  end

  defp plan(%{type: :gall, gall_key: {:trait, trait, old}} = s, {:values, values})
       when is_list(values) do
    values = Enum.uniq(values)

    cond do
      values == [] or not Enum.all?(values, &is_binary/1) ->
        {:error, :not_correctable}

      (unknown = Enum.reject(values, &Catalog.get_trait_value(trait, &1))) != [] ->
        {:error, "not values of #{trait}: #{Enum.join(unknown, ", ")}"}

      values == [old] ->
        {:error, :unchanged}

      true ->
        {:ok,
         %{
           withdraw?: old not in values,
           targets:
             for(v <- values, v != old, do: Catalog.gall_fact(s.gall_id, {:trait, trait, v})),
           swap: %{}
         }}
    end
  end

  defp plan(%{type: :taxon, kind: :placement, key: key}, {:parent, parent})
       when is_integer(parent) or is_nil(parent) do
    if parent == key.parent_id,
      do: {:error, :unchanged},
      else:
        {:ok,
         %{
           withdraw?: true,
           targets: [{:placement, %{key | parent_id: parent}}],
           swap: if(key.parent_id && parent, do: %{key.parent_id => parent}, else: %{})
         }}
  end

  defp plan(%{type: :taxon, kind: :synonymy, key: key}, {:accepted, accepted})
       when is_integer(accepted) do
    if accepted == key.accepted_taxon_id,
      do: {:error, :unchanged},
      else:
        {:ok,
         %{
           withdraw?: true,
           targets: [{:synonymy, %{key | accepted_taxon_id: accepted}}],
           swap: %{key.accepted_taxon_id => accepted}
         }}
  end

  defp plan(_subject, _correction), do: {:error, :not_correctable}

  # A correction that withdraws nothing and moves to Facts the Source
  # states already changes nothing.
  defp changes?(%{withdraw?: true}, _source_id), do: :ok

  defp changes?(%{targets: targets}, source_id) do
    if Enum.all?(targets, &held_by(&1, source_id)), do: {:error, :unchanged}, else: :ok
  end

  # The target Fact, if the Source states it already.
  defp held_by({kind, key} = target, source_id) do
    case find(target_type(target), kind, key) do
      {:ok, id} when is_integer(id) -> if Facts.get_attribution(id, source_id), do: id
      _ -> nil
    end
  end

  @act_kinds [:placement, :name, :synonymy, :split, :common_name]

  defp target_type({kind, _key}) when kind in @act_kinds, do: :taxon
  defp target_type(_target), do: :gall

  defp find(:taxon, kind, key), do: Taxa.find_act_fact(kind, key)
  defp find(:gall, kind, key), do: Catalog.find_fact(kind, key)

  # -- carrying it out ------------------------------------------------------------------

  defp carry_out(actor, attribution, subject, plan) do
    withdrawn = if plan.withdraw?, do: [attribution.fact_id], else: []

    with {:ok, conflicts} <- withdraw(actor, attribution, subject, plan.withdraw?),
         {:ok, stated} <- state_all(actor, attribution, plan) do
      {:ok,
       %{
         withdrawn: withdrawn,
         asserted: Enum.map(stated, & &1.fact_id),
         new_attributions: for(%{new: %Attribution{} = a} <- stated, do: a),
         conflicts: conflicts ++ Enum.flat_map(stated, & &1.conflicts)
       }}
    end
  end

  defp withdraw(_actor, _attribution, _subject, false), do: {:ok, []}

  defp withdraw(actor, attribution, subject, true) do
    with {:ok, conflicts} <-
           Facts.remove_attribution(actor, attribution.fact_id, attribution.source_id) do
      if subject.type == :taxon, do: drop_questions(attribution.id)
      {:ok, conflicts}
    end
  end

  # A withdrawn statement's open question in the taxonomy queue goes with it.
  defp drop_questions(attribution_id) do
    from(q in QueueItem,
      where:
        q.kind == :taxonomy_acceptance and q.status == :open and
          fragment("(?->>'attribution_id')::bigint", q.subject) == ^attribution_id
    )
    |> Repo.delete_all()
  end

  defp state_all(actor, attribution, plan) do
    attrs = carried(attribution, plan.swap)

    Enum.reduce_while(plan.targets, {:ok, []}, fn target, {:ok, stated} ->
      case state(actor, target, attribution.source_id, attrs) do
        {:ok, one} -> {:cont, {:ok, stated ++ [one]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp state(actor, {kind, key} = target, source_id, attrs) do
    case held_by(target, source_id) do
      id when is_integer(id) ->
        {:ok, %{fact_id: id, new: nil, conflicts: []}}

      nil ->
        result =
          case target_type(target) do
            :taxon -> Taxa.assert_act(kind, actor, key, attrs)
            :gall -> Catalog.assert_fact(kind, actor, key, attrs)
          end

        with {:ok, %{fact: fact, attribution: a, conflicts: conflicts}} <- result do
          {:ok, %{fact_id: fact.id, new: a, conflicts: conflicts}}
        end
    end
  end

  # The withdrawn statement's words, as `Gallformers.Facts.attribute/2`
  # takes them, its names' taxa changed by `swap`.
  defp carried(%Attribution{} = a, swap) do
    %{
      source_id: a.source_id,
      stance: a.stance,
      stated: a.stated_on && PartialDate.format(a.stated_on, a.stated_precision || :day),
      value_as_written: a.value_as_written,
      term: a.term,
      batch_id: a.batch_id,
      statement_text: a.statement_text,
      when_as_written: a.when_as_written,
      stage_as_written: a.stage_as_written,
      status_as_written: a.status_as_written,
      authorship_as_written: a.authorship_as_written,
      cites_as_written: a.cites_as_written,
      cited_source_id: a.cited_source_id,
      evidence:
        Enum.map(
          a.evidence,
          &Map.take(&1, [:document_item_id, :quote, :page, :url, :whole_item, :cites_as_written])
        ),
      names:
        Enum.map(a.names, fn n ->
          %{
            taxon_id: Map.get(swap, n.taxon_id, n.taxon_id),
            name_as_written: n.name_as_written,
            name_reading: n.name_reading,
            role: n.role
          }
        end),
      observations: Enum.map(a.observations, &Map.take(&1, [:provider, :external_id, :url]))
    }
  end

  # A taxonomic statement stated anew: accepted now when the curator says
  # so, else asked in the taxonomy queue; one of Gallformers' own counts.
  defp settle_acceptance(_actor, %{type: :gall}, _attributions, _opts), do: :ok

  defp settle_acceptance(actor, %{type: :taxon}, attributions, opts) do
    Enum.each(attributions, fn %Attribution{} = a ->
      kind = Repo.one!(from(f in Fact, where: f.id == ^a.fact_id, select: f.kind))

      cond do
        not Facts.needs_acceptance?(kind, a.source_id) ->
          :ok

        Keyword.get(opts, :accept, false) ->
          actor |> TaxonomicDecisions.decide(:accept, a.id) |> ok_or_rollback()

        true ->
          :ok = TaxonomyQueue.asked_again(:reopen, a.id)
      end
    end)
  end

  # -- the record and the log -------------------------------------------------------------

  defp kind_of(:withdraw), do: :withdraw
  defp kind_of({kind, _to}), do: kind

  defp replay_key(source_id, %{type: :gall} = s) do
    %{
      "source" => StableRef.source(source_id),
      "gall" => StableRef.gall(s.gall_id),
      "fact" => CurationNotes.fact_key(s.gall_key)
    }
  end

  defp replay_key(source_id, %{type: :taxon} = s) do
    %{
      "source" => StableRef.source(source_id),
      "kind" => Atom.to_string(s.kind),
      "fact" => TaxonomicDecisions.encode_key(s.kind, s.key)
    }
  end

  defp payload(correction, note, actor, opts) do
    {op, to} =
      case correction do
        :withdraw -> {"withdraw", nil}
        {:values, values} -> {"values", values}
        {op, nil} -> {Atom.to_string(op), nil}
        {op, taxon_id} -> {Atom.to_string(op), StableRef.taxon(taxon_id)}
      end

    %{
      "op" => op,
      "to" => to,
      "note" => note,
      "author" => Keyword.get(opts, :author_name, actor.name),
      "accept" => Keyword.get(opts, :accept, false)
    }
  end

  # -- in words -----------------------------------------------------------------------------

  defp describe(%{type: :gall, gall_id: gall_id, gall_key: key}, attribution) do
    gall = get_in(FactsView.gall_names([gall_id]), [gall_id, :name]) || "Gall #{gall_id}"
    "#{fact_words(key)} of #{gall}#{denial(attribution)}"
  end

  defp describe(%{type: :taxon, kind: kind, key: key}, attribution),
    do: "#{act_words(kind, key)}#{denial(attribution)}"

  defp denial(%Attribution{stance: :deny}), do: " (a denial)"
  defp denial(_attribution), do: ""

  defp fact_words({:host, id}), do: "Host #{taxon(id)}"
  defp fact_words({:inducer, id}), do: "Inducer #{taxon(id)}"
  defp fact_words({:trait, trait, value}), do: "#{humanize(trait)} #{value}"
  defp fact_words({:alias, name}), do: "Alias “#{name}”"
  defp fact_words({:range, :exclude, id}), do: "Range: not in #{place(id)}"
  defp fact_words({:range, :only, id}), do: "Range: only in #{place(id)}"
  defp fact_words({:occurrence, id}), do: "Recorded in #{place(id)}"

  defp act_words(:placement, %{taxon_id: t, parent_id: nil}),
    do: "Placement of #{taxon(t)} at the root"

  defp act_words(:placement, %{taxon_id: t, parent_id: p}),
    do: "Placement of #{taxon(t)} under #{taxon(p)}"

  defp act_words(:name, %{taxon_id: t, name: name, rank: rank}),
    do: "Name of #{taxon(t)} as #{name} (#{rank})"

  defp act_words(:synonymy, %{name: name, accepted_taxon_id: t}),
    do: "#{name} as a synonym of #{taxon(t)}"

  defp act_words(:split, %{taxon_id: t}), do: "Split of #{taxon(t)}"

  defp act_words(:common_name, %{taxon_id: t, common_name: name}),
    do: "Common name “#{name}” of #{taxon(t)}"

  defp describe_change(:withdraw), do: nil
  defp describe_change({:host, id}), do: taxon(id)
  defp describe_change({:values, values}), do: Enum.join(values, ", ")
  defp describe_change({:parent, nil}), do: "at the root"
  defp describe_change({:parent, id}), do: "under #{taxon(id)}"
  defp describe_change({:accepted, id}), do: "synonym of #{taxon(id)}"

  defp taxon(id) do
    case FactsView.taxon_names([id]) do
      %{^id => %{name: name, rank: rank}} when rank in [nil, :species] -> name
      %{^id => %{name: name, rank: rank}} -> "#{name} (#{rank})"
      _ -> "taxon #{id}"
    end
  end

  defp place(id), do: Places.get_place!(id).name

  defp humanize(text), do: text |> to_string() |> String.replace("_", " ") |> String.capitalize()

  # -- reading ------------------------------------------------------------------------------

  @doc "Source `source_id`'s corrections, newest first."
  @spec list(integer()) :: [SourceCorrection.t()]
  def list(source_id) when is_integer(source_id) do
    from(c in SourceCorrection,
      where: c.source_id == ^source_id,
      order_by: [desc: c.inserted_at, desc: c.id]
    )
    |> Repo.all()
  end

  @doc "How many gall Facts Source `source_id` states (its attributions of them)."
  @spec gall_fact_count(integer()) :: non_neg_integer()
  def gall_fact_count(source_id) when is_integer(source_id) do
    Repo.one(
      from(a in Attribution,
        join: f in Fact,
        on: f.id == a.fact_id,
        where: a.source_id == ^source_id and like(f.kind, "gall_%"),
        select: count()
      )
    )
  end

  @doc """
  The Galls Source `source_id` states Facts about whose name, alias or
  Inducer matches `query` (`Gallformers.Catalog.search_galls/2`), at most
  `limit`, by name: `%{id, name}`.
  """
  @spec search_galls(integer(), String.t(), pos_integer()) :: [%{id: integer(), name: String.t()}]
  def search_galls(source_id, query, limit) when is_integer(source_id) and is_binary(query) do
    hits = Catalog.search_galls(query)
    stated = MapSet.new(galls_stated(source_id, Enum.map(hits, & &1.id)))

    hits
    |> Enum.filter(&MapSet.member?(stated, &1.id))
    |> Enum.take(limit)
    |> Enum.map(&%{id: &1.id, name: &1.name})
  end

  # Which of `gall_ids` the Source states a Fact about (may repeat).
  defp galls_stated(_source_id, []), do: []

  defp galls_stated(source_id, gall_ids) do
    plain =
      for schema <- [TraitFact, AliasFact, RangeFact, OccurrenceFact, DescriptionFact] do
        from(d in schema,
          join: a in Attribution,
          on: a.fact_id == d.fact_id,
          where: a.source_id == ^source_id and d.gall_id in ^gall_ids,
          distinct: true,
          select: d.gall_id
        )
      end

    relationships =
      from(r in RelationshipFact,
        join: a in Attribution,
        on: a.fact_id == r.fact_id,
        where: a.source_id == ^source_id and r.object_gall_id in ^gall_ids,
        distinct: true,
        select: r.object_gall_id
      )

    Enum.flat_map(plain ++ [relationships], &Repo.all/1)
  end

  # -- replay -------------------------------------------------------------------------------

  @doc """
  Replays a logged correction: the Source found by its title, the Fact by
  its stable key, and the correction made again with its note and author.
  Done (`:ok`) when the Source no longer states the Fact, or the
  correction changes nothing.
  """
  @spec replay(Actor.t(), map(), map()) :: :ok | {:error, term()}
  def replay(%Actor{} = actor, key, payload) do
    with {:ok, source_id} <- StableRef.resolve_source(key["source"]),
         {:ok, fact_id} <- replay_fact(key),
         {:ok, correction} <- decode_correction(payload) do
      if is_nil(fact_id) or is_nil(Facts.get_attribution(fact_id, source_id)) do
        :ok
      else
        opts = if payload["author"], do: [author_name: payload["author"]], else: []

        case correct(actor, source_id, fact_id, correction, payload["note"], opts) do
          {:ok, _result} -> :ok
          {:error, :unchanged} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  defp replay_fact(%{"gall" => gall, "fact" => fact}) do
    with {:ok, gall_id} <- StableRef.resolve_gall(gall),
         {:ok, gall_key} <- CurationNotes.decode_fact_key(fact) do
      Catalog.find_gall_fact(gall_id, gall_key)
    end
  end

  defp replay_fact(%{"kind" => kind, "fact" => fact}) do
    with {:ok, kind} <- kind_or_error(kind),
         {:ok, key} <- TaxonomicDecisions.decode_key(kind, fact) do
      Taxa.find_act_fact(kind, key)
    end
  end

  defp replay_fact(key), do: {:error, {:unknown_correction, key}}

  defp kind_or_error(kind) do
    case TaxonomicDecisions.kind(kind) do
      {:ok, kind} -> {:ok, kind}
      :error -> {:error, {:unknown_kind, kind}}
    end
  end

  defp decode_correction(%{"op" => "withdraw"}), do: {:ok, :withdraw}

  defp decode_correction(%{"op" => "values", "to" => values}) when is_list(values),
    do: {:ok, {:values, values}}

  defp decode_correction(%{"op" => "parent", "to" => nil}), do: {:ok, {:parent, nil}}

  defp decode_correction(%{"op" => op, "to" => ref}) when op in ["host", "parent", "accepted"] do
    with {:ok, id} <- StableRef.resolve_current_taxon(ref),
         do: {:ok, {String.to_existing_atom(op), id}}
  end

  defp decode_correction(payload), do: {:error, {:unknown_correction, payload}}

  defp ok_or_rollback({:ok, value}), do: value
  defp ok_or_rollback({:error, reason}), do: Repo.rollback(reason)
end
