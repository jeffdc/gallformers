defmodule Gallformers.Catalog.Vocab.Terms do
  @moduledoc """
  The term table's changes (matter `d213`): a Source's term for a Trait
  (`Gallformers.Catalog.Vocab.TraitTermMapping`) is looked up by its
  normalized key, placed for every Source under one category or under
  each value its words name ("green-yellow" → green and yellow), marked
  ambiguous (with candidates) or unambiguous, marked as fitting no
  category, moved to another category, or spot-checked. Reached through
  `Gallformers.Catalog`; recorded for replay by
  `Gallformers.Import.record_term_edit/3`.

  Each change is audited as the given actor and serialized per term (a
  transaction-scoped advisory lock), so two placements of one new term
  make one row. Options: `:at`, the time the change is made (default now):
  `placed_at`, or `spot_checked_at`; a replayed change passes the logged
  time.

  Errors: `{:error, changeset}` for an invalid trait, term, category or
  way of placing; `{:error, {:placed, term}}` when the term is placed
  under other categories; `{:error, {:ambiguous,
  term}}` when it is ambiguous (decided per use, or marked unambiguous by
  a superadmin); `{:error, {:not_ambiguous, term}}`, `{:error,
  {:not_placed, term}}`; `{:error, :not_found}`.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Changeset
  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog.Vocab.GenerationValue
  alias Gallformers.Catalog.Vocab.TraitTermMapping
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Repo

  @type error ::
          Changeset.t()
          | {:placed, TraitTermMapping.t()}
          | {:ambiguous, TraitTermMapping.t()}
          | {:not_ambiguous, TraitTermMapping.t()}
          | {:not_placed, TraitTermMapping.t()}
          | :not_found

  @type result :: {:ok, TraitTermMapping.t()} | {:error, error()}

  @type categories :: TraitTermMapping.categories()

  @typedoc "What moving a term changes: the term, the categories it left, the one it moved to."
  @type move :: %{term: TraitTermMapping.t(), from: [String.t()], to: String.t()}

  @doc "A term by its trait and term (compared normalized), or nil."
  @spec get(String.t(), String.t()) :: TraitTermMapping.t() | nil
  def get(trait, term) when is_binary(trait) and is_binary(term),
    do:
      Repo.get_by(TraitTermMapping,
        trait: trait,
        normalized_term: TraitTermMapping.normalize(term)
      )

  @doc "Every term, in the order added (the contract's order)."
  @spec list() :: [TraitTermMapping.t()]
  def list, do: Repo.all(from(m in TraitTermMapping, order_by: m.id))

  @doc """
  The other values of `trait` that are readings of one ambiguous term with
  any of `values` (its candidates: "swelling" is abrupt swelling, tapered
  swelling or stem club), each once.
  """
  @spec readings_with(String.t(), [String.t()]) :: [String.t()]
  def readings_with(_trait, []), do: []

  def readings_with(trait, values) do
    from(m in TraitTermMapping,
      where:
        m.trait == ^trait and m.status == :ambiguous and fragment("? && ?", m.candidates, ^values),
      select: m.candidates
    )
    |> Repo.all()
    |> List.flatten()
    |> Enum.uniq()
    |> Kernel.--(values)
  end

  @doc """
  Places `term` for every Source under `categories`: one value, or each
  value its words name (a list), `placed_by` one of
  `TraitTermMapping.placed_by_values/0`. A new term, or one that fit no
  category, is placed; a term already under the same categories (in any
  order) is left as it is (nothing written). Refuses a term placed under
  other categories and an ambiguous term.
  """
  @spec place(Actor.t(), String.t(), String.t(), categories(), atom(), keyword()) :: result()
  def place(%Actor{} = actor, trait, term, categories, placed_by, opts \\ []) do
    change(actor, "catalog.place_term", trait, term, fn
      nil ->
        insert_term(trait, term, placed(categories, placed_by, opts))

      %TraitTermMapping{status: :placed} = existing ->
        if TraitTermMapping.same_categories?(existing.categories, categories),
          do: {:ok, existing},
          else: {:error, {:placed, existing}}

      %TraitTermMapping{status: :ambiguous} = existing ->
        {:error, {:ambiguous, existing}}

      %TraitTermMapping{status: :no_fit} = existing ->
        update_term(existing, placed(categories, placed_by, opts))
    end)
  end

  @doc """
  Marks `term` ambiguous between `candidates` (values of its Trait): it is
  never mapped automatically again, each use being decided on its own. A
  new term is added; a placed term loses its category (its Facts stand:
  listing them is the caller's).
  """
  @spec mark_ambiguous(Actor.t(), String.t(), String.t(), [String.t()], atom(), keyword()) ::
          result()
  def mark_ambiguous(%Actor{} = actor, trait, term, candidates, placed_by, opts \\ []) do
    attrs = %{
      status: :ambiguous,
      categories: [],
      candidates: candidates,
      placed_by: placed_by,
      placed_at: at(opts)
    }

    change(actor, "catalog.mark_term_ambiguous", trait, term, fn
      nil -> insert_term(trait, term, attrs)
      existing -> update_term(existing, attrs)
    end)
  end

  @doc """
  Places an ambiguous `term` under `categories` (one value, or the values
  its words name): it then maps automatically.
  """
  @spec mark_unambiguous(Actor.t(), String.t(), String.t(), categories(), atom(), keyword()) ::
          result()
  def mark_unambiguous(%Actor{} = actor, trait, term, categories, placed_by, opts \\ []) do
    change(actor, "catalog.mark_term_unambiguous", trait, term, fn
      nil ->
        {:error, :not_found}

      %TraitTermMapping{status: :ambiguous} = t ->
        update_term(t, placed(categories, placed_by, opts))

      existing ->
        {:error, {:not_ambiguous, existing}}
    end)
  end

  @doc """
  Marks `term` as fitting no category: it stays text on the Gall. A new or
  ambiguous term; refuses a placed one (move it instead).
  """
  @spec mark_no_fit(Actor.t(), String.t(), String.t(), atom(), keyword()) :: result()
  def mark_no_fit(%Actor{} = actor, trait, term, placed_by, opts \\ []) do
    attrs = %{
      status: :no_fit,
      categories: [],
      candidates: [],
      placed_by: placed_by,
      placed_at: at(opts)
    }

    change(actor, "catalog.mark_term_no_fit", trait, term, fn
      nil -> insert_term(trait, term, attrs)
      %TraitTermMapping{status: :no_fit} = existing -> {:ok, existing}
      %TraitTermMapping{status: :placed} = existing -> {:error, {:placed, existing}}
      existing -> update_term(existing, attrs)
    end)
  end

  @doc """
  Moves a placed `term` to `category` (a superadmin's change). Returns what
  must move with it: the categories it left (`from`) and the one it moved
  to (`to`). The term changes here; the caller moves the attributions that
  carry the term (`Gallformers.Facts.Attribution.term`) from the Facts on
  the `from` categories to the Fact on `to`. A term already under
  `category` alone is left as it is.
  """
  @spec move(Actor.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, move()} | {:error, error()}
  def move(%Actor{} = actor, trait, term, category, opts \\ []) do
    change(actor, "catalog.move_term", trait, term, fn
      nil ->
        {:error, :not_found}

      %TraitTermMapping{status: :placed, categories: [^category]} = existing ->
        {:ok, %{term: existing, from: [category], to: category}}

      %TraitTermMapping{status: :placed} = existing ->
        with {:ok, moved} <- update_term(existing, placed(category, :superadmin, opts)) do
          {:ok, %{term: moved, from: existing.categories, to: category}}
        end

      existing ->
        {:error, {:not_placed, existing}}
    end)
  end

  @doc "Records that `term`'s placement was spot-checked (at `:at`, default now)."
  @spec record_spot_check(Actor.t(), String.t(), String.t(), keyword()) :: result()
  def record_spot_check(%Actor{} = actor, trait, term, opts \\ []) do
    change(actor, "catalog.record_term_spot_check", trait, term, fn
      nil -> {:error, :not_found}
      existing -> existing |> TraitTermMapping.spot_check_changeset(at(opts)) |> Repo.update()
    end)
  end

  # -- helpers -------------------------------------------------------------------

  defp placed(categories, placed_by, opts) do
    %{
      status: :placed,
      categories: TraitTermMapping.categories(categories),
      candidates: [],
      placed_by: placed_by,
      placed_at: at(opts)
    }
  end

  defp at(opts) do
    case Keyword.get(opts, :at) do
      nil -> DateTime.utc_now() |> DateTime.truncate(:second)
      %DateTime{} = at -> DateTime.truncate(at, :second)
    end
  end

  # Runs `fun` on the term's row (nil when new), under the term's lock, in
  # one audited transaction; rolls back its error.
  defp change(actor, operation, trait, term, fun) do
    Audit.transaction(actor, operation, fn ->
      if is_binary(trait) and is_binary(term) do
        lock(trait, term)
        trait |> get(term) |> fun.() |> ok_or_rollback()
      else
        Repo.rollback(invalid(trait, term))
      end
    end)
  end

  defp insert_term(trait, term, attrs) do
    %TraitTermMapping{}
    |> TraitTermMapping.changeset(Map.merge(attrs, %{trait: trait, term: term}), values(trait))
    |> Repo.insert()
  end

  defp update_term(existing, attrs) do
    existing
    |> TraitTermMapping.changeset(attrs, values(existing.trait))
    |> Repo.update()
  end

  defp invalid(trait, term) do
    %TraitTermMapping{}
    |> TraitTermMapping.changeset(%{trait: trait, term: term}, [])
    |> Map.put(:action, :insert)
  end

  # The values a term of `trait` is placed under.
  defp values("generation"), do: Repo.all(from(v in GenerationValue, select: v.value))

  defp values(trait) when is_binary(trait),
    do: Repo.all(from(t in TraitValue, where: t.trait == ^trait, select: t.value))

  defp lock(trait, term) do
    Repo.query!("SELECT pg_advisory_xact_lock(9449, hashtext($1))", [
      "trait_term:#{trait}:#{TraitTermMapping.normalize(term)}"
    ])
  end

  defp ok_or_rollback({:ok, value}), do: value
  defp ok_or_rollback({:error, reason}), do: Repo.rollback(reason)
end
