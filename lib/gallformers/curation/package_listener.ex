defmodule Gallformers.Curation.PackageListener do
  @moduledoc """
  Curation's "package advanced" listener (`Gallformers.Import.Events`),
  registered in `config/config.exs` and called by the import job after each
  step it takes a package: the tray items submitted in that package learn
  their outcome (`Gallformers.Curation.settle_package/1`), and the pages
  listing the curators' changes hear of the step
  (`Gallformers.Audit.ChangeLog.changed/0`): an import applied, held or
  approved is a change.
  """
  @behaviour Gallformers.Import.Events

  alias Gallformers.Audit.ChangeLog
  alias Gallformers.Curation

  @impl true
  def package_advanced(package) do
    :ok = Curation.settle_package(package.id)
    ChangeLog.changed()
  end
end
