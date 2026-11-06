defmodule Gallformers.AuditFixtures do
  @moduledoc """
  Curators' changes in the audit trail, for the change log
  (`Gallformers.Audit.ChangeLog`) and the pages that show it.

  A test runs in one database transaction, so the audit trail would record
  one change for all of it. These write a curator's transaction and its
  changes into the trail directly, as Carbonite would have.
  """
  alias Gallformers.Import.Package
  alias Gallformers.Repo

  @doc """
  A transaction by curator `who` (or `:system`), `minutes_ago`, recording
  `changes`: `{table, op, data}` triples (`op` "insert", "update" or
  "delete"). Returns the transaction's id.
  """
  def curator_change(who, operation, minutes_ago, changes) do
    # Carbonite's ids rise with time, and the change log orders by them, so
    # a fixture's ids must too.
    id = System.unique_integer([:positive, :monotonic]) + 1_000_000_000_000

    actor =
      if who == :system,
        do: %{type: "system", name: "import_submit"},
        else: %{type: "user", id: 1, name: who}

    at =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-minutes_ago * 60)
      |> NaiveDateTime.truncate(:second)

    Repo.query!(
      "INSERT INTO carbonite_default.transactions (id, xact_id, meta, inserted_at) VALUES ($1, $2::xid8, $3, $4)",
      [id, id, %{actor: actor, operation: operation}, at]
    )

    for {table, op, data} <- changes do
      Repo.query!(
        """
        INSERT INTO carbonite_default.changes
          (transaction_id, transaction_xact_id, op, table_prefix, table_name, data, changed)
        VALUES ($1, $2::xid8, $3::text::carbonite_default.change_op, 'public', $4, $5, '{}')
        """,
        [id, id, op, table, data]
      )
    end

    id
  end

  @doc "An import package of `source`, for a change to name its Source through."
  def package_for(source) do
    Repo.insert!(%Package{
      key: "pkg-#{System.unique_integer([:positive])}",
      s3_prefix: "import/x/",
      source_id: source.id,
      submitter_name: "Producer"
    })
  end
end
