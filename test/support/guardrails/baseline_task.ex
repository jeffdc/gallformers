defmodule Mix.Tasks.Gallformers.Guardrails.Baseline do
  use Boundary, check: [in: false, out: false]

  @moduledoc """
  Locks in the copied-code baseline (matter `c800`).

  Recounts copied code (see `Gallformers.Guardrails.DuplicateCode`) and writes
  the counts to `test/support/duplicate_code_baseline.json`. Run it after
  removing copied code, so the test holds the gain. Never run it to make new
  copied code pass.

      mix gallformers.guardrails.baseline

  It runs in the test environment, where Credo and this module are compiled.
  """
  use Mix.Task

  alias Gallformers.Guardrails.DuplicateCode

  @shortdoc "Lock in the copied-code baseline"

  @impl Mix.Task
  def run(_args) do
    path = DuplicateCode.write_baseline()
    total = path |> File.read!() |> Jason.decode!() |> Map.values() |> Enum.sum()
    Mix.shell().info("Wrote #{path}: #{total} copied-code findings in the baseline.")
  end
end
