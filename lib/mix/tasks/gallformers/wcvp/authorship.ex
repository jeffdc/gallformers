defmodule Mix.Tasks.Gallformers.Wcvp.Authorship do
  use Boundary, check: [in: false, out: false]

  @moduledoc """
  Gives plants' names WCVP's authorship (matter `f14c`;
  `Gallformers.Ranges.WcvpAuthorship.backfill/2`): every plant name with no
  authorship takes WCVP's authors where WCVP holds the name unambiguously,
  audited as the system actor `"wcvp_authorship"`, and the task prints how
  many it filled, which names are ambiguous (left blank) and how many WCVP
  does not hold. It writes to the database the environment points at, and
  starts nothing but the repo and the WCVP repo:

      MIX_ENV=dev PGDATABASE=gallformers_taxogall mix gallformers.wcvp.authorship

  Idempotent: an authorship a name already has (a curator's) is kept, and
  running it again fills nothing more. The catalog migration does the same
  as one of its steps. On a release, `bin/gallformers eval
  "Gallformers.Release.backfill_wcvp_authorship()"`.
  """
  use Mix.Task

  alias Gallformers.Audit.Actor
  alias Gallformers.Ranges.WcvpAuthorship
  alias Gallformers.Repo

  @shortdoc "Fills plants' names' authorship from WCVP (idempotent)"

  @impl Mix.Task
  def run(_args) do
    start_repos()
    backfill(Actor.system("wcvp_authorship"))
  end

  @doc "Runs the backfill as `actor` and prints its summary; raises when WCVP cannot be read."
  @spec backfill(Actor.t()) :: :ok
  def backfill(actor) do
    case WcvpAuthorship.backfill(actor) do
      {:ok, summary} -> Mix.shell().info(WcvpAuthorship.format(summary))
      {:error, :wcvp_unavailable} -> Mix.raise("The WCVP database cannot be read: nothing filled")
    end
  end

  defp start_repos do
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:ecto_sql)

    for repo <- [Repo, Repo.WCVP] do
      case repo.start_link(pool_size: 2) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
    end
  end
end
