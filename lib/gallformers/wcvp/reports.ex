defmodule Gallformers.Wcvp.Reports do
  @moduledoc """
  Reads WCVP reconciliation report files from disk.

  Reports are stored as JSON files in date-stamped directories under
  `priv/repo/data/reconciliation/YYYY-MM-DD/`. This module provides
  functions to list available runs, get summary counts, and load
  individual report files.
  """

  @default_base_dir "priv/repo/data/reconciliation"

  @doc """
  Returns available report run dates, most recent first.
  """
  def list_runs(base_dir \\ @default_base_dir) do
    case File.ls(base_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&date_dir?/1)
        |> Enum.sort(:desc)

      {:error, _} ->
        []
    end
  end

  @doc """
  Returns a summary map with counts for each report type in a given run.
  Returns nil if the run directory doesn't exist.
  """
  def summary(run_date, base_dir \\ @default_base_dir) do
    dir = Path.join(base_dir, run_date)

    if File.dir?(dir) do
      %{
        run_date: run_date,
        taxonomy_mismatches: count_items(dir, "taxonomy-mismatches"),
        gf_not_in_wcvp: count_items(dir, "in-gf-not-wcvp"),
        range_updates: count_items(dir, "range-updates")
      }
    end
  end

  @doc """
  Loads and parses a specific report file. Returns {:ok, items} or {:error, reason}.
  """
  def load_report(run_date, report_name, base_dir \\ @default_base_dir) do
    path = Path.join([base_dir, run_date, "#{report_name}.json"])

    case File.read(path) do
      {:ok, content} -> {:ok, Jason.decode!(content)}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # -- Private --

  defp date_dir?(name), do: Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, name)

  defp count_items(dir, report_name) do
    path = Path.join(dir, "#{report_name}.json")

    case File.read(path) do
      {:ok, content} -> content |> Jason.decode!() |> length()
      {:error, _} -> 0
    end
  end
end
