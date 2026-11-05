defmodule Mix.Tasks.Gallformers.Import.TermCandidates do
  use Boundary, check: [in: false, out: false]

  @moduledoc """
  Gathers the Trait terms of producer packages into seed candidates for
  the term table (matter `d213`, Task F;
  `Gallformers.Import.gather_term_candidates/2`), for a superadmin to rule
  on from the vocabulary page (`/admin/vocabulary`, "Seed terms") before
  go-live.

      MIX_ENV=dev PGDATABASE=gallformers_taxogall mix gallformers.import.term_candidates \\
        services/import-producer/output/golden-2026-10-27 services/import-producer/output/trial/729-aphis-rubifolii

  Each directory is searched for `gall.json` files; a package is named by
  the directory holding its `gall.json`. Gathering a package again replaces
  its counts; a decided candidate is never changed. Terms the term table
  already holds are reported, with the categories producers suggested
  other than theirs. Runs as the system actor `"term_candidates"`.
  """
  use Mix.Task

  alias Gallformers.Audit.Actor
  alias Gallformers.Import

  @shortdoc "Gathers producer packages' Trait terms as seed candidates"

  @impl Mix.Task
  def run(args) do
    {_opts, dirs} = OptionParser.parse!(args, strict: [])

    if dirs == [],
      do: Mix.raise("Usage: mix gallformers.import.term_candidates <dir>...")

    for dir <- dirs, not File.dir?(dir), do: Mix.raise("no such directory: #{dir}")

    Mix.Task.run("app.start")
    # Dev logs every query at debug; the summary is what matters here.
    if Logger.compare_levels(Logger.level(), :info) == :lt, do: Logger.configure(level: :info)

    case Import.gather_term_candidates(Actor.system("term_candidates"), dirs) do
      {:ok, summary} -> report(summary)
      {:error, reason} -> Mix.raise("Could not gather the candidates: #{inspect(reason)}")
    end
  end

  defp report(summary) do
    info("#{count(summary.packages, "package")}, #{count(summary.uses, "use")} of Trait terms")

    info(
      "Candidates: #{summary.created} new, #{summary.updated} updated, " <>
        "#{summary.decided} already decided (left as they are)"
    )

    for {path, reason} <- summary.unreadable, do: info("  unreadable: #{path} (#{reason})")

    if summary.held != [] do
      info("Already in the vocabulary (#{length(summary.held)}):")

      for held <- summary.held do
        info("  #{held.trait}: “#{held.term}” #{standing(held)}#{conflicts(held.conflicts)}")
      end
    end
  end

  defp standing(%{status: :placed, categories: categories}),
    do: "placed under #{Enum.join(categories, ", ")}"

  defp standing(%{status: :ambiguous, candidates: candidates}),
    do: "ambiguous between #{Enum.join(candidates, ", ")}"

  defp standing(%{status: :no_fit}), do: "fits no category"

  defp conflicts([]), do: ""

  defp conflicts(conflicts) do
    " — producers suggested " <>
      Enum.map_join(conflicts, ", ", &"#{&1["category"]} #{&1["count"]}")
  end

  defp count([_] = list, word) when is_list(list), do: "1 #{word}"
  defp count(list, word) when is_list(list), do: "#{length(list)} #{word}s"
  defp count(1, word), do: "1 #{word}"
  defp count(n, word), do: "#{n} #{word}s"

  defp info(line), do: Mix.shell().info(line)
end
