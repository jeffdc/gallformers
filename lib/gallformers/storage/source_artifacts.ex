defmodule Gallformers.Storage.SourceArtifacts do
  @moduledoc """
  Storage helpers for private ingestion artifacts and public published-source
  artifacts.
  """

  alias Gallformers.Storage.S3

  @type stage :: atom() | String.t()
  @type source_artifact_ref :: %{
          required(:id) => integer(),
          required(:title) => term(),
          optional(any()) => any()
        }
  @published_sources_prefix "sources"
  @max_filename_base_length 120

  defmodule Backend do
    @moduledoc false

    @callback copy_object(String.t(), String.t(), String.t(), String.t()) ::
                {:ok, term()} | {:error, term()}

    @callback upload(String.t(), String.t(), binary(), String.t()) ::
                {:ok, term()} | {:error, term()}

    @callback get_object(String.t(), String.t()) :: {:ok, map()} | {:error, term()}

    @callback list_objects(String.t(), String.t(), String.t() | nil) ::
                {:ok,
                 %{
                   keys: [String.t()],
                   next_continuation_token: String.t() | nil,
                   is_truncated: boolean()
                 }}
                | {:error, term()}

    @callback delete_objects(String.t(), [String.t()]) :: {:ok, term()} | {:error, term()}
  end

  defmodule DefaultBackend do
    @moduledoc false

    @behaviour Gallformers.Storage.SourceArtifacts.Backend

    @impl true
    def copy_object(dest_bucket, dest_path, src_bucket, src_path) do
      ExAws.S3.put_object_copy(dest_bucket, dest_path, src_bucket, src_path)
      |> S3.request()
    end

    @impl true
    def upload(bucket, path, content, content_type) do
      ExAws.S3.put_object(bucket, path, content, content_type: content_type)
      |> S3.request()
    end

    @impl true
    def get_object(bucket, path) do
      bucket
      |> ExAws.S3.get_object(path)
      |> S3.request()
    end

    @impl true
    def list_objects(bucket, prefix, continuation_token) do
      opts =
        [prefix: prefix]
        |> maybe_put_continuation_token(continuation_token)

      case ExAws.S3.list_objects_v2(bucket, opts) |> S3.request() do
        {:ok, %{body: body}} ->
          {:ok,
           %{
             keys: extract_keys(body),
             next_continuation_token: next_continuation_token(body),
             is_truncated: truncated?(body)
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end

    @impl true
    def delete_objects(bucket, keys) do
      ExAws.S3.delete_multiple_objects(bucket, keys)
      |> S3.request()
    end

    defp maybe_put_continuation_token(opts, nil), do: opts

    defp maybe_put_continuation_token(opts, continuation_token) do
      Keyword.put(opts, :continuation_token, continuation_token)
    end

    defp extract_keys(body) do
      body
      |> Map.get(:contents, Map.get(body, "contents", []))
      |> List.wrap()
      |> Enum.map(fn entry -> Map.get(entry, :key, Map.get(entry, "key")) end)
      |> Enum.reject(&is_nil/1)
    end

    defp next_continuation_token(body) do
      Map.get(body, :next_continuation_token, Map.get(body, "next_continuation_token"))
    end

    defp truncated?(body) do
      case Map.get(body, :is_truncated, Map.get(body, "is_truncated")) do
        true -> true
        "true" -> true
        _ -> false
      end
    end
  end

  @doc """
  Returns the private bucket used for ingestion uploads and pipeline artifacts.
  """
  @spec private_bucket() :: String.t()
  def private_bucket do
    storage_config()[:private_bucket]
  end

  @doc """
  Returns the canonical private artifact prefix for an ingestion ID.
  """
  @spec private_artifact_prefix(integer()) :: String.t()
  def private_artifact_prefix(ingestion_id) when is_integer(ingestion_id) do
    Path.join("source-ingestions", Integer.to_string(ingestion_id))
  end

  @doc """
  Returns the canonical private artifact path for an ingestion stage output.
  """
  @spec private_artifact_path(integer(), stage(), String.t()) :: String.t()
  def private_artifact_path(ingestion_id, stage, filename)
      when is_integer(ingestion_id) and is_binary(filename) do
    Path.join([
      private_artifact_prefix(ingestion_id),
      normalize_stage(stage),
      filename
    ])
  end

  @doc """
  Returns a path under an existing private artifact prefix.

  This preserves persisted `artifacts_path` behavior during the migration away
  from `Ingestions` path ownership.
  """
  @spec private_artifact_path(String.t() | nil, String.t() | [String.t()]) :: String.t() | nil
  def private_artifact_path(artifacts_path, _suffix) when artifacts_path in [nil, ""] do
    nil
  end

  def private_artifact_path(artifacts_path, suffix)
      when is_binary(artifacts_path) and is_binary(suffix) do
    Path.join(artifacts_path, suffix)
  end

  def private_artifact_path(artifacts_path, suffixes)
      when is_binary(artifacts_path) and is_list(suffixes) do
    Enum.reduce(suffixes, artifacts_path, fn suffix, acc -> Path.join(acc, suffix) end)
  end

  @doc """
  Uploads a canonical private artifact and returns its key.
  """
  @spec upload_private_artifact(integer(), stage(), String.t(), binary(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def upload_private_artifact(ingestion_id, stage, filename, content, content_type)
      when is_binary(content) and is_binary(content_type) do
    path = private_artifact_path(ingestion_id, stage, filename)

    case backend().upload(private_bucket(), path, content, content_type) do
      {:ok, _response} -> {:ok, path}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Downloads a canonical private artifact.
  """
  @spec download_private_artifact(integer(), stage(), String.t()) ::
          {:ok, binary()} | {:error, term()}
  def download_private_artifact(ingestion_id, stage, filename) do
    path = private_artifact_path(ingestion_id, stage, filename)

    case backend().get_object(private_bucket(), path) do
      {:ok, %{body: body}} when is_binary(body) -> {:ok, body}
      {:ok, body} when is_binary(body) -> {:ok, body}
      {:error, reason} when reason in [:not_found, :no_such_key] -> {:error, :not_found}
      {:error, reason} -> normalize_download_error(reason)
    end
  end

  @doc """
  Lists every private artifact key stored for an ingestion under its canonical
  prefix.
  """
  @spec list_private_artifacts_for_ingestion(integer()) :: {:ok, [String.t()]} | {:error, term()}
  def list_private_artifacts_for_ingestion(ingestion_id) when is_integer(ingestion_id) do
    ingestion_id
    |> private_artifact_prefix()
    |> Kernel.<>("/")
    |> list_private_artifact_keys()
    |> case do
      {:ok, keys} -> {:ok, Enum.sort(keys)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes every private artifact stored for an ingestion under its canonical
  prefix.
  """
  @spec delete_private_artifacts_for_ingestion(integer()) :: :ok | {:error, term()}
  def delete_private_artifacts_for_ingestion(ingestion_id) when is_integer(ingestion_id) do
    case list_private_artifacts_for_ingestion(ingestion_id) do
      {:ok, keys} -> delete_private_artifact_keys(keys)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns the public bucket used for published source artifacts.
  """
  @spec public_bucket() :: String.t()
  def public_bucket do
    storage_config()[:public_bucket]
  end

  @doc """
  Returns the public base URL for published source artifacts.
  """
  @spec public_base_url() :: String.t()
  def public_base_url do
    storage_config()[:public_base_url]
  end

  @doc """
  Returns the public `sources/{id}` prefix for a source.
  """
  @spec public_source_prefix(integer()) :: String.t()
  def public_source_prefix(source_id) when is_integer(source_id) do
    Path.join([@published_sources_prefix, Integer.to_string(source_id)])
  end

  @doc """
  Returns the canonical public markdown path for a published source.
  """
  @spec published_markdown_path(source_artifact_ref()) :: String.t()
  def published_markdown_path(%{id: source_id, title: title}) when is_integer(source_id) do
    Path.join([public_source_prefix(source_id), markdown_filename(source_id, title)])
  end

  @doc """
  Returns the public URL for a published source markdown file.
  """
  @spec published_markdown_url(source_artifact_ref()) :: String.t()
  def published_markdown_url(source) when is_map(source) do
    source
    |> published_markdown_path()
    |> public_url()
  end

  @doc """
  Builds a public URL for a published source artifact path.
  """
  @spec public_url(String.t()) :: String.t()
  def public_url(path) when is_binary(path) do
    base_url = public_base_url() |> String.trim_trailing("/")
    path = String.trim_leading(path, "/")
    "#{base_url}/#{path}"
  end

  @doc """
  Copies a private ingestion artifact to a public published-source path.
  """
  @spec copy_private_to_public(String.t(), String.t()) ::
          {:ok, %{bucket: String.t(), path: String.t(), url: String.t()}}
          | {:error, term()}
  def copy_private_to_public(private_path, public_path)
      when is_binary(private_path) and is_binary(public_path) do
    case backend().copy_object(public_bucket(), public_path, private_bucket(), private_path) do
      {:ok, _response} ->
        {:ok, %{bucket: public_bucket(), path: public_path, url: public_url(public_path)}}

      {:error, reason} ->
        normalize_copy_error(reason)
    end
  end

  defp backend do
    Application.get_env(:gallformers, __MODULE__, [])
    |> Keyword.get(:backend, DefaultBackend)
  end

  defp storage_config do
    Application.get_env(:gallformers, :source_storage, [])
  end

  defp list_private_artifact_keys(prefix, continuation_token \\ nil, acc \\ []) do
    case backend().list_objects(private_bucket(), prefix, continuation_token) do
      {:ok, result} ->
        continue_or_finish_listing(prefix, result, acc)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp continue_or_finish_listing(prefix, result, acc) do
    keys = Map.get(result, :keys, Map.get(result, "keys", []))

    if truncated_listing?(result) do
      case Map.get(result, :next_continuation_token, Map.get(result, "next_continuation_token")) do
        next_token when is_binary(next_token) and next_token != "" ->
          list_private_artifact_keys(prefix, next_token, Enum.reverse(keys, acc))

        _ ->
          {:error, :invalid_continuation_token}
      end
    else
      {:ok, Enum.reverse(acc, keys)}
    end
  end

  defp truncated_listing?(result) do
    case Map.get(result, :is_truncated, Map.get(result, "is_truncated")) do
      true ->
        true

      "true" ->
        true

      false ->
        false

      "false" ->
        false

      nil ->
        next_token =
          Map.get(result, :next_continuation_token, Map.get(result, "next_continuation_token"))

        is_binary(next_token) and next_token != ""

      _ ->
        false
    end
  end

  defp delete_private_artifact_keys([]), do: :ok

  defp delete_private_artifact_keys(keys) do
    case backend().delete_objects(private_bucket(), keys) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp markdown_filename(source_id, title) do
    base_name =
      title
      |> normalize_title()
      |> truncate_base_name()
      |> fallback_base_name(source_id)

    "#{base_name}.md"
  end

  defp normalize_title(title) when is_binary(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}\s_-]/u, "")
    |> String.replace(~r/[\s-]+/u, "_")
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
  end

  defp normalize_title(_title), do: ""

  defp truncate_base_name(base_name) do
    base_name
    |> String.slice(0, @max_filename_base_length)
    |> String.trim_trailing("_")
  end

  defp fallback_base_name("", source_id), do: "source_#{source_id}"
  defp fallback_base_name(base_name, _source_id), do: base_name

  defp normalize_stage(stage) when is_atom(stage), do: Atom.to_string(stage)
  defp normalize_stage(stage) when is_binary(stage), do: stage

  defp normalize_download_error({:http_error, 404, _details}), do: {:error, :not_found}
  defp normalize_download_error(%{status_code: 404}), do: {:error, :not_found}
  defp normalize_download_error(%{reason: :not_found}), do: {:error, :not_found}
  defp normalize_download_error(reason), do: {:error, reason}

  defp normalize_copy_error(reason) when reason in [:not_found, :no_such_key] do
    {:error, :private_artifact_not_found}
  end

  defp normalize_copy_error({:http_error, 404, _details}) do
    {:error, :private_artifact_not_found}
  end

  defp normalize_copy_error(%{status_code: 404}) do
    {:error, :private_artifact_not_found}
  end

  defp normalize_copy_error(%{reason: :not_found}) do
    {:error, :private_artifact_not_found}
  end

  defp normalize_copy_error(reason), do: {:error, reason}
end
