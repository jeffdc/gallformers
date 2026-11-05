defmodule Gallformers.Storage.Private do
  @moduledoc """
  Get and put objects in the private bucket (`gallformers-private`,
  `infra/s3.tf`): material that is never served publicly, such as Sources'
  stored documents and import packages.

  ## Configuration

      # config/config.exs
      config :gallformers, :private_storage, bucket: "gallformers-private"

      # config/test.exs: an in-memory stub, so tests never reach S3
      config :gallformers, :private_storage, adapter: Gallformers.Storage.PrivateStub

      # config/dev.exs: files on the local disk, so development never
      # writes to production's private bucket
      config :gallformers, :private_storage, adapter: Gallformers.Storage.Private.LocalAdapter

  The default adapter is `Gallformers.Storage.Private.S3Adapter`, which goes
  through `Gallformers.Storage.S3` and so also respects `s3_enabled`.
  """

  @no_writes {__MODULE__, :no_writes}

  @doc "Stores `data` under `key` in `bucket`."
  @callback put_object(
              bucket :: String.t(),
              key :: String.t(),
              data :: binary(),
              opts :: keyword()
            ) ::
              :ok | {:error, term()}

  @doc "Reads the object under `key` in `bucket`."
  @callback get_object(bucket :: String.t(), key :: String.t()) ::
              {:ok, binary()} | {:error, :not_found} | {:error, term()}

  @doc """
  Stores `data` under `key`. Options go to `ExAws.S3.put_object/4`
  (e.g. `content_type: "application/json"`).
  """
  @spec put(String.t(), binary(), keyword()) :: :ok | {:error, term()}
  def put(key, data, opts \\ []) when is_binary(key) and is_binary(data) do
    if Process.get(@no_writes, false),
      do: :ok,
      else: adapter().put_object(bucket(), key, data, opts)
  end

  @doc """
  Runs `fun` with `put/3` writing nothing for this process (it returns
  `:ok`), returning its result: for work inside a transaction that is
  rolled back, whose stored objects would be left behind (the Facts
  preview, `Gallformers.Import.preview_package/2`).
  """
  @spec without_writes((-> result)) :: result when result: var
  def without_writes(fun) when is_function(fun, 0) do
    previous = Process.put(@no_writes, true)

    try do
      fun.()
    after
      if previous, do: Process.put(@no_writes, previous), else: Process.delete(@no_writes)
    end
  end

  @doc "Reads the object under `key`; `{:error, :not_found}` when there is none."
  @spec get(String.t()) :: {:ok, binary()} | {:error, :not_found} | {:error, term()}
  def get(key) when is_binary(key) do
    adapter().get_object(bucket(), key)
  end

  @doc "The private bucket's name."
  @spec bucket() :: String.t()
  def bucket, do: Keyword.fetch!(config(), :bucket)

  @doc "The module that stores objects (the S3 adapter unless configured otherwise)."
  @spec adapter() :: module()
  def adapter, do: Keyword.get(config(), :adapter, Gallformers.Storage.Private.S3Adapter)

  defp config, do: Application.get_env(:gallformers, :private_storage, [])
end

defmodule Gallformers.Storage.Private.S3Adapter do
  @moduledoc """
  The private bucket on S3, through `Gallformers.Storage.S3` (which returns
  mock responses when `s3_enabled` is false).
  """
  @behaviour Gallformers.Storage.Private

  alias Gallformers.Storage.S3

  @impl true
  def put_object(bucket, key, data, opts) do
    case bucket |> ExAws.S3.put_object(key, data, opts) |> S3.request() do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_object(bucket, key) do
    case bucket |> ExAws.S3.get_object(key) |> S3.request() do
      {:ok, %{body: body}} when is_binary(body) -> {:ok, body}
      {:ok, response} -> {:error, {:unexpected_response, response}}
      {:error, {:http_error, 404, _}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end

defmodule Gallformers.Storage.Private.LocalAdapter do
  @moduledoc """
  The private bucket as files on the local disk, for development:
  `<root>/<bucket>/<key>`, with the root `tmp/private_storage` (gitignored)
  unless `:local_root` is set in the `:private_storage` config. Packages
  imported locally and the Source documents they store stay on this
  machine.
  """
  @behaviour Gallformers.Storage.Private

  @doc "The directory holding the buckets."
  @spec root() :: String.t()
  def root do
    :gallformers
    |> Application.get_env(:private_storage, [])
    |> Keyword.get(:local_root, "tmp/private_storage")
  end

  @impl true
  def put_object(bucket, key, data, _opts) do
    with {:ok, path} <- path(bucket, key),
         :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, data)
    end
  end

  @impl true
  def get_object(bucket, key) do
    with {:ok, path} <- path(bucket, key) do
      case File.read(path) do
        {:ok, data} -> {:ok, data}
        {:error, :enoent} -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # A key's segments stay inside its bucket.
  defp path(bucket, key) do
    if ".." in Path.split(key),
      do: {:error, :invalid_key},
      else: {:ok, Path.join([root(), bucket, key])}
  end
end
