defmodule Gallformers.Curation.PackageListener do
  @moduledoc """
  Curation's "package advanced" listener (`Gallformers.Import.Events`),
  registered in `config/config.exs` and called by the import job after each
  step it takes a package: the tray items submitted in that package learn
  their outcome (`Gallformers.Curation.settle_package/1`).
  """
  @behaviour Gallformers.Import.Events

  alias Gallformers.Curation

  @impl true
  def package_advanced(package), do: Curation.settle_package(package.id)
end
