defmodule Gallformers.Storage.LocalBackend do
  @moduledoc """
  Filesystem-backed storage backend for dev. Drop-in replacement for the
  S3 DefaultBackend — the "bucket" parameter is treated as a root directory.
  """

  @behaviour Gallformers.Storage.SourceArtifacts.Backend

  @impl true
  def upload(bucket, path, content, _content_type) do
    full_path = Path.join(bucket, path)
    full_path |> Path.dirname() |> File.mkdir_p!()
    File.write!(full_path, content)
    {:ok, %{}}
  end

  @impl true
  def get_object(bucket, path) do
    full_path = Path.join(bucket, path)

    case File.read(full_path) do
      {:ok, body} -> {:ok, %{body: body}}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def list_objects(bucket, prefix, _continuation_token) do
    dir = Path.join(bucket, prefix)

    keys =
      if File.dir?(dir) do
        dir
        |> list_files_recursive()
        |> Enum.map(&Path.relative_to(&1, bucket))
        |> Enum.sort()
      else
        []
      end

    {:ok, %{keys: keys, is_truncated: false, next_continuation_token: nil}}
  end

  @impl true
  def delete_objects(bucket, keys) do
    Enum.each(keys, fn key ->
      Path.join(bucket, key) |> File.rm()
    end)

    {:ok, %{}}
  end

  @impl true
  def copy_object(dest_bucket, dest_path, src_bucket, src_path) do
    source = Path.join(src_bucket, src_path)
    destination = Path.join(dest_bucket, dest_path)
    destination |> Path.dirname() |> File.mkdir_p!()
    File.cp!(source, destination)
    {:ok, %{}}
  end

  defp list_files_recursive(dir) do
    dir
    |> File.ls!()
    |> Enum.flat_map(fn entry ->
      full = Path.join(dir, entry)

      if File.dir?(full) do
        list_files_recursive(full)
      else
        [full]
      end
    end)
  end
end
