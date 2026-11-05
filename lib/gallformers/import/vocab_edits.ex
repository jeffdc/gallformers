defmodule Gallformers.Import.VocabEdits do
  @moduledoc """
  Changes to the Trait vocabulary (matter 6611, Task 1; d213, Task A),
  made through `Gallformers.Catalog` and recorded in the replay log, so a
  value added or a term placed during the backscan on preview is made
  again after the cutover data migration (`Gallformers.Import.Replay`).

  The database owns the vocabulary: `Gallformers.Import.Vocab` (`mix
  gallformers.import.vocab`) publishes what is changed here to the
  contract's `traits.json` and `traits.schema.json`.

    * `:trait_value_added` — key `%{"trait", "value"}`, payload
      `%{"definition"}` (`Gallformers.Catalog.add_trait_value/2`).
    * `:trait_term_edit` — key `%{"op", "trait", "term"}` (the term as
      written), one per `t:term_edit/0` (`record_term_edit/3`), payload
      what the op takes and when it was made (`"at"`, ISO 8601):
      * `"place"` — `%{"category", "placed_by", "at"}`, or `"categories"`
        (a list) in place of `"category"` for a term placed under each of
        several values its words name (`d213`)
      * `"mark_ambiguous"` — `%{"candidates", "placed_by", "at"}`
      * `"mark_unambiguous"` — as `"place"`
      * `"mark_no_fit"` — `%{"placed_by", "at"}`
      * `"move"` — `%{"category", "from", "at"}`: the attributions carrying
        the term move with it to the new category's Facts
        (`Gallformers.Catalog.move_term_attributions/5`), and so again on
        replay
      * `"spot_check"` — `%{"at"}`
    * `:term_mapping_added` — 6611's term mappings, logged before terms
      were one per row: key `%{"trait", "term"}`, payload `%{"maps_to",
      "candidates", "rule"}`. No longer written; replayed as a placed term
      (one value) or an ambiguous one (candidates).

  Replaying an entry whose change the database already holds (the
  committed `traits.json` seeds a fresh database) leaves the database's
  row as it is and logs nothing.
  """

  import Ecto.Query, only: [from: 2]

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Catalog.Vocab.TraitTermMapping
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.ReplayEntry
  alias Gallformers.Import.ReplayLog
  alias Gallformers.Repo

  @typedoc "How a term was placed (`TraitTermMapping.placed_by_values/0`)."
  @type placed_by :: TraitTermMapping.placed_by()

  @typedoc "One category, or the values a term's words name (`Gallformers.Catalog.Vocab.Terms`)."
  @type categories :: TraitTermMapping.categories()

  @typedoc "A change to a term (`Gallformers.Catalog.Vocab.Terms`): trait, term, then its arguments."
  @type term_edit ::
          {:place, String.t(), String.t(), categories(), placed_by()}
          | {:mark_ambiguous, String.t(), String.t(), [String.t()], placed_by()}
          | {:mark_unambiguous, String.t(), String.t(), categories(), placed_by()}
          | {:mark_no_fit, String.t(), String.t(), placed_by()}
          | {:move, String.t(), String.t(), String.t()}
          | {:spot_check, String.t(), String.t()}

  @doc """
  Adds a Trait value (`Gallformers.Catalog.add_trait_value/2`) and records
  it in the replay log, in one transaction.
  """
  @spec record_trait_value_added(Actor.t(), map()) ::
          {:ok, TraitValue.t()} | {:error, Ecto.Changeset.t()}
  def record_trait_value_added(%Actor{} = actor, attrs) when is_map(attrs) do
    Audit.transaction(actor, "import.record_trait_value_added", fn ->
      value = actor |> Catalog.add_trait_value(attrs) |> unwrap_or_rollback()

      ReplayLog.append!(
        :trait_value_added,
        %{"trait" => value.trait, "value" => value.value},
        %{"definition" => value.definition}
      )

      value
    end)
  end

  @doc """
  Makes `edit` to a term (`Gallformers.Catalog.place_term/6` and its
  siblings) and records it in the replay log, in one transaction. Options:
  `:at`, when it is made (default now). Returns the term; on error (as the
  Catalog function gives it) nothing is written.
  """
  @spec record_term_edit(Actor.t(), term_edit(), keyword()) ::
          {:ok, TraitTermMapping.t()} | {:error, term()}
  def record_term_edit(%Actor{} = actor, edit, opts \\ []) when is_tuple(edit) do
    at = DateTime.truncate(opts[:at] || DateTime.utc_now(), :second)

    Audit.transaction(actor, "import.record_term_edit", fn ->
      {term, payload} = actor |> run(edit, at: at) |> unwrap_or_rollback()
      [op, trait, as_written | _] = Tuple.to_list(edit)

      ReplayLog.append!(
        :trait_term_edit,
        %{"op" => Atom.to_string(op), "trait" => trait, "term" => as_written},
        Map.put(payload, "at", DateTime.to_iso8601(at))
      )

      term
    end)
  end

  # Each edit through the Catalog, with the payload its entry logs.
  defp run(actor, {:place, trait, term, categories, by}, opts) do
    with {:ok, t} <- Catalog.place_term(actor, trait, term, categories, by, opts),
         do: {:ok, {t, Map.put(logged_categories(categories), "placed_by", to_string(by))}}
  end

  defp run(actor, {:mark_ambiguous, trait, term, candidates, by}, opts) do
    with {:ok, t} <- Catalog.mark_term_ambiguous(actor, trait, term, candidates, by, opts),
         do: {:ok, {t, %{"candidates" => candidates, "placed_by" => to_string(by)}}}
  end

  defp run(actor, {:mark_unambiguous, trait, term, categories, by}, opts) do
    with {:ok, t} <- Catalog.mark_term_unambiguous(actor, trait, term, categories, by, opts),
         do: {:ok, {t, Map.put(logged_categories(categories), "placed_by", to_string(by))}}
  end

  defp run(actor, {:mark_no_fit, trait, term, by}, opts) do
    with {:ok, t} <- Catalog.mark_term_no_fit(actor, trait, term, by, opts),
         do: {:ok, {t, %{"placed_by" => to_string(by)}}}
  end

  # Moving a term carries its attributions to the new category's Facts, so
  # its replay moves them again.
  defp run(actor, {:move, trait, term, category}, opts) do
    with {:ok, %{term: t, from: from}} <- Catalog.move_term(actor, trait, term, category, opts),
         {:ok, moves} <- Catalog.move_term_attributions(actor, trait, term, from, category) do
      repoint_statements(moves)
      {:ok, {t, %{"category" => category, "from" => from}}}
    end
  end

  defp run(actor, {:spot_check, trait, term}, opts) do
    with {:ok, t} <- Catalog.record_term_spot_check(actor, trait, term, opts),
         do: {:ok, {t, %{}}}
  end

  # One category is logged as it always was; several as the set.
  defp logged_categories(categories) do
    case TraitTermMapping.categories(categories) do
      [category] -> %{"category" => category}
      several -> %{"categories" => several}
    end
  end

  @doc """
  The categories a `"place"` or `"mark_unambiguous"` entry's payload
  records: `"categories"` (several), or `"category"` (one), as given.
  """
  @spec logged_categories_of(map()) :: {:ok, categories()} | :error
  def logged_categories_of(%{"categories" => [_ | _] = categories}), do: {:ok, categories}

  def logged_categories_of(%{"category" => category}) when is_binary(category),
    do: {:ok, category}

  def logged_categories_of(_payload), do: :error

  @doc """
  Replays a `:trait_value_added`, `:trait_term_edit` or
  `:term_mapping_added` entry: makes the change again, recording it,
  unless the database holds it.
  """
  @spec replay(Actor.t(), ReplayEntry.kind(), map(), map()) :: :ok | {:error, term()}
  def replay(actor, :trait_value_added, %{"trait" => trait, "value" => value}, payload) do
    if Catalog.get_trait_value(trait, value) do
      :ok
    else
      actor
      |> record_trait_value_added(%{
        trait: trait,
        value: value,
        definition: payload["definition"]
      })
      |> ok()
    end
  end

  def replay(actor, :trait_term_edit, %{"op" => op, "trait" => trait, "term" => term}, payload) do
    with {:ok, edit} <- edit(op, trait, term, payload),
         {:ok, at} <- at(payload) do
      if done?(edit, Catalog.get_term(trait, term), at),
        do: :ok,
        else: actor |> record_term_edit(edit, at: at) |> ok()
    end
  end

  def replay(actor, :term_mapping_added, %{"trait" => trait, "term" => term}, payload) do
    edit =
      case payload do
        %{"maps_to" => [category]} ->
          {:place, trait, term, category, :curator}

        %{"candidates" => [_ | _] = candidates} ->
          {:mark_ambiguous, trait, term, candidates, :curator}

        _ ->
          nil
      end

    cond do
      Catalog.get_term(trait, term) -> :ok
      edit -> actor |> record_term_edit(edit) |> ok()
      true -> {:error, {:unreplayable_term_mapping, trait, term}}
    end
  end

  defp edit(op, trait, term, %{"placed_by" => by} = payload)
       when op in ["place", "mark_unambiguous"] do
    with {:ok, categories} <- categories_of(payload),
         {:ok, by} <- placed_by(by),
         do: {:ok, {term_op(op), trait, term, categories, by}}
  end

  defp edit("mark_ambiguous", trait, term, %{"candidates" => cs, "placed_by" => by}),
    do: with({:ok, by} <- placed_by(by), do: {:ok, {:mark_ambiguous, trait, term, cs, by}})

  defp edit("mark_no_fit", trait, term, %{"placed_by" => by}),
    do: with({:ok, by} <- placed_by(by), do: {:ok, {:mark_no_fit, trait, term, by}})

  defp edit("move", trait, term, %{"category" => c}), do: {:ok, {:move, trait, term, c}}
  defp edit("spot_check", trait, term, _payload), do: {:ok, {:spot_check, trait, term}}
  defp edit(op, _trait, _term, _payload), do: {:error, {:unknown_term_edit, op}}

  defp term_op("place"), do: :place
  defp term_op("mark_unambiguous"), do: :mark_unambiguous

  defp categories_of(payload) do
    case logged_categories_of(payload) do
      {:ok, categories} -> {:ok, categories}
      :error -> {:error, {:no_categories, payload}}
    end
  end

  defp placed_by(by) do
    case Enum.find(TraitTermMapping.placed_by_values(), &(Atom.to_string(&1) == by)) do
      nil -> {:error, {:unknown_placed_by, by}}
      atom -> {:ok, atom}
    end
  end

  defp at(%{"at" => at}) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _} -> {:error, {:invalid_at, at}}
    end
  end

  defp at(_payload), do: {:ok, nil}

  # Whether the database already holds what `edit` makes.
  defp done?(_edit, nil, _at), do: false

  defp done?({:place, _, _, categories, _}, %{status: :placed} = t, _at),
    do: TraitTermMapping.same_categories?(categories, t.categories)

  defp done?({:mark_ambiguous, _, _, candidates, _}, %{status: :ambiguous} = t, _at),
    do: Enum.sort(candidates) == Enum.sort(t.candidates)

  defp done?({:mark_unambiguous, _, _, categories, _}, %{status: :placed} = t, _at),
    do: TraitTermMapping.same_categories?(categories, t.categories)

  defp done?({:mark_no_fit, _, _, _}, %{status: :no_fit}, _at), do: true

  defp done?({:move, _, _, category}, %{status: :placed, categories: categories}, _at),
    do: categories == [category]

  defp done?({:spot_check, _, _}, %{spot_checked_at: %DateTime{} = checked}, at),
    do: at == nil or DateTime.compare(checked, at) != :lt

  defp done?(_edit, _term, _at), do: false

  # The batch statements that wrote a moved attribution now name its Fact.
  defp repoint_statements(moves) do
    for %{batch_id: batch_id, from_fact_id: from, to_fact_id: to} <- moves,
        is_integer(batch_id) do
      from(s in BatchStatement, where: s.batch_id == ^batch_id and s.fact_id == ^from)
      |> Repo.update_all(set: [fact_id: to])
    end

    :ok
  end

  defp ok({:ok, _value}), do: :ok
  defp ok({:error, reason}), do: {:error, reason}

  defp unwrap_or_rollback({:ok, value}), do: value
  defp unwrap_or_rollback({:error, reason}), do: Repo.rollback(reason)
end
