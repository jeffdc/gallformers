defmodule Mix.Tasks.Gallformers.Facts.RecomputeContests do
  use Boundary, check: [in: false, out: false]

  @moduledoc """
  Recomputes the standings of the Facts that contest a name (matter `f923`:
  a revalidated name outranks an older synonymy of it;
  `Gallformers.Facts.recompute_contests/1`), audited as the system actor
  `"recompute_contests"`, and prints how many contests it recomputed and
  how many Facts' standings changed; the tree follows what changes.
  Migration `20261107140000_add_fact_contests` gave the existing name and
  synonymy Facts their contests without recomputing, so run it once on a
  database migrated past that. It writes to the database the environment
  points at, and starts nothing but the repo:

      MIX_ENV=dev PGDATABASE=gallformers_taxogall mix gallformers.facts.recompute_contests

  Idempotent: running it again changes nothing. On a release,
  `bin/gallformers eval "Gallformers.Release.recompute_contests()"`.
  """
  use Mix.Task

  alias Gallformers.Audit.Actor
  alias Gallformers.Facts
  alias Gallformers.Repo

  @shortdoc "Recomputes the standings of the Facts contesting a name (idempotent)"

  @impl Mix.Task
  def run(_args) do
    start_repo()
    recompute(Actor.system("recompute_contests"))
  end

  @doc "Recomputes the contests as `actor` and prints the summary; raises when a listener refuses."
  @spec recompute(Actor.t()) :: :ok
  def recompute(actor) do
    case Facts.recompute_contests(actor) do
      {:ok, summary} -> Mix.shell().info(Facts.format_contests_recomputed(summary))
      {:error, reason} -> Mix.raise("Contests not all recomputed: #{inspect(reason)}")
    end
  end

  defp start_repo do
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:ecto_sql)

    case Repo.start_link(pool_size: 2) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end
