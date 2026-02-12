defmodule Gallformers.ProdDataCase do
  @moduledoc """
  Case template for tests that run against a copy of the production database.

  These tests validate data integrity and exercise write paths (reclassify,
  cascade delete, genus rename) against real data. All writes use the Ecto
  sandbox so they roll back automatically.

  ## Usage

      use Gallformers.ProdDataCase

  Tests using this case template are excluded by default. Run them with:

      make test-prod-data

  which copies the local dev database to the test path and includes the
  `:prod_data` tag.

  NOTE: Like DataCase, async: true is NOT supported with SQLite.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  import Ecto.Query

  @min_species_count 1000

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

    count =
      Gallformers.Repo.one(from s in "species", select: count(s.id))

    Sandbox.stop_owner(pid)

    if count < @min_species_count do
      raise """
      Prod data tests require a real database (found #{count} species, need >= #{@min_species_count}).

      Run `make test-prod-data` which copies priv/gallformers.sqlite to the test DB.
      """
    end

    :ok
  end

  setup tags do
    if tags[:async] do
      raise "async: true is not supported with SQLite. Use async: false (the default)."
    end

    pid = Sandbox.start_owner!(Gallformers.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    :ok
  end

  @doc """
  Returns the count of rows for the given schema module.

      assert data_count(Gallformers.Taxonomy.Taxonomy) > 500
  """
  def data_count(schema) do
    Gallformers.Repo.aggregate(schema, :count)
  end
end
