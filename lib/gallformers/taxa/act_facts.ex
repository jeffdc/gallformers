defmodule Gallformers.Taxa.ActFacts do
  @moduledoc """
  Taxonomic-act Facts (`9449` §3): the contract's act kinds
  (`priv/import/schema/taxonomy.schema.json`) recorded as Facts
  (`Gallformers.Facts`) with typed details, one table per kind, each unique
  on the kind's natural key:

  | Kind | Details | Natural key | Slot |
  |---|---|---|---|
  | placement | `PlacementFact` | taxon + parent | `taxon:<id>:placement` |
  | name | `NameFact` | taxon + normalized name + rank | `taxon:<id>:name` |
  | synonymy | `SynonymyFact` | normalized synonym name + accepted taxon | none |
  | split | `SplitFact` | taxon + set of daughters | none |
  | common name | `CommonNameFact` | taxon + common name (any case) | none |

  Asserting an act finds the Fact by its natural key or creates it (with its
  details), then records the Source's stance with `Gallformers.Facts.attribute/2`,
  all in one transaction as one actor. The act's per-statement words go on
  the attribution: `status_as_written` for any act, `authorship_as_written`
  for a name.

  In phase 1 these Facts are recorded only: they never change the editorial
  tree (`taxa`, `taxon_names`, `taxon_common_names`). Phase 2 lets them
  drive it.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Changeset
  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Facts.Fact
  alias Gallformers.Facts.Standing.Conflict
  alias Gallformers.Repo

  @type detail :: struct()

  @type result :: %{
          fact: Fact.t(),
          detail: detail(),
          attribution: Attribution.t(),
          conflicts: [Conflict.t()]
        }

  @doc "The Fact kind (`facts.kind`)."
  @callback kind() :: String.t()

  @doc "Casts and validates the details that make up the natural key."
  @callback changeset(detail(), map()) :: Changeset.t()

  @doc "The slot the Fact competes in, or nil."
  @callback slot(detail()) :: String.t() | nil

  @doc "The natural key, as a term (for locking)."
  @callback natural_key(detail()) :: term()

  @doc "A query for the stored details with the same natural key."
  @callback existing_query(detail()) :: Ecto.Query.t()

  @doc "Writes rows that belong with newly inserted details."
  @callback after_insert(detail()) :: :ok

  @optional_callbacks after_insert: 1

  @doc """
  Asserts an act of kind `module` (a details schema implementing this
  behaviour): finds or creates its Fact by the natural key in `key_attrs`,
  then attributes it with `attribution_attrs` (as `Gallformers.Facts.attribute/2`
  takes them, without `:fact_id`).

  On error nothing is written — no Fact is left behind — and the changeset
  says why.
  """
  @spec assert(module(), Actor.t(), map(), map()) :: {:ok, result()} | {:error, Changeset.t()}
  def assert(module, %Actor{} = actor, key_attrs, attribution_attrs)
      when is_map(key_attrs) and is_map(attribution_attrs) do
    Audit.transaction(actor, "taxa.assert_#{module.kind()}", fn ->
      changeset = module.changeset(struct(module), key_attrs)
      key = changeset |> Changeset.apply_action(:insert) |> ok_or_rollback()

      lock(module.kind(), module.natural_key(key))
      detail = Repo.one(module.existing_query(key)) || create(module, actor, changeset, key)

      %{attribution: attribution, conflicts: conflicts} =
        actor
        |> Facts.attribute(Map.put(attribution_attrs, :fact_id, detail.fact_id))
        |> ok_or_rollback()

      %{
        fact: Facts.get_fact!(detail.fact_id),
        detail: detail,
        attribution: attribution,
        conflicts: conflicts
      }
    end)
  end

  @doc """
  Finds the details of the act Fact of kind `module` with the natural key in
  `key_attrs`, without writing anything: `{:ok, detail}`, `{:ok, nil}` when
  there is none yet, or `{:error, changeset}` when the key is invalid.
  """
  @spec find(module(), map()) :: {:ok, detail() | nil} | {:error, Changeset.t()}
  def find(module, key_attrs) when is_map(key_attrs) do
    with {:ok, key} <-
           module |> struct() |> module.changeset(key_attrs) |> Changeset.apply_action(:insert) do
      {:ok, Repo.one(module.existing_query(key))}
    end
  end

  @doc "A taxon's placement Facts, with their Facts, oldest first."
  @spec list_placement_facts(integer()) :: [__MODULE__.PlacementFact.t()]
  def list_placement_facts(taxon_id) do
    from(p in __MODULE__.PlacementFact,
      where: p.taxon_id == ^taxon_id,
      order_by: p.fact_id,
      preload: :fact
    )
    |> Repo.all()
  end

  defp create(module, actor, changeset, key) do
    fact =
      actor
      |> Facts.create_fact(%{kind: module.kind(), slot: module.slot(key)})
      |> ok_or_rollback()

    detail =
      changeset
      |> Changeset.put_change(:fact_id, fact.id)
      |> Repo.insert()
      |> ok_or_rollback()

    if function_exported?(module, :after_insert, 1), do: :ok = module.after_insert(detail)
    detail
  end

  # Serializes find-or-create on one natural key, so two concurrent asserts
  # of the same act make one Fact.
  defp lock(kind, natural_key) do
    Repo.query!("SELECT pg_advisory_xact_lock(9449, hashtext($1))", [
      "#{kind}:#{inspect(natural_key)}"
    ])
  end

  defp ok_or_rollback({:ok, value}), do: value
  defp ok_or_rollback({:error, changeset}), do: Repo.rollback(changeset)
end
