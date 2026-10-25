defmodule Gallformers.Import.Diff do
  @moduledoc """
  Writing a batch's statements as attributions by diffing them against the
  Source's existing attributions of the batch's type (`9449` §5, Task 13).

  For each statement (an act or a Fact, already turned into a natural key
  and attribution attrs):

    * the Fact is found by its natural key; a statement whose Fact does not
      exist yet creates it and its attribution (**new**);
    * an existing Fact with this Source's attribution unchanged (apart from
      the batch that last wrote it) is **left untouched**: no write, no
      audit rows, its `batch_id` still the batch that wrote it;
    * a changed attribution is **updated** (audit keeps what it replaced);
    * for the Gallformers Source, a statement **older** than the one its
      attribution holds does not replace it (each Gallformers statement is
      dated; the newest stands).

  After every statement, `remove_unstated/2` removes, for `mode: replace`,
  the Source's attributions of this batch type that the batch no longer
  states: a Fact left with no support becomes unsupported. `mode: add`
  never removes.

  Each statement's **delta** is what it says about what Gallformers held:
  `:new` (the Fact did not exist), `:denies_or_replaces` (it denies an
  existing Fact, or confirms one whose slot holds another current Fact),
  or `:confirms_existing`.
  """

  alias Gallformers.Audit.Actor
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Facts.Standing.Conflict
  alias Gallformers.Sources.PartialDate
  alias Gallformers.Sources.Source

  @typedoc """
  What the diff needs: the actor, the Source, the Source's existing
  attributions of this batch type by Fact ID, and how to find and assert a
  Fact of a kind (`Catalog` or `Taxa`).
  """
  @type context :: %{
          actor: Actor.t(),
          source: Source.t(),
          existing: %{integer() => Attribution.t()},
          find: (atom(), map() -> {:ok, integer() | nil} | {:error, Ecto.Changeset.t()}),
          assert: (atom(), Actor.t(), map(), map() -> {:ok, map()} | {:error, term()})
        }

  @typedoc "A statement to write: its kind, natural key and attribution attrs."
  @type write :: %{kind: atom(), key: map(), attribution: map()}

  @typedoc "What writing a statement did."
  @type outcome :: %{
          fact_id: integer() | nil,
          resolution: :new | :resolved | :unresolved,
          delta: :new | :confirms_existing | :denies_or_replaces | nil,
          flags: [String.t()],
          detail: map(),
          conflicts: [Conflict.t()]
        }

  @doc """
  Writes one statement. An invalid key (e.g. an unknown Trait value) is not
  written and comes back `:unresolved` with the reason; an attribution that
  cannot be written (a quote not in its item) returns `{:error, reason}`, so
  the caller rolls the batch back.
  """
  @spec write(context(), write()) :: {:ok, outcome()} | {:error, term()}
  def write(ctx, %{kind: kind, key: key, attribution: attrs}) do
    attrs = Map.put(attrs, :source_id, ctx.source.id)

    case ctx.find.(kind, key) do
      {:error, changeset} ->
        {:ok, unresolved("invalid: #{errors(changeset)}")}

      {:ok, nil} ->
        with {:ok, result} <- ctx.assert.(kind, ctx.actor, key, attrs) do
          {:ok, outcome(result.fact.id, :new, :new, result.conflicts)}
        end

      {:ok, fact_id} ->
        write_existing(ctx, kind, key, attrs, fact_id)
    end
  end

  defp write_existing(ctx, kind, key, attrs, fact_id) do
    delta = delta(fact_id, attrs[:stance])
    existing = Map.get(ctx.existing, fact_id)

    cond do
      existing && older_gallformers_statement?(ctx.source, existing, attrs) ->
        {:ok, %{outcome(fact_id, :resolved, delta, []) | flags: ["older_than_stored_statement"]}}

      existing && Facts.attribution_unchanged?(existing, attrs) ->
        {:ok, outcome(fact_id, :resolved, delta, [])}

      true ->
        with {:ok, result} <- ctx.assert.(kind, ctx.actor, key, attrs) do
          {:ok, outcome(fact_id, :resolved, delta, result.conflicts)}
        end
    end
  end

  defp delta(fact_id, stance) do
    fact = Facts.get_fact!(fact_id)

    cond do
      to_string(stance) == "deny" -> :denies_or_replaces
      Facts.other_current_in_slot?(fact) -> :denies_or_replaces
      true -> :confirms_existing
    end
  end

  # Each Gallformers statement is dated: an older one never replaces a newer.
  defp older_gallformers_statement?(%Source{kind: :gallformers}, existing, attrs) do
    with %Date{} = stored <- existing.stated_on,
         stated when is_binary(stated) <- attrs[:stated],
         {:ok, {date, _precision}} <- PartialDate.parse(stated) do
      Date.compare(date, stored) == :lt
    else
      _ -> false
    end
  end

  defp older_gallformers_statement?(_source, _existing, _attrs), do: false

  @doc "A statement that could not be written, with the reason."
  @spec unresolved(String.t()) :: outcome()
  def unresolved(reason) do
    %{
      fact_id: nil,
      resolution: :unresolved,
      delta: nil,
      flags: [],
      detail: %{"skipped" => reason},
      conflicts: []
    }
  end

  defp outcome(fact_id, resolution, delta, conflicts) do
    %{
      fact_id: fact_id,
      resolution: resolution,
      delta: delta,
      flags: [],
      detail: %{},
      conflicts: conflicts
    }
  end

  @doc """
  For `mode: replace`, removes the Source's existing attributions (of this
  batch type) on Facts not in `stated_fact_ids`; returns the conflicts the
  recomputed standings report. `mode: add` removes nothing.
  """
  @spec remove_unstated(context(), :replace | :add, [integer()]) ::
          {:ok, [Conflict.t()]} | {:error, term()}
  def remove_unstated(_ctx, :add, _stated_fact_ids), do: {:ok, []}

  def remove_unstated(ctx, :replace, stated_fact_ids) do
    stated = Map.new(stated_fact_ids, &{&1, true})

    ctx.existing
    |> Map.keys()
    |> Enum.reject(&Map.has_key?(stated, &1))
    |> Enum.sort()
    |> Enum.reduce_while({:ok, []}, fn fact_id, {:ok, acc} ->
      case Facts.remove_attribution(ctx.actor, fact_id, ctx.source.id) do
        {:ok, conflicts} -> {:cont, {:ok, acc ++ conflicts}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r/%{(\w+)}/, message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end
end
