defmodule Gallformers.Catalog.Vocab.Loader do
  @moduledoc """
  Loads the Catalog's vocabularies (`9449` Task 8).

    * Trait values, with definitions, and terms (one per row, placed,
      ambiguous or fitting no category: `Gallformers.Catalog.Vocab.TraitTermMapping`)
      are seeded from the contract's `priv/import/vocab/traits.json`
      (`mappings`), each term as placed by the seed. The database owns
      them (`6611`, `d213`): a value is added through
      `Gallformers.Catalog.add_trait_value/2` and a term placed, marked or
      moved through `Gallformers.Catalog.Vocab.Terms` (recorded for replay
      by `Gallformers.Import.record_trait_value_added/2` and
      `record_term_edit/3`), and the vocabulary generator
      (`Gallformers.Import.Vocab`, `mix gallformers.import.vocab`) writes
      the file from the database, so the committed file is generated
      output that seeds a fresh database. Loading it and generating
      reproduces it (tested).
    * Generation groups and values are the provisional list held here
      (`8567` *Generation groups*): heterogony (agamic, sexual), seasonal
      (spring, summer, autumn), rust stages (aecial, telial) and the aphid
      life cycle (`8567` *Aphid life-cycle values*), whose other names load
      as terms of trait `"generation"`, placed under their values. The loader never writes
      their taxa mappings (`generation_group_taxa`): the catalog migration
      does, from `priv/catalog_migration/generation_group_taxa.csv`
      (`Gallformers.CatalogMigration.GenerationGroupTaxa`).

  Loading is idempotent: rows are matched on their natural keys (trait +
  value, trait + normalized term, group name, generation value) and new
  ones inserted. Trait values and terms are only seeded: one the database
  already holds is never overwritten, so a definition edited, or a term
  placed, in the database stays.
  Generation values are the code's list, so a changed one is updated.
  Unchanged rows are left untouched, so a reload with nothing new writes
  nothing (and leaves no audit records). Nothing is ever deleted: a value
  dropped from the file may still be referenced by Facts, so its removal is
  a migration.
  """

  import Ecto.Query, only: [from: 2]

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog.Vocab.GenerationGroup
  alias Gallformers.Catalog.Vocab.GenerationValue
  alias Gallformers.Catalog.Vocab.TraitTermMapping
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Repo

  @type counts :: %{
          trait_values: non_neg_integer(),
          trait_term_mappings: non_neg_integer(),
          generation_groups: non_neg_integer(),
          generation_values: non_neg_integer()
        }

  # {group, [{value, name qualifier, definition, other names}]}. The
  # heterogony, seasonal and rust-stage definitions are best guesses, to be
  # edited (Jeff, 2026-10-27).
  @generation_groups [
    {"heterogony",
     [
       {"agamic", "agamic",
        "The all-female generation, which reproduces without mating; its larvae induce the gall.",
        nil},
       # Today's Gall names say "sexgen" for the sexual generation.
       {"sexual", "sexgen",
        "The generation of males and females, which reproduces by mating; its larvae induce " <>
          "the gall.", nil}
     ]},
    # Today's Gall names say "(spring generation)" (86e7, Jeff 2026-10-27).
    # Season is when the gall forms and grows (the `season` Trait).
    {"seasonal",
     [
       {"spring", "spring generation", "The generation whose gall forms and grows in spring.",
        nil},
       {"summer", "summer generation", "The generation whose gall forms and grows in summer.",
        nil},
       {"autumn", "autumn generation", "The generation whose gall forms and grows in autumn.",
        nil}
     ]},
    {"rust_stages",
     [
       {"aecial", "aecial",
        "The rust stage that induces a gall bearing aecia, which release aeciospores, as " <>
          "pine-oak gall rust does on Pinus.", nil},
       {"telial", "telial",
        "The rust stage that induces a gall bearing telia, which produce teliospores, as " <>
          "cedar-apple rust does on Juniperus.", nil}
     ]},
    {"aphid_life_cycle",
     [
       {"fundatrix", "fundatrix",
        "Hatches from the overwintering egg on the primary host and induces the primary gall.",
        ["stem mother"]},
       {"apterae", "apterae",
        "The stem mother's wingless offspring on the primary host, where they leave her gall " <>
          "to induce one of their own.", ["apterae fundatrigeniae"]},
       {"exules", "exules", "Generations on the secondary host.",
        ["alienicolae", "virginoparae"]},
       {"gallicolae", "gallicolae", "Phylloxerid generations that induce leaf galls.", nil},
       {"radicicolae", "radicicolae", "Phylloxerid generations that induce root galls.", nil}
     ]}
  ]

  @doc "The generation groups' names, in order."
  @spec group_names() :: [String.t()]
  def group_names, do: for({name, _values} <- @generation_groups, do: name)

  @doc "The contract's `traits.json`."
  @spec traits_path() :: String.t()
  def traits_path, do: Application.app_dir(:gallformers, "priv/import/vocab/traits.json")

  @doc """
  Loads the vocabularies as `actor`, in one audited transaction. Returns how
  many rows of each table were inserted or updated.
  """
  @spec load(Actor.t(), String.t()) :: {:ok, counts()}
  def load(%Actor{} = actor, path \\ traits_path()) do
    contract = path |> File.read!() |> Jason.decode!()

    Audit.transaction(actor, "catalog.load_vocab", fn ->
      groups = upsert_generation_groups()

      %{
        trait_values: upsert_trait_values(contract),
        trait_term_mappings: upsert_term_mappings(contract),
        generation_groups: groups,
        generation_values: upsert_generation_values()
      }
    end)
  end

  @doc """
  The Trait values the contract's `traits.json` (at `path`) lists, as
  `load/2` stores them in `trait_values`: `%{trait, value, definition}`.
  """
  @spec contract_trait_values(String.t()) :: [
          %{trait: String.t(), value: String.t(), definition: String.t() | nil}
        ]
  def contract_trait_values(path \\ traits_path()) do
    path |> File.read!() |> Jason.decode!() |> trait_value_rows()
  end

  defp trait_value_rows(%{"traits" => traits}) do
    for {trait, %{"values" => values}} <- traits,
        trait in TraitValue.traits(),
        %{"value" => value} = entry <- values do
      %{trait: trait, value: value, definition: entry["definition"]}
    end
  end

  defp upsert_trait_values(contract) do
    upsert(TraitValue, trait_value_rows(contract), :nothing, [:trait, :value])
  end

  defp upsert_term_mappings(%{"mappings" => mappings}) do
    placed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    contract_rows =
      for mapping <- mappings do
        term_row(mapping["trait"], mapping["term"], placed_at, %{
          status: String.to_existing_atom(mapping["status"]),
          categories: mapping["categories"] || [],
          candidates: mapping["candidates"] || [],
          rule: mapping["rule"]
        })
      end

    generation_rows =
      for {_group, values} <- @generation_groups,
          {value, _qualifier, _definition, other_names} <- values,
          name <- other_names || [] do
        term_row("generation", name, placed_at, %{
          status: :placed,
          categories: [value],
          candidates: [],
          rule: nil
        })
      end

    upsert(TraitTermMapping, contract_rows ++ generation_rows, :nothing, [
      :trait,
      :normalized_term
    ])
  end

  defp term_row(trait, term, placed_at, attrs) do
    Map.merge(attrs, %{
      trait: trait,
      term: term,
      normalized_term: TraitTermMapping.normalize(term),
      placed_by: :seed,
      placed_at: placed_at
    })
  end

  defp upsert_generation_groups do
    rows = for {name, _values} <- @generation_groups, do: %{name: name}
    upsert(GenerationGroup, rows, :nothing, [:name])
  end

  defp upsert_generation_values do
    group_ids = Repo.all(from(g in GenerationGroup, select: {g.name, g.id})) |> Map.new()

    rows =
      for {group, values} <- @generation_groups,
          {{value, qualifier, definition, _other_names}, position} <- Enum.with_index(values) do
        %{
          group_id: Map.fetch!(group_ids, group),
          value: value,
          name_qualifier: qualifier,
          definition: definition,
          position: position
        }
      end

    on_conflict =
      from(v in GenerationValue,
        where:
          fragment(
            "(?, ?, ?, ?) IS DISTINCT FROM (EXCLUDED.group_id, EXCLUDED.name_qualifier, EXCLUDED.definition, EXCLUDED.position)",
            v.group_id,
            v.name_qualifier,
            v.definition,
            v.position
          ),
        update: [
          set: [
            group_id: fragment("EXCLUDED.group_id"),
            name_qualifier: fragment("EXCLUDED.name_qualifier"),
            definition: fragment("EXCLUDED.definition"),
            position: fragment("EXCLUDED.position")
          ]
        ]
      )

    upsert(GenerationValue, rows, on_conflict, [:value])
  end

  defp upsert(schema, rows, on_conflict, conflict_target) do
    {count, _} =
      Repo.insert_all(schema, rows, on_conflict: on_conflict, conflict_target: conflict_target)

    count
  end
end
