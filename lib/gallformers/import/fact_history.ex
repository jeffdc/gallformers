defmodule Gallformers.Import.FactHistory do
  @moduledoc """
  A Fact's history (matter `87a1`, "A Fact's history in the inspector"):
  each change to it, newest first, in plain words, read from the audit
  trail (Carbonite's `transactions` and `changes`, as
  `Gallformers.Audit.ChangeLog` reads them):

    * a Source's statement written or rewritten: "Weld 1959 stated it",
      "Gallformers said it isn't so" (a rewrite counts when its stance,
      date or words changed);
    * a Source's statement taken away: by a reading fix of that Source
      ("Kinsey 1920: our reading fixed, it doesn't say this"), else "Weld
      1959 no longer states it";
    * the Fact's standing: "Withdrawn", "Superseded", "No Source states it
      any more", and "Current again" after one of those.

  Who: the curator who made the change, or "import" for another Source's
  statements an import wrote; a standing change names no one (it follows
  from the statements). A statement the audit trail has no record of (the
  old site's data, loaded before the trail) comes last, undated: "In
  Gallformers' original data" for the legacy data's.

  One database transaction can hold several changes (a test is one): they
  are ordered by the change's own sequence.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Facts.Attribution
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Sources.Source

  @type entry :: %{at: NaiveDateTime.t() | nil, what: String.t(), who: String.t() | nil}

  @doc "Fact `fact_id`'s history, newest first."
  @spec for_fact(integer()) :: [entry()]
  def for_fact(fact_id) when is_integer(fact_id) do
    statements = statement_changes(fact_id)
    standings = standing_changes(fact_id)
    recorded = MapSet.new(for(s <- statements, s.op == "insert", do: s.attribution_id))

    sources =
      statements
      |> Enum.map(& &1.source_id)
      |> Enum.concat(untracked_source_ids(fact_id, recorded))
      |> names()

    {loaded, changed} = Enum.split_with(statements, &original?/1)

    audited =
      (Enum.map(changed, &statement_entry(&1, sources)) ++ standing_entries(standings))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.seq, :desc)
      |> Enum.map(&Map.delete(&1, :seq))

    audited ++
      Enum.map(Enum.filter(loaded, &(&1.op == "insert")), &original_entry(&1, sources)) ++
      untracked(fact_id, recorded, sources)
  end

  # -- statements -------------------------------------------------------------------

  defp statement_changes(fact_id) do
    sql = """
    SELECT c.id, t.inserted_at, t.meta->'actor'->>'name', t.meta->>'operation', c.op::text,
           (c.data->>'id')::bigint, (c.data->>'source_id')::bigint, c.data->>'stance',
           c.changed,
           EXISTS (
             SELECT 1 FROM carbonite_default.changes b
             JOIN import_packages p ON p.id = (b.data->>'package_id')::bigint
             WHERE b.transaction_id = c.transaction_id AND b.table_name = 'import_batches'
               AND p.key LIKE 'reading-%' AND p.source_id = (c.data->>'source_id')::bigint
           )
    FROM carbonite_default.changes c
    JOIN carbonite_default.transactions t ON t.id = c.transaction_id
    WHERE c.table_name = 'attributions' AND (c.data->>'fact_id')::bigint = $1
    ORDER BY c.id
    """

    %{rows: rows} = Repo.query!(sql, [fact_id])

    for [seq, at, who, operation, op, id, source_id, stance, changed, reading?] <- rows do
      %{
        seq: seq,
        at: at,
        who: who,
        operation: operation,
        op: op,
        attribution_id: id,
        source_id: source_id,
        stance: stance,
        changed: changed || [],
        reading?: reading?
      }
    end
  end

  # What the catalog migration loaded is the old site's data: its
  # statements are the original data, undated and naming no one, and the
  # standings it gave are where the history starts.
  defp original?(%{operation: "catalog_migration" <> _}), do: true
  defp original?(_change), do: false

  defp original_entry(s, sources) do
    source = sources[s.source_id]

    what =
      cond do
        source.legacy? -> "In Gallformers' original data"
        s.stance == "deny" -> "#{source.name} said it isn't so"
        true -> "#{source.name} stated it"
      end

    %{at: nil, what: what, who: nil}
  end

  @statement_fields ~w(stance stated_on statement_text)

  defp statement_entry(%{op: "update", changed: changed} = s, sources) do
    if Enum.any?(changed, &(&1 in @statement_fields)), do: stated(s, sources)
  end

  defp statement_entry(%{op: "insert"} = s, sources), do: stated(s, sources)

  defp statement_entry(%{op: "delete"} = s, sources) do
    name = sources[s.source_id].name

    what =
      if s.reading?,
        do: "#{name}: our reading fixed, it doesn't say this",
        else: "#{name} no longer states it"

    %{seq: s.seq, at: s.at, what: what, who: s.who}
  end

  defp stated(s, sources) do
    source = sources[s.source_id]
    verb = if s.stance == "deny", do: "said it isn't so", else: "stated it"
    %{seq: s.seq, at: s.at, what: "#{source.name} #{verb}", who: who(s, source)}
  end

  # Another Source's statements an import wrote are the import's.
  defp who(%{operation: "import.apply_batch", reading?: false}, %{own?: false}), do: "import"
  defp who(s, _source), do: s.who

  # -- standing ---------------------------------------------------------------------

  defp standing_changes(fact_id) do
    sql = """
    SELECT c.id, t.inserted_at, c.op::text, c.data->>'standing', c.changed,
           t.meta->>'operation'
    FROM carbonite_default.changes c
    JOIN carbonite_default.transactions t ON t.id = c.transaction_id
    WHERE c.table_name = 'facts' AND (c.data->>'id')::bigint = $1
    ORDER BY c.id
    """

    %{rows: rows} = Repo.query!(sql, [fact_id])

    for [seq, at, op, standing, changed, operation] <- rows,
        op == "insert" or "standing" in (changed || []),
        do: %{seq: seq, at: at, standing: standing, operation: operation}
  end

  # Each change of standing, after the first, but the catalog migration's
  # (where the history starts); current only again after the Fact stopped
  # holding.
  defp standing_entries(changes) do
    {entries, _previous} =
      Enum.map_reduce(changes, nil, fn change, previous ->
        entry =
          cond do
            is_nil(previous) or change.standing == previous or original?(change) ->
              nil

            change.standing == "current" and previous == "unsupported" ->
              nil

            true ->
              %{seq: change.seq, at: change.at, what: standing_words(change.standing), who: nil}
          end

        {entry, change.standing}
      end)

    entries
  end

  defp standing_words("current"), do: "Current again"
  defp standing_words("withdrawn"), do: "Withdrawn"
  defp standing_words("superseded"), do: "Superseded"
  defp standing_words(_standing), do: "No Source states it any more"

  # -- statements with no record ----------------------------------------------------

  defp untracked_attributions(fact_id, recorded) do
    from(a in Attribution, where: a.fact_id == ^fact_id, order_by: a.id)
    |> Repo.all()
    |> Enum.reject(&MapSet.member?(recorded, &1.id))
  end

  defp untracked_source_ids(fact_id, recorded),
    do: fact_id |> untracked_attributions(recorded) |> Enum.map(& &1.source_id)

  defp untracked(fact_id, recorded, sources) do
    for a <- untracked_attributions(fact_id, recorded) do
      source = sources[a.source_id]

      what =
        cond do
          source.legacy? -> "In Gallformers' original data"
          a.stance == :deny -> "#{source.name} said it isn't so"
          true -> "#{source.name} stated it"
        end

      %{at: nil, what: what, who: nil}
    end
  end

  # -- Sources ----------------------------------------------------------------------

  defp names(source_ids) do
    own = Sources.own_source_ids()
    legacy = Sources.get_legacy_data_source()

    from(s in Source, where: s.id in ^Enum.uniq(source_ids))
    |> Repo.all()
    |> Map.new(fn s ->
      {s.id,
       %{
         name: name(s),
         own?: s.id in own,
         legacy?: legacy != nil and s.id == legacy.id
       }}
    end)
  end

  defp name(%Source{kind: :gallformers}), do: "Gallformers"
  defp name(%Source{} = s), do: Sources.short_name(s) || s.title
end
