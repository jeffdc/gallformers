defmodule Gallformers.S3 do
  @moduledoc """
  S3 wrapper that respects `s3_enabled` config for test isolation.

  All S3 operations should go through this module instead of calling
  `ExAws.request/1` directly. This ensures tests never make real AWS calls.

  ## Configuration

      # config/test.exs
      config :gallformers, s3_enabled: false

  ## Usage

      # Instead of:
      ExAws.S3.put_object(bucket, path, data) |> ExAws.request()

      # Use:
      ExAws.S3.put_object(bucket, path, data) |> Gallformers.S3.request()
  """

  require Logger

  @doc """
  Executes an ExAws operation, respecting the `s3_enabled` config.

  Returns `{:ok, %{}}` when S3 is disabled (test environment).
  """
  @spec request(ExAws.Operation.t()) :: {:ok, term()} | {:error, term()}
  def request(operation) do
    if Application.get_env(:gallformers, :s3_enabled, true) do
      ExAws.request(operation)
    else
      # Return mock success in test environment
      # Structure works for both list ops (need body.contents) and mutate ops (just check {:ok, _})
      {:ok, %{body: %{contents: [], is_truncated: false}}}
    end
  end
end
