defmodule Mix.Tasks.Gallformers.DesignSystem.Baseline do
  use Boundary, check: [in: false, out: false]

  @moduledoc """
  Locks in the design-system conformance baseline.

  Recounts off-system styling (see `GallformersWeb.DesignSystem.Conformance`)
  and writes the counts to `test/support/design_system_baseline.json`. Run it
  after moving code onto the system, so the conformance test holds the gain.
  Never run it to make new off-system styling pass.

      mix gallformers.design_system.baseline
  """
  use Mix.Task

  alias GallformersWeb.DesignSystem.Conformance

  @shortdoc "Lock in the design-system conformance baseline"

  @impl Mix.Task
  def run(_args) do
    path = Conformance.write_baseline()

    total =
      path |> File.read!() |> Jason.decode!() |> Enum.flat_map(fn {_, r} -> Map.values(r) end)

    Mix.shell().info("Wrote #{path}: #{Enum.sum(total)} off-system findings in the baseline.")
  end
end
