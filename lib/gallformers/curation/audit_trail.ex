defmodule Gallformers.Curation.AuditTrail do
  @moduledoc """
  What other curators changed since a tray item was added (matter `ec2c`:
  "Review recalculates … and flags anything another curator changed
  since"), read from the audit trail (Carbonite's `transactions` and
  `changes`, `Gallformers.Audit`): the newest change by another `:user`
  actor, after the item's `seen_at`, to

    * a Fact item's or note's Facts: their `facts` row, their attributions,
      their notes;
    * a Gall's editorial field: the `galls` row's columns for that field;
    * a plant's name or synonyms: its `taxon_names` rows; its range: the
      taxonomy admin's `set_host_range` and `set_wcvp` edits of it in the
      replay log (`host_range` itself is not audited).

  Plain SQL over the audit trail, as the change log reads it.
  """
  alias Gallformers.Repo

  @gall_columns %{
    completeness: ["datacomplete"],
    abundance: ["abundance_id"],
    code: ["gallformers_code"],
    name_parts: ["form_label", "descriptor", "host_qualifier_taxon_id", "name_override", "name"],
    default_source_id: ["default_source_id"]
  }

  @typedoc "Who changed it, and when (UTC)."
  @type change :: {%{id: integer(), name: String.t()}, NaiveDateTime.t()}

  @doc """
  The newest change by a user other than `user_id` after `since` to what
  `target` names, or nil: `{:facts, fact_ids}`, `{:gall_field, gall_id,
  field}`, `{:plant_names, taxon_id}` or `{:plant_range, name}` (the
  plant's accepted name, as the replay log's taxon references name it).
  """
  @spec changed_since(term(), integer(), DateTime.t()) :: change() | nil
  def changed_since({:facts, []}, _user_id, _since), do: nil

  def changed_since({:facts, fact_ids}, user_id, since) do
    newest(
      """
      (c.table_name = 'facts' AND (c.data->>'id')::bigint = ANY($3))
      OR (c.table_name IN ('attributions', 'fact_notes') AND (c.data->>'fact_id')::bigint = ANY($3))
      """,
      [fact_ids],
      user_id,
      since
    )
  end

  def changed_since({:gall_field, gall_id, field}, user_id, since) do
    newest(
      """
      c.table_name = 'galls' AND (c.data->>'id')::bigint = $3
        AND (c.op <> 'update' OR c.changed && $4::varchar[])
      """,
      [gall_id, Map.fetch!(@gall_columns, field)],
      user_id,
      since
    )
  end

  def changed_since({:plant_names, taxon_id}, user_id, since) do
    newest(
      "c.table_name = 'taxon_names' AND (c.data->>'taxon_id')::bigint = $3",
      [taxon_id],
      user_id,
      since
    )
  end

  def changed_since({:plant_range, name}, user_id, since) do
    newest(
      """
      c.table_name = 'replay_log' AND c.op = 'insert'
        AND c.data->'key'->>'op' IN ('set_host_range', 'set_wcvp')
        AND c.data->'key'->'taxon'->>'name' = $3
      """,
      [name],
      user_id,
      since
    )
  end

  defp newest(where, params, user_id, since) do
    sql = """
    SELECT (t.meta->'actor'->>'id')::bigint, t.meta->'actor'->>'name', t.inserted_at
    FROM carbonite_default.changes c
    JOIN carbonite_default.transactions t
      ON t.id = c.transaction_id AND t.xact_id = c.transaction_xact_id
    WHERE t.meta->'actor'->>'type' = 'user'
      AND (t.meta->'actor'->>'id')::bigint <> $1
      AND t.inserted_at > $2
      AND (#{where})
    ORDER BY t.inserted_at DESC
    LIMIT 1
    """

    since = since |> DateTime.to_naive() |> NaiveDateTime.truncate(:microsecond)

    case Repo.query!(sql, [user_id, since | params]) do
      %{rows: [[id, name, at]]} -> {%{id: id, name: name}, at}
      %{rows: []} -> nil
    end
  end
end
