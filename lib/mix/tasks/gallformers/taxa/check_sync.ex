defmodule Mix.Tasks.Gallformers.Taxa.CheckSync do
  use Boundary, check: [in: false, out: false]

  @moduledoc """
  Checks that the tree follows the Facts (matter `f923` Task 5): rebuilds
  the expected tree from the current taxonomic Facts of every taxon
  outside Plantae and prints each tree row that differs
  (`Gallformers.Taxa.Sync.check/0`). It only reads, and starts nothing but
  the repo:

      mix gallformers.taxa.check_sync
      MIX_ENV=dev PGDATABASE=gallformers_taxogall mix gallformers.taxa.check_sync

  On a release (production), `bin/gallformers eval
  "Gallformers.Release.check_taxa_sync()"`.
  """
  use Mix.Task

  alias Gallformers.Repo
  alias Gallformers.Taxa.Sync

  @shortdoc "Lists tree rows that differ from the taxonomic Facts (read-only)"

  @impl Mix.Task
  def run(_args) do
    start_repo()
    shell = Mix.shell()
    Sync.check() |> format() |> Enum.each(&shell.info/1)
  end

  @doc "The differences as lines to print (`Gallformers.Taxa.Sync.format/1`)."
  @spec format([Sync.difference()]) :: [String.t()]
  defdelegate format(differences), to: Sync

  defp start_repo do
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:ecto_sql)

    case Repo.start_link(pool_size: 2) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end
