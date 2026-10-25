defmodule Gallformers.Audit.AuditTestMigrations do
  @moduledoc false
  # Migrations that create throwaway audited tables inside a test's sandbox
  # transaction. They run through `Ecto.Migrator`, so they exercise
  # `Gallformers.Audit.Migration.track_table/2` exactly as a real migration
  # would, and the sandbox rolls the tables back when the test ends.

  for {suffix, table} <- [
        {Rows, "audit_test_rows"},
        {RowsA, "audit_test_rows_a"},
        {RowsB, "audit_test_rows_b"}
      ] do
    defmodule Module.concat(__MODULE__, suffix) do
      @moduledoc false
      use Ecto.Migration

      @table table

      def up do
        create table(@table) do
          add :name, :text
          add :size, :integer
        end

        Gallformers.Audit.Migration.track_table(@table)
      end
    end
  end

  defmodule Pairs do
    @moduledoc false
    use Ecto.Migration

    def up do
      create table("audit_test_pairs", primary_key: false) do
        add :left_id, :integer, primary_key: true
        add :right_id, :integer, primary_key: true
        add :note, :text
      end

      Gallformers.Audit.Migration.track_table("audit_test_pairs",
        primary_key_columns: ["left_id", "right_id"]
      )
    end
  end
end

defmodule Gallformers.AuditTest do
  use Gallformers.DataCase, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Multi
  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Audit.AuditTestMigrations

  @jeff Actor.user(1, "Jeff")
  @importer Actor.system("importer")

  # Versions far above any real migration; the sandbox rolls them back.
  @rows_version 99_990_000_000_001
  @rows_a_version 99_990_000_000_002
  @rows_b_version 99_990_000_000_003
  @pairs_version 99_990_000_000_004

  defp migrate!(version, module) do
    :ok = Ecto.Migrator.up(Repo, version, module, log: false, migration_lock: false)
  end

  defp insert_row!(table, name, size) do
    {1, [%{id: id}]} = Repo.insert_all(table, [%{name: name, size: size}], returning: [:id])
    id
  end

  defp changes_for(table) do
    Repo.all(
      from c in Carbonite.Change,
        where: c.table_name == ^table,
        order_by: c.id,
        preload: :transaction
    )
  end

  defp jeff_meta(operation) do
    %{
      "actor" => %{"type" => "user", "id" => 1, "name" => "Jeff"},
      "operation" => operation
    }
  end

  describe "track_table/2" do
    setup do
      migrate!(@rows_version, AuditTestMigrations.Rows)
      :ok
    end

    test "configures the trigger to keep changed-from values and the primary key" do
      %{rows: [[pk, store_changed_from, mode]]} =
        Repo.query!("""
        SELECT primary_key_columns, store_changed_from, mode::text
        FROM carbonite_default.triggers
        WHERE table_prefix = 'public' AND table_name = 'audit_test_rows'
        """)

      assert pk == ["id"]
      assert store_changed_from == true
      assert mode == "capture"
    end

    test "records composite primary keys" do
      migrate!(@pairs_version, AuditTestMigrations.Pairs)

      {:ok, _} =
        Audit.transaction(@jeff, "test.pairs", fn ->
          Repo.query!("INSERT INTO audit_test_pairs (left_id, right_id, note) VALUES (3, 7, 'x')")
        end)

      assert [%{op: :insert, table_pk: ["3", "7"]}] = changes_for("audit_test_pairs")
    end
  end

  describe "transaction/3" do
    setup do
      migrate!(@rows_version, AuditTestMigrations.Rows)
      :ok
    end

    test "captures an insert with the actor and operation" do
      assert {:ok, id} =
               Audit.transaction(@jeff, "test.create", fn ->
                 insert_row!("audit_test_rows", "gall", 3)
               end)

      assert [change] = changes_for("audit_test_rows")
      assert change.op == :insert
      assert change.table_pk == [to_string(id)]
      assert change.data["name"] == "gall"
      assert change.transaction.meta == jeff_meta("test.create")
    end

    test "captures an update with the values it replaced" do
      {:ok, id} =
        Audit.transaction(@jeff, "test.edit", fn ->
          id = insert_row!("audit_test_rows", "gall", 3)
          Repo.query!("UPDATE audit_test_rows SET size = 5 WHERE id = $1", [id])
          id
        end)

      assert [_insert, update] = changes_for("audit_test_rows")
      assert update.op == :update
      assert update.table_pk == [to_string(id)]
      assert update.changed == ["size"]
      assert update.changed_from == %{"size" => 3}
      assert update.data["size"] == 5
    end

    test "captures a delete with the deleted row" do
      {:ok, id} =
        Audit.transaction(@jeff, "test.delete", fn ->
          id = insert_row!("audit_test_rows", "gall", 3)
          Repo.query!("DELETE FROM audit_test_rows WHERE id = $1", [id])
          id
        end)

      assert [_insert, delete] = changes_for("audit_test_rows")
      assert delete.op == :delete
      assert delete.table_pk == [to_string(id)]
      assert delete.data == %{"id" => id, "name" => "gall", "size" => 3}
    end

    test "records a system actor without an id" do
      {:ok, _} =
        Audit.transaction(@importer, "import.apply_batch", fn ->
          insert_row!("audit_test_rows", "gall", 1)
        end)

      assert [change] = changes_for("audit_test_rows")

      assert change.transaction.meta == %{
               "actor" => %{"type" => "system", "name" => "importer"},
               "operation" => "import.apply_batch"
             }
    end

    test "returns the rollback value and leaves no audit rows when rolled back" do
      assert {:error, :nope} =
               Audit.transaction(@jeff, "test.rollback", fn ->
                 insert_row!("audit_test_rows", "gall", 3)
                 Repo.rollback(:nope)
               end)

      assert changes_for("audit_test_rows") == []
      assert Repo.all(Carbonite.Query.current_transaction()) == []
    end

    test "a nested call with the same actor joins the outer transaction" do
      {:ok, _} =
        Audit.transaction(@jeff, "test.outer", fn ->
          {:ok, _} =
            Audit.transaction(@jeff, "test.inner", fn ->
              insert_row!("audit_test_rows", "gall", 3)
            end)
        end)

      assert [change] = changes_for("audit_test_rows")
      assert change.transaction.meta == jeff_meta("test.outer")
    end

    test "a second actor in the same database transaction is refused" do
      {:ok, _} =
        Audit.transaction(@jeff, "test.first", fn ->
          insert_row!("audit_test_rows", "gall", 3)
        end)

      assert_raise Audit.ConflictError, fn ->
        Audit.transaction(@importer, "test.second", fn ->
          insert_row!("audit_test_rows", "other", 4)
        end)
      end

      assert [change] = changes_for("audit_test_rows")
      assert change.data["name"] == "gall"
    end

    test "rejects an actor that is not an Actor" do
      # Built at runtime so the compiler's type check doesn't flag the call.
      not_an_actor = Map.new(id: 1)

      assert_raise FunctionClauseError, fn ->
        Audit.transaction(not_an_actor, "test.bad", fn -> :ok end)
      end
    end

    test "rejects a blank operation" do
      assert_raise ArgumentError, fn ->
        Audit.transaction(@jeff, "", fn -> :ok end)
      end
    end
  end

  describe "run_multi/3" do
    setup do
      migrate!(@rows_version, AuditTestMigrations.Rows)
      :ok
    end

    test "records the metadata before the multi's own steps" do
      result =
        Multi.new()
        |> Multi.run(:row, fn repo, _ ->
          %{rows: [[id]]} =
            repo.query!(
              "INSERT INTO audit_test_rows (name, size) VALUES ('gall', 2) RETURNING id"
            )

          {:ok, id}
        end)
        |> Audit.run_multi(@jeff, "test.multi")

      assert {:ok, %{row: id}} = result
      assert [change] = changes_for("audit_test_rows")
      assert change.table_pk == [to_string(id)]
      assert change.transaction.meta == jeff_meta("test.multi")
    end

    test "returns a failing step as Repo.transaction/1 does and keeps nothing" do
      result =
        Multi.new()
        |> Multi.run(:row, fn repo, _ ->
          repo.query!("INSERT INTO audit_test_rows (name, size) VALUES ('gall', 2)")
          {:ok, :inserted}
        end)
        |> Multi.run(:check, fn _repo, _ -> {:error, :too_small} end)
        |> Audit.run_multi(@jeff, "test.multi")

      assert {:error, :check, :too_small, %{row: :inserted}} = result
      assert changes_for("audit_test_rows") == []
    end
  end

  describe "writes without metadata" do
    setup do
      migrate!(@rows_version, AuditTestMigrations.Rows)
      :ok
    end

    test "are rejected" do
      error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(fn -> insert_row!("audit_test_rows", "gall", 3) end)
        end

      assert error.postgres.message =~ "without prior INSERT into carbonite_default.transactions"
    end

    test "cannot be smuggled in with empty metadata" do
      assert_raise Ecto.ConstraintError, ~r/transactions_meta_attribution/, fn ->
        Repo.transaction(fn ->
          Carbonite.insert_transaction(Repo, %{meta: %{}})
          insert_row!("audit_test_rows", "gall", 3)
        end)
      end
    end
  end

  describe "sandboxed processes" do
    test "never share metadata" do
      parent = self()

      a =
        Task.async(fn ->
          :ok = Sandbox.checkout(Repo)
          migrate!(@rows_a_version, AuditTestMigrations.RowsA)

          {:ok, _} =
            Audit.transaction(@jeff, "test.a", fn ->
              send(parent, {:a_ready, self()})
              assert_receive :go, 5_000
              insert_row!("audit_test_rows_a", "a", 1)
            end)

          changes = changes_for("audit_test_rows_a")
          Sandbox.checkin(Repo)
          changes
        end)

      assert_receive {:a_ready, a_pid}, 5_000

      b =
        Task.async(fn ->
          :ok = Sandbox.checkout(Repo)
          migrate!(@rows_b_version, AuditTestMigrations.RowsB)

          # A's metadata is open on another connection; it must not cover B.
          unaudited =
            try do
              Repo.transaction(fn -> insert_row!("audit_test_rows_b", "b", 0) end)
            rescue
              e in Postgrex.Error -> {:rejected, e}
            end

          {:ok, _} =
            Audit.transaction(@importer, "test.b", fn ->
              insert_row!("audit_test_rows_b", "b", 2)
            end)

          changes = changes_for("audit_test_rows_b")
          Sandbox.checkin(Repo)
          {unaudited, changes}
        end)

      {unaudited, b_changes} = Task.await(b)
      send(a_pid, :go)
      a_changes = Task.await(a)

      assert {:rejected, _} = unaudited
      assert [%{transaction: %{meta: %{"operation" => "test.a"} = a_meta}}] = a_changes
      assert a_meta["actor"]["name"] == "Jeff"
      assert [%{transaction: %{meta: %{"operation" => "test.b"} = b_meta}}] = b_changes
      assert b_meta["actor"]["name"] == "importer"
    end
  end

  describe "test helpers" do
    setup do
      migrate!(@rows_version, AuditTestMigrations.Rows)
      :ok
    end

    test "audit_test_metadata/1 attributes later writes in the test to the test actor" do
      audit_test_metadata(%{})
      insert_row!("audit_test_rows", "fixture", 1)

      assert [change] = changes_for("audit_test_rows")

      assert change.transaction.meta == %{
               "actor" => %{"type" => "system", "name" => "test"},
               "operation" => "test.setup"
             }
    end

    test "test_actor/0 can be passed to audited operations after setup" do
      audit_test_metadata(%{})

      assert {:ok, _} =
               Audit.transaction(test_actor(), "test.op", fn ->
                 insert_row!("audit_test_rows", "x", 1)
               end)
    end
  end

  describe "entity_id_seq" do
    test "hands out ids above every species id" do
      %{rows: [[next]]} = Repo.query!("SELECT nextval('entity_id_seq')")
      %{rows: [[max_species]]} = Repo.query!("SELECT COALESCE(MAX(id), 0) FROM species")

      assert next > max_species
    end
  end
end
