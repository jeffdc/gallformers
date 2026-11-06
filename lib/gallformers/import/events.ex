defmodule Gallformers.Import.Events do
  @moduledoc """
  "Package advanced" events, with the dependency inverted (as
  `Gallformers.Facts.Events`): Import never references the contexts that
  wait on its packages (e.g. `Gallformers.Curation`, whose tray items wait
  for the package they were submitted in).

  After the import job (`Gallformers.Import.Worker`) takes a package a
  step on — validated and resolved, applied, or held back for review — it
  calls every registered listener with the package as it now is, after the
  step's transactions have committed. A listener returns `:ok`; it cannot
  undo the step, and a raise fails the job (which Oban retries: the steps
  are idempotent).

  ## Registration

      config :gallformers, Gallformers.Import.Events,
        listeners: [Gallformers.Curation.PackageListener]
  """

  alias Gallformers.Import.Package

  @doc "Reacts to a package the import job took a step on."
  @callback package_advanced(Package.t()) :: :ok

  @doc "The registered listeners, in call order."
  @spec listeners() :: [module()]
  def listeners do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:listeners, [])
  end

  @doc "Calls each listener with `package`."
  @spec dispatch(Package.t()) :: :ok
  def dispatch(%Package{} = package) do
    Enum.each(listeners(), fn listener ->
      case listener.package_advanced(package) do
        :ok ->
          :ok

        other ->
          raise ArgumentError,
                "#{inspect(listener)}.package_advanced/1 must return :ok, got: #{inspect(other)}"
      end
    end)
  end
end
