defmodule Gallformers.PublicSnapshotTest do
  @moduledoc """
  The public database snapshot (`.github/workflows/db-snapshot.yml`;
  `9449` Task 17, `ede2`): every table is classified public or private in
  `priv/snapshot/tables.txt`, so a new table cannot leak without anyone
  deciding; the private ones include stored Source text, the import tables,
  the replay log and the audit schema; and Gallformers notes, public today,
  are still published (`priv/snapshot/public_snapshot.sql`).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures, only: [gallformers_source: 0, source_fixture: 2]

  alias Gallformers.Catalog
  alias Gallformers.Sources

  @list "priv/snapshot/tables.txt"
  @script "priv/snapshot/public_snapshot.sql"
  @workflow ".github/workflows/db-snapshot.yml"

  defp listed do
    @list
    |> File.read!()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.map(fn line ->
      [kind, name] = String.split(line)
      {kind, name}
    end)
  end

  defp names(kind), do: for({^kind, name} <- listed(), do: name)

  defp db_tables(schema) do
    Repo.query!(
      """
      SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = $1 AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
      ORDER BY 1
      """,
      [schema]
    ).rows
    |> List.flatten()
  end

  test "every table and schema in the database is listed public or private" do
    listed = names("public") ++ names("private")

    assert db_tables("public") -- listed == [],
           "tables not in #{@list}: classify them public or private"

    schemas =
      Repo.query!("""
      SELECT nspname FROM pg_namespace
      WHERE nspname NOT IN ('public', 'information_schema') AND nspname NOT LIKE 'pg\\_%'
      ORDER BY 1
      """).rows
      |> List.flatten()

    assert schemas -- names("private-schema") == []
  end

  test "every listed table exists, listed once; derived ones exist only in the snapshot" do
    tables = db_tables("public")
    listed = names("public") ++ names("private")

    assert listed -- tables == []
    assert listed -- Enum.uniq(listed) == []
    assert Enum.filter(names("derived"), &(&1 in tables)) == []

    assert Enum.sort(Enum.uniq(for {kind, _} <- listed(), do: kind)) ==
             ["derived", "private", "private-schema", "public"]
  end

  test "stored Source text, the import tables, the replay log and the audit trail are private" do
    private = names("private")

    for table <- ~w(source_documents document_items import_packages import_batches
                    batch_statements batch_unmapped queue_items replay_log users) do
      assert table in private, "#{table} must be private"
    end

    assert "carbonite_default" in names("private-schema")
    # Shown on gall pages today, so published.
    assert "legacy_citations" in names("public")
    assert "gall_notes" in names("derived")
  end

  test "the workflow builds the snapshot from the list and the script, and restore-tests it" do
    workflow = File.read!(@workflow)

    assert workflow =~ @list
    assert workflow =~ @script
    assert workflow =~ "private-schema"
    assert workflow =~ "--exit-on-error"
  end

  test "the snapshot publishes Gallformers notes, not other stored text" do
    gallformers = gallformers_source()
    {:ok, gall} = Catalog.create_gall(test_actor(), %{name: "Fixture snapshot gall"})
    {:ok, _} = Sources.store_note(test_actor(), gallformers, gall.id, "Look for the red rim.")

    other = source_fixture("Snapshot paper", "1990")

    {:ok, _} =
      Gallformers.Audit.transaction(test_actor(), "test.snapshot", fn ->
        %{rows: [[id]]} =
          Repo.query!(
            """
            INSERT INTO source_documents (source_id, kind, s3_key, sha256, inserted_at, updated_at)
            VALUES ($1, 'docling', 'sources/x/document.json', $2, now(), now()) RETURNING id
            """,
            [other.id, String.duplicate("a", 64)]
          )

        Repo.query!(
          """
          INSERT INTO document_items (source_document_id, ref, text, position)
          VALUES ($1, '#/texts/0', 'Copyrighted paper text.', 0)
          """,
          [id]
        )
      end)

    Repo.query!(File.read!(@script))

    assert Repo.query!("SELECT gall_id, source_id, version_date, text FROM gall_notes").rows ==
             [[gall.id, gallformers.id, nil, "Look for the red rim."]]
  end
end
