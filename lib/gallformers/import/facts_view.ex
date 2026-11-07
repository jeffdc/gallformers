defmodule Gallformers.Import.FactsView do
  @moduledoc """
  A Source's Facts as the Facts page shows them (matter `f14c`, item 4):
  grouped by Gall, then by category, each Fact in Gallformers' terms beside
  the Source's own words.

  The shaping does not care where the Facts come from: `group/2` takes
  Gall headers and Fact entries, from the Facts preview's rolled-back
  apply (`Gallformers.Import.Preview`) or from the Facts a Source's
  attributions hold (`entries/2`, `Gallformers.Import.facts_for_source/1`).

  ## A Fact entry

      %{
        ref: "f3" | nil,          # the statement's id in its batch
        batch_id: 62 | nil,
        fact_id: 123 | nil,       # nil for a Fact not written yet
        kind: :relationship | :trait | :range | :occurrence | :alias
              | :description | :qualifier,
        category: :inducer | :hosts | :traits | :range | :descriptions
                  | :aliases | :other,
        gall: gall key,           # the Gall header it goes under
        value: map,               # in Gallformers' terms (see below)
        words: map,               # the Source's words (see below)
        stance: :confirm | :deny,
        status: :new | :held | :conflict | :waiting | :dropped | nil,
        standing: the Fact's standing (an applied Fact) | nil,
        question: map | nil,      # what a waiting Fact waits on
        why: String.t() | nil,    # why it was dropped, or the conflict
        edits: [map]              # the curator's edits on its statement
      }

  `value` by kind: a Relationship `%{type, label, subject, object,
  gall_context}` (each `%{taxon_id, name, rank}` or `%{gall_id, name}`, an
  ID nil for one only the preview creates, or nil); a Trait `%{trait,
  value}`; a range `%{adjustment, place}` and an occurrence `%{place}`
  (`%{id, code, name}`); an alias `%{name, kind}`; a description `%{}` (its
  text is its evidence); a qualifier `%{qualifier, value, of_ref}`.

  `words`: `%{term, value_as_written, names: [%{role, name_as_written,
  name_reading}], evidence: [%{quote, item, whole_item, page}],
  when_as_written, stage_as_written, statement_text}`, the evidence's
  `item` the document item's ref (`"#/texts/4"`).

  ## A Gall header and its group

  A header is `%{key, ref, gall_id, new, name_as_written, name, status,
  question, why}`; `group/2` adds `facts`, a map of category to entries
  (`:traits` a map of Trait to entries), every category present.
  """

  import Ecto.Query, only: [from: 2, union_all: 2]

  alias Gallformers.Accounts
  alias Gallformers.Catalog.Facts.AliasFact
  alias Gallformers.Catalog.Facts.DescriptionFact
  alias Gallformers.Catalog.Facts.OccurrenceFact
  alias Gallformers.Catalog.Facts.QualifierFact
  alias Gallformers.Catalog.Facts.RangeFact
  alias Gallformers.Catalog.Facts.RelationshipFact
  alias Gallformers.Catalog.Facts.TraitFact
  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.RelationshipTypes
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Facts.Fact
  alias Gallformers.Places.Place
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Sources.DocumentItem
  alias Gallformers.Taxa.ActFacts.CommonNameFact
  alias Gallformers.Taxa.ActFacts.NameFact
  alias Gallformers.Taxa.ActFacts.PlacementFact
  alias Gallformers.Taxa.ActFacts.SplitFact
  alias Gallformers.Taxa.ActFacts.SynonymyFact
  alias Gallformers.Taxa.Taxon
  alias Gallformers.Taxa.TaxonName

  @categories [:inducer, :hosts, :traits, :range, :descriptions, :aliases, :other]

  @type category :: :inducer | :hosts | :traits | :range | :descriptions | :aliases | :other
  @type entry :: map()
  @type header :: map()

  @doc "The categories, in the page's order."
  @spec categories() :: [category()]
  def categories, do: @categories

  @doc """
  The category of a Fact of `kind` (an atom or the contract's string),
  a Relationship's by its `type`. A qualifier goes with the Fact it
  qualifies (`category/2` of that Fact).
  """
  @spec category(atom() | String.t(), String.t() | nil) :: category()
  def category(kind, type \\ nil)
  def category(kind, type) when is_binary(kind), do: category(kind(kind), type)
  def category(:relationship, "inducer_of"), do: :inducer
  def category(:relationship, "host_of"), do: :hosts
  def category(:trait, _type), do: :traits
  def category(kind, _type) when kind in [:range, :occurrence], do: :range
  def category(:description, _type), do: :descriptions
  def category(:alias, _type), do: :aliases
  def category(_kind, _type), do: :other

  @kinds Map.new(
           [
             :relationship,
             :trait,
             :range,
             :occurrence,
             :alias,
             :description,
             :qualifier,
             :name,
             :placement,
             :synonymy,
             :split,
             :common_name
           ],
           &{Atom.to_string(&1), &1}
         )

  @doc "A statement's kind (the contract's `kind`) as an atom; nil for one unknown."
  @spec kind(String.t() | nil) :: atom() | nil
  def kind(kind), do: Map.get(@kinds, kind)

  # -- entries from the database ----------------------------------------------

  @doc """
  The entries of the gall Facts among `fact_ids`, with Source
  `source_id`'s words (its attribution of each; none, no words), in the
  order given. Each entry's `gall` is the ID of the Gall it is about (a
  Gall-to-Gall Relationship's subject, a qualifier's Fact's Gall).
  Facts of other kinds (taxonomic acts) are left out.
  """
  @spec entries(integer(), [integer()]) :: [entry()]
  def entries(_source_id, []), do: []

  def entries(source_id, fact_ids) when is_integer(source_id) and is_list(fact_ids),
    do: build(source_id, fact_ids, Facts.list_attributions_for_facts(fact_ids))

  @doc """
  The entries of the gall Facts among `fact_ids` with no one Source's
  words (as `entries/2`), each with its `sources`: every attribution's
  Source, `%{source_id, name, stance}` (`name` as
  `Gallformers.Sources.short_name/1`, else the title), oldest statement
  first. For a page showing a Gall's Facts from all its Sources.
  """
  @spec gall_entries([integer()]) :: [entry()]
  def gall_entries([]), do: []

  def gall_entries(fact_ids) when is_list(fact_ids) do
    all = Facts.list_attributions_for_facts(fact_ids)
    names = all |> Map.values() |> List.flatten() |> source_names()

    for e <- build(nil, fact_ids, all) do
      sources =
        all
        |> Map.get(e.fact_id, [])
        |> Enum.sort_by(&{&1.stated_on != nil, stated_days(&1.stated_on), &1.id})
        |> Enum.map(&%{source_id: &1.source_id, name: names[&1.source_id], stance: &1.stance})

      Map.put(e, :sources, sources)
    end
  end

  # A statement's date as a number to sort by (undated ones sort first on
  # `stated_on != nil`, Standing's rule 4).
  defp stated_days(nil), do: nil
  defp stated_days(%Date{} = date), do: Date.to_gregorian_days(date)

  defp source_names(attributions) do
    attributions
    |> Enum.map(& &1.source_id)
    |> Enum.uniq()
    |> Sources.list_sources_by_id()
    |> Map.new(&{&1.id, Sources.short_name(&1) || &1.title})
  end

  defp build(source_id, fact_ids, all) do
    facts = Repo.all(from(f in Fact, where: f.id in ^fact_ids)) |> Map.new(&{&1.id, &1})
    details = details(fact_ids)

    attributions =
      Map.new(all, fn {id, list} ->
        {id, source_id && Enum.find(list, &(&1.source_id == source_id))}
      end)

    names = names(details)
    items = items(Map.values(attributions))

    for id <- fact_ids, %{} = detail <- [details[id]] do
      attribution = attributions[id]
      {kind, value, gall} = value(detail, names, details)

      %{
        ref: nil,
        batch_id: attribution && attribution.batch_id,
        fact_id: id,
        kind: kind,
        category: entry_category(kind, detail, details),
        gall: gall,
        value: value,
        words: words(attribution, items),
        stance: attribution && attribution.stance,
        status: nil,
        standing: facts[id] && facts[id].standing,
        slot: facts[id] && facts[id].slot,
        question: nil,
        why: nil,
        edits: []
      }
    end
  end

  defp entry_category(:qualifier, %QualifierFact{of_fact_id: of}, details) do
    case details[of] do
      %RelationshipFact{type: type} -> category(:relationship, type)
      _ -> :other
    end
  end

  defp entry_category(:relationship, %RelationshipFact{type: type}, _details),
    do: category(:relationship, type)

  defp entry_category(kind, _detail, _details), do: category(kind)

  # Each Fact's detail row, by Fact ID; a qualifier's Relationship too.
  defp details(fact_ids) do
    rows =
      [RelationshipFact, TraitFact, RangeFact, OccurrenceFact, AliasFact, DescriptionFact]
      |> Enum.flat_map(fn schema ->
        Repo.all(from(d in schema, where: d.fact_id in ^fact_ids))
      end)

    qualifiers = Repo.all(from(q in QualifierFact, where: q.fact_id in ^fact_ids))
    of_ids = Enum.map(qualifiers, & &1.of_fact_id) -- fact_ids
    ofs = Repo.all(from(r in RelationshipFact, where: r.fact_id in ^of_ids))

    Map.new(rows ++ qualifiers ++ ofs, &{&1.fact_id, &1})
  end

  # Taxon, Gall, Trait value and place names the details need.
  defp names(details) do
    rows = Map.values(details)

    taxon_ids =
      for %RelationshipFact{} = r <- rows,
          id <- [r.subject_taxon_id, r.object_taxon_id],
          is_integer(id),
          uniq: true,
          do: id

    gall_ids =
      Enum.uniq(
        for(
          %RelationshipFact{} = r <- rows,
          id <- [r.subject_gall_id, r.object_gall_id, r.gall_context_id],
          is_integer(id),
          do: id
        ) ++
          for(%{gall_id: id} <- rows, is_integer(id), do: id)
      )

    value_ids = for %TraitFact{trait_value_id: id} <- rows, uniq: true, do: id
    place_ids = for %{place_id: id} <- rows, is_integer(id), uniq: true, do: id

    %{
      taxa: taxon_names(taxon_ids),
      galls: gall_names(gall_ids),
      values:
        Repo.all(
          from(v in TraitValue, where: v.id in ^value_ids, select: {v.id, {v.trait, v.value}})
        )
        |> Map.new(),
      places:
        Repo.all(
          from(p in Place,
            where: p.id in ^place_ids,
            select: {p.id, %{id: p.id, code: p.code, name: p.name}}
          )
        )
        |> Map.new()
    }
  end

  @doc "The accepted name and rank of each of `taxon_ids`, by ID: `%{taxon_id, name, rank}`."
  @spec taxon_names([integer()]) :: %{integer() => map()}
  def taxon_names([]), do: %{}

  def taxon_names(taxon_ids) do
    from(t in Taxon,
      join: n in TaxonName,
      on: n.taxon_id == t.id and n.status == :accepted,
      where: t.id in ^taxon_ids,
      select: {t.id, %{taxon_id: t.id, name: n.name, rank: t.rank}}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "The name each of `gall_ids` shows, by ID: `%{gall_id, name}`."
  @spec gall_names([integer()]) :: %{integer() => map()}
  def gall_names([]), do: %{}

  def gall_names(gall_ids) do
    from(g in Gall, where: g.id in ^gall_ids)
    |> Repo.all()
    |> Map.new(&{&1.id, %{gall_id: &1.id, name: Gall.display_name(&1)}})
  end

  defp value(%RelationshipFact{} = r, names, _details) do
    type = RelationshipTypes.get(r.type)

    value = %{
      type: r.type,
      label: type && type.label,
      subject: endpoint(r.subject_taxon_id, r.subject_gall_id, names),
      object: endpoint(r.object_taxon_id, r.object_gall_id, names),
      gall_context: endpoint(nil, r.gall_context_id, names)
    }

    # A Gall-to-Gall Relationship goes under its subject, the others under their Gall.
    {:relationship, value, r.subject_gall_id || r.object_gall_id || r.gall_context_id}
  end

  defp value(%TraitFact{} = t, names, _details) do
    {trait, value} = Map.get(names.values, t.trait_value_id, {nil, nil})
    {:trait, %{trait: trait, value: value}, t.gall_id}
  end

  defp value(%RangeFact{} = r, names, _details),
    do: {:range, %{adjustment: r.adjustment, place: names.places[r.place_id]}, r.gall_id}

  defp value(%OccurrenceFact{} = o, names, _details),
    do: {:occurrence, %{place: names.places[o.place_id]}, o.gall_id}

  defp value(%AliasFact{} = a, _names, _details),
    do: {:alias, %{name: a.name, kind: a.kind}, a.gall_id}

  defp value(%DescriptionFact{} = d, _names, _details), do: {:description, %{}, d.gall_id}

  defp value(%QualifierFact{} = q, names, details) do
    gall =
      case details[q.of_fact_id] do
        %RelationshipFact{} = r -> r |> value(names, details) |> elem(2)
        _ -> nil
      end

    {:qualifier, %{qualifier: q.qualifier, value: q.value, of_fact_id: q.of_fact_id, of_ref: nil},
     gall}
  end

  defp endpoint(taxon_id, _gall_id, names) when is_integer(taxon_id),
    do: Map.get(names.taxa, taxon_id, %{taxon_id: taxon_id, name: nil, rank: nil})

  defp endpoint(_taxon_id, gall_id, names) when is_integer(gall_id),
    do: Map.get(names.galls, gall_id, %{gall_id: gall_id, name: nil})

  defp endpoint(_taxon_id, _gall_id, _names), do: nil

  # The document item refs the attributions' evidence points at.
  defp items(attributions) do
    ids =
      for %{evidence: evidence} <- attributions,
          is_list(evidence),
          e <- evidence,
          is_integer(e.document_item_id),
          uniq: true,
          do: e.document_item_id

    Repo.all(from(i in DocumentItem, where: i.id in ^ids, select: {i.id, i.ref})) |> Map.new()
  end

  defp words(nil, _items), do: empty_words()

  defp words(attribution, items) do
    %{
      term: attribution.term,
      value_as_written: attribution.value_as_written,
      names:
        for n <- attribution.names do
          %{role: n.role, name_as_written: n.name_as_written, name_reading: n.name_reading}
        end,
      evidence:
        for e <- attribution.evidence do
          %{
            quote: e.quote,
            item: items[e.document_item_id],
            whole_item: e.whole_item,
            page: e.page
          }
        end,
      when_as_written: attribution.when_as_written,
      stage_as_written: attribution.stage_as_written,
      statement_text: attribution.statement_text
    }
  end

  @doc "No words: a Fact no Source's attribution here speaks for."
  @spec empty_words() :: map()
  def empty_words do
    %{
      term: nil,
      value_as_written: nil,
      names: [],
      evidence: [],
      when_as_written: nil,
      stage_as_written: nil,
      statement_text: nil
    }
  end

  # -- taxonomic statements (matter `f923` Task 10) -----------------------------

  @doc """
  The entries of the taxonomic statements `attributions` (Sources'
  attributions of act Facts, with their evidence and names), in the order
  given, shaped as the preview's acts: `category: :taxonomy`, the act's
  `kind` (`:placement`, `:name`, `:synonymy`, `:split`, `:common_name`),
  its `value` (`%{taxon, parent, name, accepted, into, common_name}`, those
  that apply: a placement's `parent` nil at the root, a name act's `name`
  only when it differs from the taxon's), the Source's words (with `status_as_written` and
  `authorship_as_written`) and the Fact's standing. Each also has its
  `source` (`%{source_id, name}`) and the curator's `decision`:
  `%{state: :accepted | :declined | :awaiting, by, at, reason}` (`by` the
  curator's name, nil for a system process), or nil for a statement of
  Gallformers' own Sources, which counts without one.
  """
  @spec act_entries([Attribution.t()]) :: [entry()]
  def act_entries([]), do: []

  def act_entries(attributions) when is_list(attributions) do
    fact_ids = attributions |> Enum.map(& &1.fact_id) |> Enum.uniq()
    facts = Repo.all(from(f in Fact, where: f.id in ^fact_ids)) |> Map.new(&{&1.id, &1})
    details = act_details(fact_ids)
    taxa = details |> Map.values() |> Enum.flat_map(&act_taxa/1) |> Enum.uniq() |> taxon_names()
    items = items(attributions)
    sources = source_names(attributions)
    own = Sources.own_source_ids()

    curators =
      attributions
      |> Enum.flat_map(&[&1.accepted_by_user_id, &1.declined_by_user_id])
      |> Enum.filter(&is_integer/1)
      |> Accounts.display_names()

    for a <- attributions, %{} = detail <- [details[a.fact_id]] do
      fact = facts[a.fact_id]

      %{
        ref: nil,
        batch_id: a.batch_id,
        fact_id: a.fact_id,
        kind: act_kind(detail),
        category: :taxonomy,
        gall: nil,
        value: act_value(detail, taxa),
        words:
          Map.merge(words(a, items), %{
            status_as_written: a.status_as_written,
            authorship_as_written: a.authorship_as_written
          }),
        stance: a.stance,
        status: nil,
        standing: fact && fact.standing,
        slot: fact && fact.slot,
        question: nil,
        why: nil,
        edits: [],
        source: %{source_id: a.source_id, name: sources[a.source_id]},
        decision: if(a.source_id not in own, do: decision(a, curators))
      }
    end
  end

  @act_schemas [PlacementFact, NameFact, SynonymyFact, SplitFact, CommonNameFact]

  defp act_details(fact_ids) do
    @act_schemas
    |> Enum.flat_map(&Repo.all(from(d in &1, where: d.fact_id in ^fact_ids)))
    |> Map.new(&{&1.fact_id, &1})
  end

  defp act_kind(%PlacementFact{}), do: :placement
  defp act_kind(%NameFact{}), do: :name
  defp act_kind(%SynonymyFact{}), do: :synonymy
  defp act_kind(%SplitFact{}), do: :split
  defp act_kind(%CommonNameFact{}), do: :common_name

  defp act_taxa(%PlacementFact{taxon_id: t, parent_id: p}), do: Enum.reject([t, p], &is_nil/1)
  defp act_taxa(%SynonymyFact{accepted_taxon_id: t}), do: [t]
  defp act_taxa(%SplitFact{taxon_id: t, into_taxon_ids: into}), do: [t | into]
  defp act_taxa(%{taxon_id: t}), do: [t]

  defp act_value(%PlacementFact{} = p, taxa),
    do: %{taxon: taxon(taxa, p.taxon_id), parent: p.parent_id && taxon(taxa, p.parent_id)}

  defp act_value(%NameFact{} = n, taxa) do
    taxon = taxon(taxa, n.taxon_id)
    %{taxon: taxon, name: if(n.name != taxon.name, do: n.name)}
  end

  defp act_value(%SynonymyFact{} = s, taxa),
    do: %{name: s.name, accepted: taxon(taxa, s.accepted_taxon_id)}

  defp act_value(%SplitFact{} = s, taxa),
    do: %{taxon: taxon(taxa, s.taxon_id), into: Enum.map(s.into_taxon_ids, &taxon(taxa, &1))}

  defp act_value(%CommonNameFact{} = c, taxa),
    do: %{taxon: taxon(taxa, c.taxon_id), common_name: c.common_name}

  defp taxon(taxa, id), do: Map.get(taxa, id, %{taxon_id: id, name: nil, rank: nil})

  defp decision(%Attribution{accepted_at: %DateTime{} = at} = a, curators),
    do: %{state: :accepted, by: curators[a.accepted_by_user_id], at: at, reason: nil}

  defp decision(%Attribution{declined_at: %DateTime{} = at} = a, curators),
    do: %{state: :declined, by: curators[a.declined_by_user_id], at: at, reason: a.decline_reason}

  defp decision(_attribution, _curators), do: %{state: :awaiting, by: nil, at: nil, reason: nil}

  @doc """
  Where taxon `taxon_id` stands in the Facts, and on whose word:

    * `placement` — its current placement, `%{fact_id, parent, source}`
      (`parent` nil at the root), or nil when no current Fact places it;
    * `name` — its current name, `%{fact_id, name, rank, authorship,
      sensu, source}`, or nil;
    * `disagreeing` — the papers that say otherwise and do not count, as
      `act_entries/1` gives them, newest first: a statement awaiting a
      curator, or declined, that confirms what is not current (another
      parent, another name, a synonym or common name the taxon lacks, a
      split) or denies what is.

  A position's `source` (`%{source_id, name}`) is the Source whose
  statement decides it: the newest of the statements that count.
  """
  @spec position(integer()) :: %{
          placement: map() | nil,
          name: map() | nil,
          disagreeing: [entry()]
        }
  def position(taxon_id) when is_integer(taxon_id) do
    facts =
      Repo.all(
        from(f in Fact,
          where:
            f.slot in ^["taxon:#{taxon_id}:placement", "taxon:#{taxon_id}:name"] or
              f.id in subquery(about_taxon(taxon_id))
        )
      )

    attributions =
      facts
      |> Enum.map(& &1.id)
      |> Facts.list_attributions_for_facts()

    ctx = %{
      facts: facts,
      attributions: attributions,
      own: Sources.own_source_ids(),
      details: facts |> Enum.map(& &1.id) |> act_details(),
      sources: attributions |> Map.values() |> List.flatten() |> source_names()
    }

    names =
      ctx.details |> Map.values() |> Enum.flat_map(&act_taxa/1) |> Enum.uniq() |> taxon_names()

    %{
      placement:
        with {p, source} <- current_position(ctx, :placement) do
          %{fact_id: p.fact_id, parent: p.parent_id && names[p.parent_id], source: source}
        end,
      name:
        with {n, source} <- current_position(ctx, :name) do
          %{
            fact_id: n.fact_id,
            name: n.name,
            rank: n.rank,
            authorship: n.authorship,
            sensu: n.sensu,
            source: source
          }
        end,
      disagreeing:
        ctx
        |> disagreeing()
        |> Enum.sort_by(&{&1.stated_on != nil, stated_days(&1.stated_on), &1.id}, :desc)
        |> act_entries()
    }
  end

  # The current Fact of `kind` among the taxon's, with the Source deciding it.
  defp current_position(ctx, kind) do
    Enum.find_value(ctx.facts, fn fact ->
      with :current <- fact.standing,
           %{} = detail <- ctx.details[fact.id],
           ^kind <- act_kind(detail),
           %Attribution{} = by <- deciding(fact, ctx.attributions[fact.id] || [], ctx.own) do
        {detail, %{source_id: by.source_id, name: ctx.sources[by.source_id]}}
      else
        _ -> nil
      end
    end)
  end

  # The statements that don't count and say otherwise than the Facts do.
  defp disagreeing(ctx) do
    for f <- ctx.facts,
        a <- Map.get(ctx.attributions, f.id, []),
        a.source_id not in ctx.own,
        not Facts.counts?(f.kind, a, ctx.own),
        (a.stance == :confirm and f.standing != :current) or
          (a.stance == :deny and f.standing == :current),
        do: a
  end

  # The synonymy, common-name and split Facts about a taxon.
  defp about_taxon(taxon_id) do
    from(s in SynonymyFact, where: s.accepted_taxon_id == ^taxon_id, select: s.fact_id)
    |> union_all(^from(c in CommonNameFact, where: c.taxon_id == ^taxon_id, select: c.fact_id))
    |> union_all(^from(s in SplitFact, where: s.taxon_id == ^taxon_id, select: s.fact_id))
  end

  # The attribution deciding a current Fact: the newest confirmation that counts.
  defp deciding(fact, attributions, own) do
    attributions
    |> Enum.filter(&(&1.stance == :confirm and Facts.counts?(fact.kind, &1, own)))
    |> Enum.max_by(&{&1.stated_on != nil, stated_days(&1.stated_on), &1.id}, fn -> nil end)
  end

  # -- grouping -----------------------------------------------------------------

  @doc """
  Groups `entries` under `headers` (in their order) by each entry's `gall`
  (a header's `key`): each header gains `facts`, category to entries in
  the order given, `:traits` a map of Trait to entries. An entry whose
  Gall has no header gets one (`%{key, gall_id: key}` for an integer key),
  after the others.
  """
  @spec group([header()], [entry()]) :: [header()]
  def group(headers, entries) do
    by_gall = Enum.group_by(entries, & &1.gall)
    known = MapSet.new(headers, & &1.key)

    extra =
      for %{gall: key} <- entries,
          not MapSet.member?(known, key),
          uniq: true,
          do: default_header(key)

    for header <- headers ++ extra do
      Map.put(header, :facts, by_category(Map.get(by_gall, header.key, [])))
    end
  end

  defp default_header(key) do
    %{
      key: key,
      ref: nil,
      gall_id: if(is_integer(key), do: key),
      new: false,
      name_as_written: nil,
      name: nil,
      status: nil,
      question: nil,
      why: nil
    }
  end

  defp by_category(entries) do
    grouped = Enum.group_by(entries, & &1.category)

    @categories
    |> Map.new(&{&1, Map.get(grouped, &1, [])})
    |> Map.update!(:traits, fn traits ->
      Enum.group_by(traits, & &1.value.trait)
    end)
  end
end
