defmodule Gallformers.Version do
  @moduledoc """
  Provides version information for the Gallformers application.

  - **App Version**: CalVer format (YYYY.M.D)
  - **API Version**: SemVer read from API_VERSION file
  """

  # Recompile this module when API_VERSION changes
  # Path: v2/API_VERSION (two levels up from v2/lib/gallformers/)
  @external_resource api_version_path = Path.expand("../../API_VERSION", __DIR__)

  @api_version (case File.read(api_version_path) do
                  {:ok, content} -> String.trim(content)
                  {:error, _} -> "unknown"
                end)

  @app_version (
                 date = Date.utc_today()
                 "#{date.year}.#{date.month}.#{date.day}"
               )

  @doc """
  Returns the application version in CalVer format.

  Example: "2026.2.6"
  """
  @spec app_version() :: String.t()
  def app_version, do: @app_version

  @doc """
  Returns the API version from the API_VERSION file.

  Example: "1.0.0"
  """
  @spec api_version() :: String.t()
  def api_version, do: @api_version
end
