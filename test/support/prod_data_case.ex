defmodule Gallformers.ProdDataCase do
  @moduledoc """
  Case template for tests that run against a converted copy of the
  production database: the old tables plus the new back-end the catalog
  migration fills from them.

  These tests check the new back-end's invariants on real data and
  exercise the old admin's write paths (reclassify, cascade delete, genus
  rename) against it. All writes use the Ecto sandbox so they roll back
  automatically.

  ## Usage

      use Gallformers.ProdDataCase

  Tests using this case template are excluded by default. Run them with:

      make test-prod-data                                  # download + convert
      make test-prod-data PROD_DATA_DB=gallformers_taxogall  # clone a converted copy

  Either way the copy is loaded into `gallformers_test` (the source
  database is only read, as a template), the `:prod_data` tests run, and the
  test database is rebuilt from the seeds afterwards.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  @min_gall_count 1000

  using do
    quote do
      alias Gallformers.Repo

      import Ecto
      import Ecto.Query
      import Gallformers.ProdDataCase
    end
  end

  setup_all _tags do
    pid = Sandbox.start_owner!(Gallformers.Repo, shared: true)
    count = Gallformers.Catalog.count_galls()
    Sandbox.stop_owner(pid)

    if count < @min_gall_count do
      raise """
      Prod data tests require a converted production copy (found #{count} Galls, need >= #{@min_gall_count}).

      Run `make test-prod-data`, which loads and converts the latest backup,
      or `make test-prod-data PROD_DATA_DB=gallformers_taxogall` to clone a
      converted copy.
      """
    end

    :ok
  end

  setup tags do
    if tags[:async] do
      raise "async: true is not supported for prod data tests. Use async: false (the default)."
    end

    pid = Sandbox.start_owner!(Gallformers.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    :ok
  end

  @doc """
  Returns the count of rows for the given schema module.

      assert data_count(Gallformers.Taxa.Taxon) > 500
  """
  def data_count(schema) do
    Gallformers.Repo.aggregate(schema, :count)
  end
end
