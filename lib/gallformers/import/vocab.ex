defmodule Gallformers.Import.Vocab do
  @moduledoc """
  Writes the import contract's vocabulary files (`priv/import/vocab/`) from
  the database and code (`294c` step 3; `mix gallformers.import.vocab`):

    * `traits.json` and `traits.schema.json` — the Trait values with their
      definitions (`trait_values`), the term mappings
      (`trait_term_mappings`), and the generation groups
      (`generation_groups`, `generation_values`, `generation_group_taxa`):
      each value with its definition and other names (the term mappings of
      trait `"generation"`), each group with its values and its taxa
      (accepted name and rank, through `Gallformers.Taxa`);
    * `places.json` and `place-codes.schema.json` — every place
      (`Gallformers.Places.list_all_places/0`);
    * `licenses.schema.json` (`Gallformers.Licenses.all/0`),
      `ranks.schema.json` (`Gallformers.Taxa.Rank.all/0`) and
      `relationships.schema.json` (`Gallformers.Catalog.RelationshipTypes`).

  The data comes from the database and code; the prose (each Trait's
  `about`, the files' titles and descriptions) is held here. Producers read
  it, so it says what a field is and what to put in it.

  The output is deterministic. Traits come in `TraitValue.traits/0`'s order,
  generation first; Trait values and term mappings in the order they were
  added (by ID), which is the contract's order; generation groups in the
  order defined, their values by position and their taxa by name; places by
  code. Each file keeps its formatting: `traits.json` is indented two
  spaces, `places.json` and `place-codes.schema.json` four; the other
  schemas two, with lists of values, and objects short enough, on one line.
  Every file ends in a newline.

  ## Version

  `traits.json` and `places.json` carry the `vocabulary_version` all the
  files share: a date. `write/2` keeps the date the files carry while their
  content stays the same, and dates them today (`today/0`) when it changes (or as the
  `:version` option says). `check/1` compares with that date.

  Until cutover `Gallformers.Catalog.Vocab.Loader` loads the Trait values
  and term mappings from `traits.json`, and the generation groups and values
  from its own list, so the database and the shipped file must agree:
  loading the file and generating it again reproduces it (tested).
  """

  alias Gallformers.Catalog
  alias Gallformers.Catalog.RelationshipTypes
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Licenses
  alias Gallformers.Places
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias Jason.OrderedObject

  @files ~w(traits.json traits.schema.json places.json place-codes.schema.json
            licenses.schema.json ranks.schema.json relationships.schema.json)

  @draft "https://json-schema.org/draft/2020-12/schema"
  @id_base "https://gallformers.org/schemas/import/v3/vocab/"

  # -- prose ---------------------------------------------------------------------

  @traits_description "What each Trait value means, how common Source terms map onto values, " <>
                        "and the generation groups. A value's definition decides whether it " <>
                        "fits; the value is shorthand for its definition. traits.schema.json " <>
                        "lists the allowed values."

  @abouts %{
    "generation" =>
      "The stage of the Inducer's life cycle that induces the Gall. It identifies the Gall " <>
        "(galls[].identified_by). The values come in groups, each for the taxa it names: " <>
        "choose from the group for the Inducer's taxon.",
    "detachable" =>
      "Whether the Gall can be removed from the Host without cutting it out or destroying " <>
        "the surrounding tissue. One value per Gall.",
    "plant_part" =>
      "Where on the plant the Gall is: the most precise location the Source supports.",
    "form" => "The Gall's overall type.",
    "shape" => "The Gall's shape.",
    "color" => "The Gall's colors.",
    "texture" => "The Gall's surface.",
    "alignment" => "How the Gall stands relative to the surface it is attached to.",
    "walls" => "What the Gall shows when cut open.",
    "cells" => "The Gall's larval chambers.",
    "season" =>
      "When the Gall forms and grows. Not when it is seen or found, and not when the " <>
        "Inducer emerges: rearing and emergence dates don't count."
  }

  @traits_schema_description "The allowed values of each Trait and of generation. traits.json " <>
                               "holds their definitions, the term mappings and the generation " <>
                               "groups."

  @generation_schema_description "Every generation value, from all the groups. Choose from the " <>
                                   "group for the Inducer's taxon (traits.json, " <>
                                   "traits.generation.groups)."

  @places_description "Every Gallformers place, with its code, name and type (continent, " <>
                        "country, state or province): find the code for a place the Source " <>
                        "names. place-codes.schema.json lists the codes."

  @place_codes_description "Gallformers place codes (ISO 3166 style; continents use X-codes). " <>
                             "places.json gives each code's place name."

  @licenses_description "The license a Source carries. A Source with no stated license is " <>
                          "'All Rights Reserved', unless it is in the public domain by age or " <>
                          "origin."

  @ranks_description "The ranks a taxon reference may have: any Linnaean rank, kingdom to " <>
                       "form. Synonymy and split acts are at family rank or below."

  @relationships_description "The Relationship types, grouped by their endpoints, and the " <>
                               "qualifiers' values. PRODUCER_GUIDE.md, Phase 3 (Relationships, " <>
                               "Qualifiers), gives their meanings."

  @endpoint_groups [
    {"taxon_to_gall", :taxon_to_gall, "Subject is an organism (taxon); object is a Gall."},
    {"gall_to_gall", :gall_to_gall, "Subject and object are Galls."},
    {"taxon_to_taxon_in_gall", :taxon_to_taxon_in_gall,
     "Subject and object are organisms; the Relationship happens in a Gall (gall_context)."}
  ]

  # The qualifiers whose values are words; required_for_formation's value is
  # `true` (gall.schema.json).
  @word_qualifiers ~w(lethality parasitism_mode)

  # -- API -----------------------------------------------------------------------

  @typedoc "The rendered files: file name => contents."
  @type files :: %{String.t() => String.t()}

  @doc "The names of the files written, in `priv/import/vocab/`."
  @spec file_names() :: [String.t()]
  def file_names, do: @files

  @doc """
  Every vocabulary file, rendered from the database and code with
  `vocabulary_version` `version`.
  """
  @spec render(String.t() | nil) :: files()
  def render(version), do: render_files(collect(), version)

  @doc """
  Writes the files that differ into `dir` (created if missing). The version
  is the `:version` option (a `YYYY-MM-DD` date) when given; otherwise the
  one the files in `dir` carry while their content is unchanged, else today.
  Returns the version and the names of the files written, sorted.
  """
  @spec write(Path.t(), keyword()) ::
          {:ok, %{version: String.t(), written: [String.t()]}}
          | {:error, {:invalid_version, term()}}
  def write(dir, opts \\ []) do
    with {:ok, given} <- given_version(Keyword.get(opts, :version)) do
      data = collect()
      version = given || current_version(dir, data)
      files = render_files(data, version)
      written = differing(dir, files)

      if written != [], do: File.mkdir_p!(dir)
      for name <- written, do: File.write!(Path.join(dir, name), Map.fetch!(files, name))

      {:ok, %{version: version, written: written}}
    end
  end

  @doc """
  Whether the files in `dir` are what `write/2` would write with the
  version they carry: `:ok`, or the names of the files that differ (missing
  ones included), sorted. Writes nothing.
  """
  @spec check(Path.t()) :: :ok | {:error, [String.t()]}
  def check(dir) do
    case differing(dir, render(committed_version(dir))) do
      [] -> :ok
      names -> {:error, names}
    end
  end

  @doc "The `vocabulary_version` the files in `dir` carry (`traits.json`'s), or nil."
  @spec committed_version(Path.t()) :: String.t() | nil
  def committed_version(dir) do
    with {:ok, text} <- File.read(Path.join(dir, "traits.json")),
         {:ok, %{"vocabulary_version" => version}} when is_binary(version) <- Jason.decode(text) do
      version
    else
      _ -> nil
    end
  end

  defp given_version(nil), do: {:ok, nil}

  defp given_version(version) when is_binary(version) do
    case Date.from_iso8601(version) do
      {:ok, _date} -> {:ok, version}
      {:error, _} -> {:error, {:invalid_version, version}}
    end
  end

  defp given_version(version), do: {:error, {:invalid_version, version}}

  defp current_version(dir, data) do
    committed = committed_version(dir)

    if committed && differing(dir, render_files(data, committed)) == [],
      do: committed,
      else: today()
  end

  @doc "Today's date where the task runs (the local date), as `YYYY-MM-DD`."
  @spec today() :: String.t()
  def today do
    {date, _time} = :calendar.local_time()
    date |> Date.from_erl!() |> Date.to_iso8601()
  end

  defp differing(dir, files) do
    for name <- Enum.sort(Map.keys(files)),
        File.read(Path.join(dir, name)) != {:ok, Map.fetch!(files, name)},
        do: name
  end

  # -- data ----------------------------------------------------------------------

  defp collect do
    {other_names, mappings} =
      Enum.split_with(Catalog.list_trait_term_mappings(), &(&1.trait == "generation"))

    %{
      trait_values:
        Catalog.list_trait_values()
        |> Enum.sort_by(& &1.id)
        |> Enum.group_by(& &1.trait),
      mappings: mappings,
      groups: generation_groups(other_names),
      places: Enum.sort_by(Places.list_all_places(), & &1.code)
    }
  end

  defp generation_groups(other_names) do
    for group <- Catalog.list_generation_groups() do
      %{
        name: group.name,
        values:
          for value <- group.values do
            %{
              value: value.value,
              definition: value.definition,
              other_names: other_names_of(value.value, other_names)
            }
          end,
        taxa: group.taxa |> Enum.map(&taxon(&1.taxon_id)) |> Enum.sort_by(&{&1.name, &1.rank})
      }
    end
  end

  # A generation value's other names: the terms mapped onto it, each a
  # comma-separated list of names.
  defp other_names_of(value, mappings) do
    for mapping <- mappings,
        value in mapping.maps_to,
        name <- String.split(mapping.term, ", "),
        do: name
  end

  defp taxon(id) do
    taxon = Taxa.get_taxon!(id)
    %{name: Taxa.accepted_name(taxon), rank: Atom.to_string(taxon.rank)}
  end

  # -- files ---------------------------------------------------------------------

  defp render_files(data, version) do
    %{
      "traits.json" => expanded(traits_json(data, version), "  "),
      "traits.schema.json" => compact(traits_schema(data)),
      "places.json" => expanded(places_json(data.places, version), "    "),
      "place-codes.schema.json" => expanded(place_codes_schema(data.places), "    "),
      "licenses.schema.json" => compact(licenses_schema()),
      "ranks.schema.json" => compact(ranks_schema()),
      "relationships.schema.json" => compact(relationships_schema())
    }
  end

  defp traits_json(data, version) do
    traits =
      for trait <- TraitValue.traits() do
        values =
          for value <- Map.get(data.trait_values, trait, []),
              do: object([{"value", value.value}, {"definition", value.definition}])

        {trait, object([{"about", Map.fetch!(@abouts, trait)}, {"values", values}])}
      end

    object([
      {"vocabulary", "traits"},
      {"vocabulary_version", version},
      {"description", @traits_description},
      {"traits", object([{"generation", generation(data.groups)} | traits])},
      {"mappings", Enum.map(data.mappings, &mapping/1)}
    ])
  end

  defp generation(groups) do
    values =
      for group <- groups, value <- group.values do
        object([
          {"value", value.value},
          {"definition", value.definition},
          {"other_names", value.other_names}
        ])
      end

    groups =
      for group <- groups do
        object([
          {"name", group.name},
          {"values", Enum.map(group.values, & &1.value)},
          {"taxa", for(t <- group.taxa, do: object([{"name", t.name}, {"rank", t.rank}]))}
        ])
      end

    object([
      {"about", Map.fetch!(@abouts, "generation")},
      {"values", values},
      {"groups", groups}
    ])
  end

  # A mapping's fields, leaving out those it has no value for.
  defp mapping(mapping) do
    [
      {"term", mapping.term},
      {"trait", mapping.trait},
      {"maps_to", mapping.maps_to},
      {"candidates", mapping.candidates},
      {"rule", mapping.rule}
    ]
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
    |> object()
  end

  defp traits_schema(data) do
    generation_values = for group <- data.groups, value <- group.values, do: value.value

    traits =
      for trait <- TraitValue.traits() do
        values = for value <- Map.get(data.trait_values, trait, []), do: value.value
        {trait, object([{"enum", values}])}
      end

    generation =
      object([{"description", @generation_schema_description}, {"enum", generation_values}])

    schema("traits.schema.json", "Gall Trait vocabularies", @traits_schema_description, [
      {"$defs", object([{"generation", generation} | traits])}
    ])
  end

  defp places_json(places, version) do
    object([
      {"vocabulary", "places"},
      {"vocabulary_version", version},
      {"description", @places_description},
      {"places",
       for(p <- places, do: object([{"code", p.code}, {"name", p.name}, {"type", p.type}]))}
    ])
  end

  defp place_codes_schema(places) do
    schema("place-codes.schema.json", "Place codes", @place_codes_description, [
      {"enum", Enum.map(places, & &1.code)}
    ])
  end

  defp licenses_schema do
    schema("licenses.schema.json", "Licenses", @licenses_description, [
      {"enum", Licenses.all()}
    ])
  end

  defp ranks_schema do
    schema("ranks.schema.json", "Taxon ranks", @ranks_description, [
      {"enum", Enum.map(Rank.all(), &Atom.to_string/1)}
    ])
  end

  defp relationships_schema do
    all =
      object([
        {"description", "All Relationship types (the union of the three endpoint groups below)."},
        {"enum", RelationshipTypes.names()}
      ])

    groups =
      for {name, endpoints, description} <- @endpoint_groups do
        {name,
         object([{"description", description}, {"enum", RelationshipTypes.names(endpoints)}])}
      end

    qualifiers =
      for qualifier <- @word_qualifiers,
          do: {qualifier, object([{"enum", RelationshipTypes.qualifier_values(qualifier)}])}

    schema(
      "relationships.schema.json",
      "Relationship types and qualifiers",
      @relationships_description,
      [{"$defs", object([{"type", all}] ++ groups ++ qualifiers)}]
    )
  end

  defp schema(file, title, description, body) do
    object(
      [
        {"$schema", @draft},
        {"$id", @id_base <> file},
        {"title", title},
        {"description", description}
      ] ++ body
    )
  end

  defp object(pairs), do: OrderedObject.new(pairs)

  # -- JSON formatting -----------------------------------------------------------

  # Every object and list on its own lines, indented by `indent`.
  defp expanded(json, indent), do: Jason.encode!(json, pretty: [indent: indent]) <> "\n"

  # The hand-written schemas' style: indented two spaces; a list of values
  # always on one line, and an object holding only values and such lists
  # too when its line (with a trailing comma) fits in @line_width columns.
  @line_width 120

  defp compact(json), do: IO.iodata_to_binary([compact(json, 0, 0), "\n"])

  defp compact(%OrderedObject{values: []}, _depth, _column), do: "{}"

  defp compact(%OrderedObject{values: pairs} = object, depth, column) do
    line = depth > 0 && one_line(object)

    if line && column + String.length(line) + 1 <= @line_width do
      line
    else
      members =
        for {key, value} <- pairs do
          prefix = indent(depth + 1) <> Jason.encode!(key) <> ": "
          [prefix, compact(value, depth + 1, String.length(prefix))]
        end

      ["{\n", Enum.intersperse(members, ",\n"), "\n", indent(depth), "}"]
    end
  end

  defp compact(list, depth, _column) when is_list(list) do
    if Enum.all?(list, &scalar?/1) do
      one_line(list)
    else
      items = for item <- list, do: [indent(depth + 1), compact(item, depth + 1, 2 * depth + 2)]
      ["[\n", Enum.intersperse(items, ",\n"), "\n", indent(depth), "]"]
    end
  end

  defp compact(scalar, _depth, _column), do: Jason.encode!(scalar)

  # The one-line form of a list of values, or of an object holding only
  # values and lists of values (nil for any other object).
  defp one_line(%OrderedObject{values: pairs}) do
    if Enum.all?(pairs, fn {_key, value} -> scalar?(value) or scalar_list?(value) end) do
      "{ " <>
        Enum.map_join(pairs, ", ", fn {key, value} ->
          Jason.encode!(key) <> ": " <> one_line(value)
        end) <>
        " }"
    end
  end

  defp one_line(list) when is_list(list),
    do: "[" <> Enum.map_join(list, ", ", &Jason.encode!/1) <> "]"

  defp one_line(scalar), do: Jason.encode!(scalar)

  defp scalar?(value), do: not is_list(value) and not is_struct(value, OrderedObject)
  defp scalar_list?(value), do: is_list(value) and Enum.all?(value, &scalar?/1)

  defp indent(depth), do: String.duplicate("  ", depth)
end
