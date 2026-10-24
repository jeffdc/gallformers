defmodule Gallformers.Storage do
  @moduledoc """
  Storage-layer umbrella namespace.

  This module exists as the architectural umbrella for storage submodules such
  as `Gallformers.Storage.S3`, `Gallformers.Storage.Images`, and
  `Gallformers.Storage.PDFKeys`.

  Runtime storage behavior should live in those submodules rather than
  accumulating new helper APIs here.
  """
  use Boundary, deps: [Gallformers.Async], exports: :all
end
