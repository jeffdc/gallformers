defmodule Gallformers.CatalogMigration.Galls do
  @moduledoc """
  Galls and their Inducer taxa from today's gall rows (`9449` §6, Task 15;
  `b5bd` M2).

  Each gall row's name is read through the name-suffix mapping
  (`Gallformers.CatalogMigration.NameSuffixes`), and its Inducer link
  decided from its genus link:

    * a **described** gall in a real genus links to a species-rank Inducer
      named by its name without suffixes (a binomial whose genus is the
      linked genus). Rows naming the same Inducer under the same parent —
      an agamic/sexgen pair, Galls of one species on different hosts or
      plant parts — share one Inducer taxon (new ID, kingdom from its
      genus);
    * an **undescribed** gall in a real genus links to the genus (or the
      section it is linked to);
    * a gall in a **placeholder genus** ("Unknown (Cynipidae)") links to the
      family; in "Unknown (Unknown)" it gets no Inducer;
    * a gall with **no genus link**, or a described one whose name the
      mapping cannot read, gets no Inducer and is reported.

  Every link is recorded in the crosswalk (`legacy_taxon_ids`, kind
  `:gall_inducer`, by gall species ID). The Inducer Fact itself is a legacy
  Fact (`Gallformers.CatalogMigration.LegacyFacts`).

  Each gall row becomes a Gall keeping its species ID, Gallformers Code,
  abundance and `datacomplete`, with the generation the mapping gives. Its
  name parts are read from its name and its `name` derived from them, with
  today's name kept as `name_override` only where the derived name differs
  (`Gallformers.CatalogMigration.GallNames`), so every name shown stays as
  it is.

  Each Gall's `default_source_id` — the Source its page leads with (`803b`
  decision 3) — is the Source of its `species_source` row marked
  `useasdefault`, its Gallformers note or a citation alike. A gall with
  several such rows keeps the lowest row's and is reported.
  """

  alias Gallformers.Catalog
  alias Gallformers.CatalogMigration.GallNames
  alias Gallformers.CatalogMigration.NameSuffixes
  alias Gallformers.CatalogMigration.Old
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.CatalogMigration.Taxa, as: MigrationTaxa

  @binomial ~r/^\p{Lu}\p{Ll}+ \p{Ll}[\p{Ll}-]*$/u

  @type target ::
          {:species, String.t(), integer() | nil}
          | {:taxon, integer() | nil, :genus | :family}
          | {:none, :unknown_unknown | :no_genus | :unparsed}

  @type generations :: %{String.t() => %{id: integer(), qualifier: String.t()}}

  @type gall :: %{
          id: integer(),
          name: String.t(),
          generation: String.t() | nil,
          inducer_id: integer() | nil,
          level: :species | :genus | :family | nil
        }

  @doc """
  Creates the Inducer taxa, their crosswalk entries and the Galls, as
  `actor`. `generations` maps generation values to their IDs and name
  qualifiers; the gall rows in `excluded` (non-galls,
  `Gallformers.CatalogMigration.NonGalls`) are not migrated. Returns the
  Galls as migrated (with their Inducer taxon, if any).
  """
  @spec run(
          Gallformers.Audit.Actor.t(),
          NameSuffixes.t(),
          generations(),
          MigrationTaxa.t(),
          Report.t(),
          MapSet.t(integer())
        ) :: {[gall()], Report.t()}
  def run(actor, suffixes, generations, taxa, report, excluded \\ MapSet.new()) do
    links = Old.links("gall")
    {skipped, rows} = Enum.split_with(Old.galls(), &MapSet.member?(excluded, &1.id))
    defaults = default_sources()
    default_of = Map.new(defaults.by_species, fn {id, [first | _]} -> {id, first.source_id} end)

    read = Enum.map(rows, &read_gall(&1, suffixes, Map.get(links, &1.id), taxa))
    inducers = create_inducers(actor, read, taxa)

    {galls, names} =
      read
      |> Enum.map(fn gall ->
        {inducer_id, level} = inducer(gall.target, inducers)

        if inducer_id,
          do:
            MigrationTaxa.legacy_id!(actor, inducer_id, :gall_inducer, gall.row.id, gall.row.name)

        generation = gall.generation && Map.fetch!(generations, gall.generation)
        name = GallNames.read(suffixes, gall.row, inducer_id, level, generation)
        create_gall!(actor, gall, name, generation, default_of[gall.row.id])

        {%{
           id: gall.row.id,
           name: gall.row.name,
           generation: gall.generation,
           inducer_id: inducer_id,
           level: level
         }, name}
      end)
      |> Enum.unzip()

    report =
      report
      |> report(read, galls, inducers, length(skipped))
      |> GallNames.report(names)
      |> report_defaults(defaults, read)

    {galls, report}
  end

  # Today's default descriptions (`species_source.useasdefault`), a citation
  # or the Gallformers note alike, by species: each species' rows in
  # `species_source` ID order (the lowest is kept).
  defp default_sources do
    rows =
      Old.rows("""
      SELECT ss.id, ss.species_id, ss.source_id, src.kind = 'gallformers' AS note
      FROM species_source ss JOIN source src ON src.id = ss.source_id
      WHERE ss.useasdefault
      ORDER BY ss.id
      """)

    %{rows: rows, by_species: Enum.group_by(rows, & &1.species_id)}
  end

  # -- reading a gall row ----------------------------------------------------------

  defp read_gall(row, suffixes, link, taxa) do
    parsed = NameSuffixes.parse(suffixes, row.id, row.name)

    {generation, review, parse_error} =
      case parsed do
        {:ok, p} -> {p.generation, p.review, nil}
        {:error, reason} -> {nil, nil, reason}
      end

    {target, problem} = target(row, parsed, link, taxa)

    %{
      row: row,
      generation: generation,
      review: review,
      unparsed: problem || parse_error,
      target: target
    }
  end

  # {target, why it is unparsed or nil}
  defp target(_row, _parsed, nil, _taxa), do: {{:none, :no_genus}, nil}
  defp target(_row, _parsed, %{genus: nil}, _taxa), do: {{:none, :no_genus}, nil}

  defp target(row, parsed, %{genus: genus_id, section: section_id}, taxa) do
    genus = taxa.rows[genus_id]
    parent = taxa.anchors[section_id] || taxa.anchors[genus_id]

    cond do
      genus.is_placeholder -> placeholder_target(taxa.anchors[genus_id])
      row.undescribed -> {{:taxon, parent, :genus}, nil}
      true -> species_target(parsed, genus, parent)
    end
  end

  # A placeholder genus's anchor is its family, or nil under Unknown.
  defp placeholder_target(nil), do: {{:none, :unknown_unknown}, nil}
  defp placeholder_target(family), do: {{:taxon, family, :family}, nil}

  defp species_target({:error, reason}, _genus, _parent), do: {{:none, :unparsed}, reason}

  defp species_target({:ok, %{base: nil}}, _genus, _parent),
    do: {{:none, :unparsed}, "the curated row names no Inducer for a described gall"}

  defp species_target({:ok, %{base: base}}, genus, parent) do
    cond do
      not Regex.match?(@binomial, base) ->
        {{:none, :unparsed}, "#{inspect(base)} is not a binomial"}

      hd(String.split(base)) != String.trim(genus.name) ->
        {{:none, :unparsed}, "#{inspect(base)} is not in its genus #{genus.name}"}

      true ->
        {{:species, base, parent}, nil}
    end
  end

  # -- Inducer taxa ----------------------------------------------------------------

  # One species taxon per name and parent, created in name order.
  defp create_inducers(actor, read, taxa) do
    read
    |> Enum.flat_map(fn
      %{target: {:species, name, parent}} -> [{name, parent}]
      _other -> []
    end)
    |> Enum.uniq()
    |> Enum.sort()
    |> Map.new(fn {name, parent} = key ->
      kingdom = parent && taxa.taxa[parent].kingdom

      taxon =
        MigrationTaxa.create_taxon!(actor, %{
          rank: :species,
          origin: MigrationTaxa.origin(kingdom),
          name: name,
          parent_id: parent,
          kingdom: kingdom
        })

      {key, taxon.id}
    end)
  end

  defp inducer({:species, name, parent}, inducers),
    do: {Map.fetch!(inducers, {name, parent}), :species}

  defp inducer({:taxon, nil, _level}, _inducers), do: {nil, nil}
  defp inducer({:taxon, id, level}, _inducers), do: {id, level}
  defp inducer({:none, _why}, _inducers), do: {nil, nil}

  # -- Galls -----------------------------------------------------------------------

  defp create_gall!(actor, gall, name, generation, default_source_id) do
    row = gall.row

    attrs = %{
      id: row.id,
      name: name.stored_name,
      name_override: name.name_override,
      form_label: name.form_label,
      host_qualifier_taxon_id: name.host_qualifier_taxon_id,
      descriptor: name.descriptor,
      gallformers_code: blank_nil(row.gallformers_code),
      generation_value_id: generation && generation.id,
      abundance_id: row.abundance_id,
      datacomplete: row.datacomplete,
      default_source_id: default_source_id
    }

    case Catalog.create_gall(actor, attrs) do
      {:ok, created} ->
        created

      {:error, changeset} ->
        raise "could not create Gall #{row.id} #{row.name}: #{inspect(changeset.errors)}"
    end
  end

  defp blank_nil(nil), do: nil

  defp blank_nil(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # -- report ----------------------------------------------------------------------

  defp report(report, read, galls, inducers, excluded) do
    by_level = Enum.frequencies_by(galls, & &1.level)
    none = Enum.frequencies_by(read, &none_reason(&1.target))
    non_galls = {"non-galls excluded (non_galls.csv)", excluded}

    generations_by_inducer =
      galls
      |> Enum.filter(&(&1.level == :species))
      |> Enum.group_by(& &1.inducer_id, & &1.generation)

    shared = Enum.count(generations_by_inducer, fn {_id, gens} -> length(gens) > 1 end)

    pairs =
      Enum.count(generations_by_inducer, fn {_id, gens} ->
        "agamic" in gens and "sexual" in gens
      end)

    report
    |> Report.reconcile("Galls", length(read) + excluded, length(galls), [non_galls])
    |> Report.reconcile(
      "Gall Inducer links",
      length(read) + excluded,
      Map.get(by_level, :species, 0),
      [
        non_galls,
        {"at the genus or section (undescribed)", Map.get(by_level, :genus, 0)},
        {"at the family (placeholder genus)", Map.get(by_level, :family, 0)},
        {"none: Unknown (Unknown)", Map.get(none, :unknown_unknown, 0)},
        {"none: no genus link", Map.get(none, :no_genus, 0)},
        {"none: unparsed name", Map.get(none, :unparsed, 0)}
      ]
    )
    |> Report.count("Inducer taxa created (species)", map_size(inducers))
    |> Report.count("Inducers shared by several Galls", shared)
    |> Report.count("agamic/sexgen pairs merged into one Inducer", pairs)
    |> Report.galls(:needs_review, notes(read, :review))
    |> Report.galls(:unparsed, notes(read, :unparsed))
    |> Report.problems(
      "gall without a genus link (no Inducer)",
      for(%{target: {:none, :no_genus}, row: row} <- read, do: "#{row.id} #{row.name}")
    )
  end

  defp report_defaults(report, defaults, read) do
    names = Map.new(read, &{&1.row.id, &1.row.name})

    {on_galls, elsewhere} =
      Enum.split_with(defaults.rows, &Map.has_key?(names, &1.species_id))

    kept = for {id, [first | _]} <- defaults.by_species, Map.has_key?(names, id), do: first

    several =
      for {id, [first | _] = rows} <- Enum.sort(defaults.by_species),
          Map.has_key?(names, id),
          length(rows) > 1 do
        ids = Enum.map_join(rows, ", ", & &1.id)
        "#{id} #{names[id]}: species_source #{ids} (#{first.id} kept)"
      end

    report
    |> Report.reconcile(
      "Default Sources (species_source useasdefault)",
      length(defaults.rows),
      Old.count("SELECT count(*) FROM galls WHERE default_source_id IS NOT NULL"),
      [
        {"on species that are not Galls", length(elsewhere)},
        {"further defaults of a Gall (the lowest species_source ID kept)",
         length(on_galls) - length(kept)}
      ]
    )
    |> Report.count(
      "Galls whose default Source is their Gallformers note",
      Enum.count(kept, & &1.note)
    )
    |> Report.problems("Gall with several default Sources", several)
  end

  defp none_reason({:none, why}), do: why
  defp none_reason(_target), do: nil

  defp notes(read, field) do
    for %{row: row} = gall <- read, reason = Map.fetch!(gall, field), reason != nil do
      %{gall_id: row.id, name: row.name, reason: reason}
    end
  end
end
