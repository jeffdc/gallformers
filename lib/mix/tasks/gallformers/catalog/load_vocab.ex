defmodule Mix.Tasks.Gallformers.Catalog.LoadVocab do
  use Boundary, check: [in: false, out: false]

  @moduledoc """
  Loads the Catalog's vocabularies: Trait values and term mappings from
  `priv/import/vocab/traits.json`, and the provisional generation groups
  (`Gallformers.Catalog.load_vocab/1`). Idempotent: run it after a contract
  change; unchanged rows are left alone and nothing is deleted.

  ## Usage

      MIX_ENV=dev mix gallformers.catalog.load_vocab

  The writes are audited as the system actor `"catalog_vocab"`.
  """
  use Mix.Task

  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog

  @shortdoc "Loads the Catalog's Trait and generation vocabularies"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    {:ok, counts} = Catalog.load_vocab(Actor.system("catalog_vocab"))

    Mix.shell().info("Catalog vocabularies loaded (rows inserted or updated):")

    for {table, count} <- Enum.sort(counts) do
      Mix.shell().info("  #{table}: #{count}")
    end
  end
end
