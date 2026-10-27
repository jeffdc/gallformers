defmodule Gallformers.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test.

  If the test case interacts with the database, async tests use isolated
  sandbox connections while sync tests share a single connection.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Gallformers.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Gallformers.DataCase
    end
  end

  setup tags do
    Gallformers.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Gallformers.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    # SiteSettings is global state. Sync tests may change it (e.g. read_only),
    # so each one starts and finishes with an empty cache.
    unless tags[:async] do
      reset_site_settings()
      on_exit(&reset_site_settings/0)
    end

    :ok
  end

  @doc """
  Clears the global SiteSettings cache.

  `SiteSettings.set/2` broadcasts each change, and the SiteSettings GenServer
  writes it into the cache asynchronously. `:sys.get_state/1` waits until the
  GenServer has handled every broadcast already in its mailbox, so a late
  broadcast cannot write a value back after the reset.
  """
  def reset_site_settings do
    :sys.get_state(Gallformers.SiteSettings)
    :persistent_term.put({Gallformers.SiteSettings, :cache}, %{})
  end

  @doc """
  The actor tests pass to audited operations: a system actor named `"test"`.

  The audit trail records one actor per database transaction, and a test runs
  in one sandbox transaction, so a test uses this actor for every audited
  call (fixtures included). See `Gallformers.Audit`.
  """
  def test_actor, do: Gallformers.Audit.Actor.system("test")

  @doc """
  Records explicit audit metadata (`test_actor/0`, operation `"test.setup"`)
  for the test's sandbox transaction, so fixtures can write to audited tables
  directly. Use it as `setup :audit_test_metadata`.

  Audited calls later in the test must also use `test_actor/0`; another actor
  raises `Gallformers.Audit.ConflictError`.
  """
  def audit_test_metadata(_context) do
    {:ok, :ok} = Gallformers.Audit.transaction(test_actor(), "test.setup", fn -> :ok end)
    :ok
  end

  @doc """
  The audit trail's changes (`Carbonite.Change`) made by the running test, as
  a query to narrow further: those of its sandbox transaction. The test
  database already holds the catalog migration's changes (`make test-db`
  converts the seeds with it), so a test asserting on the changes it made
  reads only its own.
  """
  def test_audit_changes do
    import Ecto.Query, only: [from: 2]

    from(c in Carbonite.Change, where: c.transaction_xact_id == fragment("pg_current_xact_id()"))
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
