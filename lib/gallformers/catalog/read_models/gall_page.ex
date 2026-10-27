defmodule Gallformers.Catalog.ReadModels.GallPage do
  @moduledoc """
  Everything the Gall page (`/gall/:id`) shows of a Gall, in one struct
  (`803b` Task 3), built on `Gallformers.Catalog.ReadModels.GallSummary`
  (current Inducer, Hosts, Traits) and
  `Gallformers.Catalog.ReadModels.PotentialRange` (the display range).

    * the Gall: `name` (display name), `gallformers_code`, `abundance`,
      `datacomplete`, `generation` (value, name qualifier, definition);
    * `undescribed?` — no current species-rank Inducer;
    * `inducers` — the current Inducers (normally one), each with its
      `lineage` root first (`Gallformers.Taxa.lineage/1`);
    * `hosts` — the current Hosts, each with its `link`: `{:host, id}` for a
      species-rank plant, `{rank, name}` for a higher taxon (a genus Host
      links to its genus page);
    * `traits` — current Trait values by Trait;
    * `common_names` (current alias Facts of kind `:common_name`), `labels`
      (the other current alias Facts — former labels and codes —
      `%{name, kind}`) and `synonyms` (the Inducers' synonyms,
      `%{name, sensu}`);
    * `related_galls` — other Galls with the same current species-rank
      Inducer (alternate generations and forms), by name;
    * `sources` — the legacy citations and the newest Gallformers note: the
      Gall's default Source (`default_source_id`, a citation, the note, or
      any other of its Sources, `Gallformers.Catalog.gall_sources/1`, such as
      one that only attributes Facts — listed then without a description)
      first, the note next, then by title. Each is the Source's fields with
      the citation's `description` (the note's text), `useasdefault` (it is
      the Gall's default Source), `externallink` and `note?`;
    * `images` (by `image.gall_id`) and `display_range`;
    * `attributions` — every current Fact's attributions, keyed by what the
      Fact says: `{:inducer, taxon_id}`, `{:host, taxon_id}`,
      `{:trait, trait, value}`, `{:alias, name}`,
      `{:range, adjustment, place_id}`. Loaded, not shown yet: per-Fact
      Source display is designed after the backscan.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.LegacyCitation
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Catalog.ReadModels.GallSummary
  alias Gallformers.Catalog.ReadModels.PotentialRange
  alias Gallformers.Catalog.Vocab.GenerationValue
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Images
  alias Gallformers.Images.Image
  alias Gallformers.Ranges.DisplayRange
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank

  # Ranks at which an Inducer is a described species (or below).
  @species_ranks [:species, :subspecies, :variety, :form]

  @type taxon :: %{taxon_id: integer(), name: String.t(), rank: Rank.t()}

  @type inducer :: %{
          taxon_id: integer(),
          name: String.t(),
          rank: Rank.t(),
          lineage: [Taxa.lineage_entry()]
        }

  @type host :: %{
          taxon_id: integer(),
          name: String.t(),
          rank: Rank.t(),
          link: {:host, integer()} | {Rank.t(), String.t()}
        }

  @type source :: %{
          id: integer(),
          title: String.t(),
          author: String.t() | nil,
          pubyear: String.t() | nil,
          link: String.t() | nil,
          citation: String.t() | nil,
          license: String.t() | nil,
          licenselink: String.t() | nil,
          description: String.t(),
          useasdefault: boolean(),
          externallink: String.t(),
          note?: boolean()
        }

  @type attribution_key ::
          {:inducer | :host, integer()}
          | {:trait, String.t(), String.t()}
          | {:alias, String.t()}
          | {:range, atom(), integer()}

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          gallformers_code: String.t() | nil,
          abundance: String.t() | nil,
          datacomplete: boolean(),
          generation:
            %{value: String.t(), name_qualifier: String.t(), definition: String.t() | nil} | nil,
          undescribed?: boolean(),
          inducers: [inducer()],
          hosts: [host()],
          traits: %{String.t() => [String.t()]},
          common_names: [String.t()],
          labels: [%{name: String.t(), kind: :former_label | :code}],
          synonyms: [%{name: String.t(), sensu: String.t() | nil}],
          related_galls: [%{id: integer(), name: String.t()}],
          sources: [source()],
          images: [Image.t()],
          display_range: :everywhere | DisplayRange.t(),
          attributions: %{attribution_key() => [Attribution.t()]},
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:id, :name]
  defstruct [
    :id,
    :name,
    :gallformers_code,
    :abundance,
    :generation,
    :display_range,
    :inserted_at,
    :updated_at,
    datacomplete: false,
    undescribed?: false,
    inducers: [],
    hosts: [],
    traits: %{},
    common_names: [],
    labels: [],
    synonyms: [],
    related_galls: [],
    sources: [],
    images: [],
    attributions: %{}
  ]

  @doc "The Gall page of Gall `id`, or `:not_found` when there is no such Gall."
  @spec for_gall(integer()) :: {:ok, t()} | :not_found
  def for_gall(id) when is_integer(id) do
    case Repo.get(Gall, id) do
      nil -> :not_found
      gall -> {:ok, build(gall)}
    end
  end

  defp build(%Gall{} = gall) do
    summary = GallSummary.for_gall(gall.id)
    undescribed? = not Enum.any?(summary.inducers, &(&1.rank in @species_ranks))
    {common_names, labels} = aliases(gall.id)

    %__MODULE__{
      id: gall.id,
      name: summary.name,
      gallformers_code: gall.gallformers_code,
      abundance: abundance(gall.abundance_id),
      datacomplete: gall.datacomplete,
      generation: generation(gall.generation_value_id),
      undescribed?: undescribed?,
      inducers: Enum.map(summary.inducers, &Map.put(&1, :lineage, Taxa.lineage(&1.taxon_id))),
      hosts: Enum.map(summary.hosts, &Map.put(&1, :link, host_link(&1))),
      traits: summary.traits,
      common_names: common_names,
      labels: labels,
      synonyms: synonyms(summary.inducers),
      related_galls: if(undescribed?, do: [], else: related_galls(gall.id, summary.inducers)),
      sources: sources(gall),
      images: Images.list_images_for_gall(gall.id),
      display_range: PotentialRange.for_display(gall.id),
      attributions: attributions(gall.id),
      inserted_at: gall.inserted_at,
      updated_at: gall.updated_at
    }
  end

  defp abundance(nil), do: nil

  defp abundance(id),
    do: Repo.one(from(a in "abundance", where: a.id == ^id, select: a.abundance))

  defp generation(nil), do: nil

  defp generation(id) do
    value = Repo.get!(GenerationValue, id)
    %{value: value.value, name_qualifier: value.name_qualifier, definition: value.definition}
  end

  defp host_link(%{rank: rank, taxon_id: id}) when rank in @species_ranks, do: {:host, id}
  defp host_link(%{rank: rank, name: name}), do: {rank, name}

  # {common names, former labels and codes}, each by name.
  defp aliases(gall_id) do
    {common, labels} =
      from(a in Current.aliases(gall_id),
        order_by: [a.name],
        select: %{name: a.name, kind: a.kind}
      )
      |> Repo.all()
      |> Enum.split_with(&(&1.kind == :common_name))

    {Enum.map(common, & &1.name), labels}
  end

  defp synonyms(inducers) do
    for inducer <- inducers, name <- Taxa.list_synonyms(inducer.taxon_id) do
      %{name: name.name, sensu: name.sensu}
    end
  end

  defp related_galls(gall_id, inducers) do
    inducer_ids = Enum.map(inducers, & &1.taxon_id)

    from(r in Current.relationships("inducer_of"),
      join: g in Gall,
      on: g.id == r.object_gall_id,
      where: r.subject_taxon_id in ^inducer_ids and g.id != ^gall_id,
      distinct: true,
      select: g
    )
    |> Repo.all()
    |> Enum.map(&%{id: &1.id, name: Gall.display_name(&1)})
    |> Enum.sort_by(&{&1.name, &1.id})
  end

  # -- Sources -----------------------------------------------------------------

  @doc """
  A Gall's Sources as its page lists them (`sources` above): the legacy
  citations and the newest Gallformers note, the default Source first (also
  when it is neither).
  """
  @spec sources(Gall.t()) :: [source()]
  def sources(%Gall{id: gall_id, default_source_id: default_id}) do
    citations =
      Repo.all(from(c in LegacyCitation, where: c.gall_id == ^gall_id, order_by: c.source_id))

    note = newest_note(gall_id)
    source_ids = Enum.map(citations, & &1.source_id) ++ if(note, do: [note.source_id], else: [])
    by_id = source_ids |> Sources.list_sources_by_id() |> Map.new(&{&1.id, &1})

    entries =
      for citation <- citations, source = by_id[citation.source_id] do
        entry(source, citation.description, source.id == default_id, citation.externallink, false)
      end

    entries =
      case note && by_id[note.source_id] do
        nil -> entries
        source -> [entry(source, note.text, source.id == default_id, "", true) | entries]
      end

    entries = entries ++ lead_only(default_id, Map.keys(by_id))

    Enum.sort_by(entries, fn entry ->
      cond do
        entry.useasdefault -> {0, entry.title}
        entry.note? -> {1, entry.title}
        true -> {2, entry.title}
      end
    end)
  end

  # The lead Source when neither a citation nor the note gives it (a Source
  # that only attributes Facts about the Gall), without a description.
  defp lead_only(nil, _listed_ids), do: []

  defp lead_only(default_id, listed_ids) do
    if default_id in listed_ids do
      []
    else
      for source <- Sources.list_sources_by_id([default_id]),
          do: entry(source, "", true, "", false)
    end
  end

  defp newest_note(gall_id) do
    case Sources.list_gall_notes(gall_id) do
      [] ->
        nil

      [newest | _] ->
        text = newest |> Sources.list_document_items() |> Enum.map_join("\n\n", & &1.text)
        %{source_id: newest.source_id, text: text}
    end
  end

  defp entry(source, description, useasdefault, externallink, note?) do
    %{
      id: source.id,
      title: source.title,
      author: source.author,
      pubyear: source.pubyear,
      link: source.link,
      citation: source.citation,
      license: source.license,
      licenselink: source.licenselink,
      description: description,
      useasdefault: useasdefault,
      externallink: externallink,
      note?: note?
    }
  end

  # -- attributions ------------------------------------------------------------

  defp attributions(gall_id) do
    keyed = current_fact_keys(gall_id)
    by_fact = keyed |> Enum.map(&elem(&1, 0)) |> Facts.list_attributions_for_facts()

    for {fact_id, key} <- keyed, into: %{}, do: {key, Map.get(by_fact, fact_id, [])}
  end

  # Each current Fact about the Gall: {fact_id, what it says}.
  defp current_fact_keys(gall_id) do
    relationships =
      from(r in Current.relationships("inducer_of"),
        where: r.object_gall_id == ^gall_id,
        select: {r.fact_id, {:inducer, r.subject_taxon_id}}
      )

    hosts =
      from(r in Current.relationships("host_of"),
        where: r.object_gall_id == ^gall_id,
        select: {r.fact_id, {:host, r.subject_taxon_id}}
      )

    traits =
      from(t in Current.traits(gall_id),
        join: v in TraitValue,
        on: v.id == t.trait_value_id,
        select: {t.fact_id, {:trait, v.trait, v.value}}
      )

    aliases = from(a in Current.aliases(gall_id), select: {a.fact_id, {:alias, a.name}})

    ranges =
      from(r in Current.range_adjustments(gall_id),
        select: {r.fact_id, {:range, r.adjustment, r.place_id}}
      )

    Enum.flat_map([relationships, hosts, traits, aliases, ranges], &Repo.all/1)
  end
end
