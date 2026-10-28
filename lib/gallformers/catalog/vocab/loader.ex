defmodule Gallformers.Catalog.Vocab.Loader do
  @moduledoc """
  Loads the Catalog's vocabularies (`9449` Task 8).

    * Trait values, with definitions, and term mappings come from the
      contract's `priv/import/vocab/traits.json`, the source of truth until
      cutover. The vocabulary generator (`Gallformers.Import.Vocab`, `mix
      gallformers.import.vocab`) writes the file back from the database;
      loading it and generating reproduces it (tested). After cutover the
      vocabularies change by database migration and the generator
      publishes them.
    * Generation groups and values are the provisional list held here
      (`8567` *Generation groups*): heterogony (agamic, sexual), seasonal
      (spring, summer, autumn), rust stages (aecial, telial) and the aphid
      life cycle (`8567` *Aphid life-cycle values*), whose other names load
      as term mappings of trait `"generation"`. The loader never writes
      their taxa mappings (`generation_group_taxa`): the catalog migration
      does, from `priv/catalog_migration/generation_group_taxa.csv`
      (`Gallformers.CatalogMigration.GenerationGroupTaxa`).

  Loading is idempotent: rows are matched on their natural keys (trait +
  value, trait + term, group name, generation value), new ones inserted and
  changed ones updated, and unchanged ones left untouched, so a reload with
  nothing new writes nothing (and leaves no audit records). Nothing is ever
  deleted: a value dropped from the contract may still be referenced by
  Facts, so its removal is a migration.
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

  # {group, [{value, name qualifier, definition, other names}]}. Definitions
  # are null where the contract has none yet.
  @generation_groups [
    {"heterogony",
     [
       {"agamic", "agamic", nil, nil},
       # Today's Gall names say "sexgen" for the sexual generation.
       {"sexual", "sexgen", nil, nil}
     ]},
    # Today's Gall names say "(spring generation)" (86e7, Jeff 2026-10-27).
    {"seasonal",
     [
       {"spring", "spring generation", nil, nil},
       {"summer", "summer generation", nil, nil},
       {"autumn", "autumn generation", nil, nil}
     ]},
    {"rust_stages",
     [
       {"aecial", "aecial", nil, nil},
       {"telial", "telial", nil, nil}
     ]},
    {"aphid_life_cycle",
     [
       {"fundatrix", "fundatrix",
        "Hatches from the overwintering egg on the primary host and induces the primary gall.",
        "stem mother"},
       {"apterae", "apterae",
        "The stem mother's wingless offspring on the primary host, where they leave her gall " <>
          "to induce one of their own.", "apterae fundatrigeniae"},
       {"exules", "exules", "Generations on the secondary host.", "alienicolae, virginoparae"},
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
    rows = trait_value_rows(contract)

    on_conflict =
      from(t in TraitValue,
        where: fragment("? IS DISTINCT FROM EXCLUDED.definition", t.definition),
        update: [set: [definition: fragment("EXCLUDED.definition")]]
      )

    upsert(TraitValue, rows, on_conflict, [:trait, :value])
  end

  defp upsert_term_mappings(%{"mappings" => mappings}) do
    contract_rows =
      for mapping <- mappings do
        %{
          trait: mapping["trait"],
          term: mapping["term"],
          maps_to: mapping["maps_to"] || [],
          candidates: mapping["candidates"] || [],
          rule: mapping["rule"]
        }
      end

    generation_rows =
      for {_group, values} <- @generation_groups,
          {value, _qualifier, _definition, other_names} <- values,
          other_names != nil do
        %{trait: "generation", term: other_names, maps_to: [value], candidates: [], rule: nil}
      end

    on_conflict =
      from(m in TraitTermMapping,
        where:
          fragment(
            "(?, ?, ?) IS DISTINCT FROM (EXCLUDED.maps_to, EXCLUDED.candidates, EXCLUDED.rule)",
            m.maps_to,
            m.candidates,
            m.rule
          ),
        update: [
          set: [
            maps_to: fragment("EXCLUDED.maps_to"),
            candidates: fragment("EXCLUDED.candidates"),
            rule: fragment("EXCLUDED.rule")
          ]
        ]
      )

    upsert(TraitTermMapping, contract_rows ++ generation_rows, on_conflict, [:trait, :term])
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
