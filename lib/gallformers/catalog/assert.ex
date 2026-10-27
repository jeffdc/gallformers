defmodule Gallformers.Catalog.Assert do
  @moduledoc """
  Asserting a gall Fact (`9449` §4): find the Fact by its kind's natural key
  (setting any property outside the key the assert gives, where the kind
  has one: `c:update_existing/2`) or create it with its details, then record a Source's stance on it with
  `Gallformers.Facts.attribute/2` — all in one transaction, as one actor.
  On error nothing is written (no Fact is left behind) and the changeset
  says why.

  Each kind is a details schema in `Gallformers.Catalog.Facts` implementing
  this behaviour (the same shape as `Gallformers.Taxa.ActFacts` for
  taxonomic acts). Concurrent asserts of one natural key are serialized by
  a transaction-scoped advisory lock, so they make one Fact.
  """

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

  @doc "The Fact kind (`facts.kind`), prefixed `gall_`."
  @callback kind() :: String.t()

  @doc "Casts and validates the details that make up the natural key."
  @callback changeset(detail(), map()) :: Changeset.t()

  @doc """
  Checks that need the database (e.g. a Host is a plant), or resolves
  references (e.g. a Trait value by name). Runs inside the transaction.
  """
  @callback prepare(Changeset.t()) :: Changeset.t()

  @doc "The slot the Fact competes in, or nil."
  @callback slot(detail()) :: String.t() | nil

  @doc "The natural key, as a term (for locking)."
  @callback natural_key(detail()) :: term()

  @doc "A query for the stored details with the same natural key."
  @callback existing_query(detail()) :: Ecto.Query.t()

  @doc """
  The change to make to the stored details found by the natural key, for
  properties outside the key that the assert sets (e.g. an alias's kind),
  or nil to leave them. `asserted` is the assert's validated changeset.
  """
  @callback update_existing(existing :: detail(), asserted :: Changeset.t()) ::
              Changeset.t() | nil

  @optional_callbacks prepare: 1, update_existing: 2

  @doc """
  Asserts a Fact of kind `module`: finds or creates it by the natural key in
  `key_attrs`, then attributes it with `attribution_attrs` (as
  `Gallformers.Facts.attribute/2` takes them, without `:fact_id`).
  """
  @spec assert(module(), Actor.t(), map(), map()) :: {:ok, result()} | {:error, Changeset.t()}
  def assert(module, %Actor{} = actor, key_attrs, attribution_attrs)
      when is_map(key_attrs) and is_map(attribution_attrs) do
    Audit.transaction(actor, "catalog.assert_#{module.kind()}", fn ->
      changeset = module.changeset(struct(module), key_attrs)

      changeset =
        if changeset.valid? and function_exported?(module, :prepare, 1),
          do: module.prepare(changeset),
          else: changeset

      key = changeset |> Changeset.apply_action(:insert) |> ok_or_rollback()

      lock(module.kind(), module.natural_key(key))

      detail =
        case Repo.one(module.existing_query(key)) do
          nil -> create(module, actor, changeset, key)
          existing -> update_existing(module, existing, changeset)
        end

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
  Finds the details of the Fact of kind `module` with the natural key in
  `key_attrs`, without writing anything: `{:ok, detail}`, `{:ok, nil}` when
  there is none yet, or `{:error, changeset}` when the key is invalid (e.g.
  a Host that is not a plant).
  """
  @spec find(module(), map()) :: {:ok, detail() | nil} | {:error, Changeset.t()}
  def find(module, key_attrs) when is_map(key_attrs) do
    changeset = module.changeset(struct(module), key_attrs)

    changeset =
      if changeset.valid? and function_exported?(module, :prepare, 1),
        do: module.prepare(changeset),
        else: changeset

    with {:ok, key} <- Changeset.apply_action(changeset, :insert) do
      {:ok, Repo.one(module.existing_query(key))}
    end
  end

  defp create(module, actor, changeset, key) do
    fact =
      actor
      |> Facts.create_fact(%{kind: module.kind(), slot: module.slot(key)})
      |> ok_or_rollback()

    changeset
    |> Changeset.put_change(:fact_id, fact.id)
    |> Repo.insert()
    |> ok_or_rollback()
  end

  defp update_existing(module, existing, asserted) do
    with true <- function_exported?(module, :update_existing, 2),
         %Changeset{} = update <- module.update_existing(existing, asserted) do
      update |> Repo.update() |> ok_or_rollback()
    else
      _unchanged -> existing
    end
  end

  defp lock(kind, natural_key) do
    Repo.query!("SELECT pg_advisory_xact_lock(9449, hashtext($1))", [
      "#{kind}:#{inspect(natural_key)}"
    ])
  end

  defp ok_or_rollback({:ok, value}), do: value
  defp ok_or_rollback({:error, changeset}), do: Repo.rollback(changeset)
end
