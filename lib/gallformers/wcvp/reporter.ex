defmodule Gallformers.Wcvp.Reporter do
  @moduledoc """
  Writes reconciliation results as JSON report files.
  """

  @base_dir "priv/repo/data/reconciliation"

  @doc """
  Returns the default report output directory for today's date.
  """
  def report_dir do
    today = Date.utc_today() |> Date.to_iso8601()
    Path.join(@base_dir, today)
  end

  @doc """
  Writes a list of report items as a JSON file.
  Returns the path of the written file.
  """
  def write_report(items, report_name, dir \\ nil) do
    dir = dir || report_dir()
    File.mkdir_p!(dir)

    path = Path.join(dir, "#{report_name}.json")
    json = Jason.encode!(items, pretty: true)
    File.write!(path, json)

    path
  end
end
