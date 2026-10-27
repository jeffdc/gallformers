defmodule Gallformers.Storage.Images do
  @moduledoc """
  Storage helpers for image objects stored in the public image bucket.

  This module owns image-specific path naming, URL helpers, S3 delete/list
  operations, and the low-level mechanics for derivative uploads.
  Variant policy and image lifecycle decisions stay in higher-level image
  contexts.
  """
  require Logger

  alias Gallformers.Storage.S3
  alias Image, as: ImageLib

  @doc """
  Returns the CDN base URL for image objects.
  """
  @spec cdn_url() :: String.t()
  def cdn_url do
    Application.get_env(:gallformers, :images)[:cdn_url]
  end

  @doc """
  Returns the public CDN URL for an image object path.
  """
  @spec public_url(String.t()) :: String.t()
  def public_url(path) when is_binary(path) do
    path = String.trim_leading(path, "/")
    "#{cdn_url()}/#{path}"
  end

  @doc """
  Returns the full CDN URL for an article image path.
  """
  @spec article_image_url(String.t()) :: String.t()
  def article_image_url(path) do
    public_url(path)
  end

  @doc """
  Returns the public CDN URL for an image path at a specific variant size.
  """
  @spec variant_public_url(String.t(), atom()) :: String.t()
  def variant_public_url(path, size) when is_binary(path) and is_atom(size) do
    path =
      case size do
        :original -> path
        _ -> replace_variant_name(path, size)
      end

    public_url(path)
  end

  @doc """
  Generates the S3 path for an image of a Gall or a taxon, by its ID.

  Format: gall/{id}/{id}_{timestamp}_{unique}_original.{ext}

  Galls and taxa share one layout: their IDs come from one sequence, and
  it is the layout of today's images (whose species IDs the Galls and
  taxa keep).
  """
  @spec generate_path({:gall | :taxon, integer()}, String.t()) :: String.t()
  def generate_path({kind, id}, extension) when kind in [:gall, :taxon] and is_integer(id) do
    timestamp = System.system_time(:millisecond)
    unique = System.unique_integer([:positive])
    ext = String.trim_leading(extension, ".")
    prefix_path("gall/#{id}/#{id}_#{timestamp}_#{unique}_original.#{ext}")
  end

  @doc """
  Generates the S3 path for an article image.

  Format: articles/{article_id}/{timestamp}.{ext}
  """
  @spec generate_article_path(integer(), String.t()) :: String.t()
  def generate_article_path(article_id, extension) when is_integer(article_id) do
    timestamp = System.system_time(:millisecond)
    ext = String.trim_leading(extension, ".")
    prefix_path("articles/#{article_id}/#{timestamp}.#{ext}")
  end

  @doc """
  Generates the S3 path for a content image (article or key).

  Options:
  - `has_variants` - when true, includes `_original` suffix for size variant generation
  """
  @spec generate_content_image_path(String.t(), integer(), String.t(), keyword()) :: String.t()
  def generate_content_image_path(prefix, owner_id, extension, opts \\ []) do
    timestamp = System.system_time(:millisecond)
    unique = System.unique_integer([:positive])
    ext = String.trim_leading(extension, ".")
    has_variants = Keyword.get(opts, :has_variants, false)

    filename =
      if has_variants,
        do: "#{timestamp}_#{unique}_original.#{ext}",
        else: "#{timestamp}_#{unique}.#{ext}"

    prefix_path("#{prefix}/#{owner_id}/#{filename}")
  end

  @doc """
  Generates a presigned URL for uploading an image object.
  """
  @spec presigned_upload_url(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def presigned_upload_url(path, content_type) do
    expiry = Application.get_env(:gallformers, :images)[:presign_expiry] || 300

    case S3.presigned_url(:put, bucket(), path,
           expires_in: expiry,
           query_params: [{"Content-Type", content_type}]
         ) do
      {:ok, url} -> {:ok, url}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Uploads an image object to the public image bucket.
  """
  @spec upload(String.t(), binary(), String.t()) :: {:ok, term()} | {:error, term()}
  def upload(path, data, content_type) do
    ExAws.S3.put_object(bucket(), path, data, content_type: content_type)
    |> S3.request()
  end

  @doc """
  Generates image size variants with a custom sizes config.

  `sizes` is a map or keyword list of `{name, width_px}` pairs.
  An empty map/list is a no-op.
  """
  @spec generate_size_variants(String.t(), map() | keyword()) :: :ok | {:error, term()}
  def generate_size_variants(_original_path, sizes) when sizes == %{} or sizes == [] do
    :ok
  end

  def generate_size_variants(original_path, sizes) do
    original_url = public_url(original_path)

    case fetch_original_image(original_url) do
      {:ok, body} ->
        spawn_resize_tasks(body, original_path, sizes)
        :ok

      {:error, reason} ->
        Logger.error("Failed to generate size variants for #{original_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Returns the list of S3 keys for a content image path and its size variants.
  """
  @spec variant_keys_for_path(String.t(), [atom()]) :: [String.t()]
  def variant_keys_for_path(path, []), do: [path]

  def variant_keys_for_path(path, sizes) do
    variant_keys =
      Enum.map(sizes, fn size_name ->
        replace_variant_name(path, size_name)
      end)

    [path | variant_keys]
  end

  @doc """
  Deletes a content image and its size variants from S3.
  """
  @spec delete_content_image(String.t(), [atom()]) :: :ok | {:error, term()}
  def delete_content_image(path, sizes) when is_binary(path) do
    path
    |> variant_keys_for_path(sizes)
    |> delete_keys()
  end

  @doc """
  Deletes an article image from S3.
  """
  @spec delete_article_image(String.t()) :: :ok | {:error, term()}
  def delete_article_image(path) when is_binary(path) do
    Logger.info("Attempting to delete article image: #{path} from bucket: #{bucket()}")

    case ExAws.S3.delete_object(bucket(), path) |> S3.request() do
      {:ok, _} ->
        Logger.info("Successfully deleted article image: #{path}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to delete article image: #{path}, reason: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Lists all images in the articles folder on S3.
  """
  @spec list_article_images() :: [map()]
  def list_article_images do
    list_article_images_with_prefix(prefix_path("articles/"))
  end

  @doc """
  Lists images for a specific article by ID.
  """
  @spec list_article_images_for_article(integer()) :: [map()]
  def list_article_images_for_article(article_id) do
    list_article_images_with_prefix(prefix_path("articles/#{article_id}/"))
  end

  defp prefix_path(path) do
    case image_prefix() do
      nil -> path
      "" -> path
      prefix -> "#{prefix}/#{path}"
    end
  end

  defp fetch_original_image(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:fetch_failed, status}}
      {:error, reason} -> {:error, {:fetch_failed, reason}}
    end
  end

  defp spawn_resize_tasks(body, original_path, sizes) do
    Enum.each(sizes, fn {size_name, width} ->
      Gallformers.Async.run(fn -> resize_and_upload(body, original_path, size_name, width) end)
    end)
  end

  defp resize_and_upload(image_data, original_path, size_name, target_width) do
    new_path = replace_variant_name(original_path, size_name)
    format = get_image_format(original_path)
    content_type = format_to_content_type(format)

    with {:ok, img} <- ImageLib.open(image_data),
         {:ok, resized} <- ImageLib.thumbnail(img, target_width),
         {:ok, output_data} <- ImageLib.write(resized, :memory, suffix: ".#{format}"),
         {:ok, _response} <- upload(new_path, output_data, content_type) do
      {:ok, new_path}
    else
      {:error, reason} ->
        Logger.error(
          "Failed to process #{size_name} variant for #{original_path}: #{inspect(reason)}"
        )

        {:error, {:resize_failed, reason}}
    end
  end

  defp get_image_format(path) do
    if String.ends_with?(path, ".png"), do: :png, else: :jpeg
  end

  defp format_to_content_type(:png), do: "image/png"
  defp format_to_content_type(:jpeg), do: "image/jpeg"

  defp replace_variant_name(path, :original), do: path

  defp replace_variant_name(path, size_name) when is_atom(size_name) do
    String.replace(path, "original", Atom.to_string(size_name))
  end

  defp delete_keys(keys) do
    case ExAws.S3.delete_multiple_objects(bucket(), keys) |> S3.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp list_article_images_with_prefix(prefix) do
    case ExAws.S3.list_objects(bucket(), prefix: prefix) |> S3.request() do
      {:ok, %{body: body}} ->
        contents = Map.get(body, :contents) || []
        contents = if is_list(contents), do: contents, else: []

        contents
        |> Enum.filter(&image_file?/1)
        |> Enum.map(&transform_article_s3_object/1)
        |> Enum.sort_by(& &1.last_modified, :desc)

      {:error, reason} ->
        Logger.warning("Failed to list article images: #{inspect(reason)}")
        []
    end
  end

  defp image_file?(obj) do
    String.ends_with?(obj.key, [".jpg", ".jpeg", ".png", ".gif", ".webp"])
  end

  defp transform_article_s3_object(obj) do
    path = obj.key
    parts = String.split(path, "/")
    folder = extract_folder(parts)

    %{
      path: path,
      url: article_image_url(path),
      name: List.last(parts),
      folder: folder,
      article_id: parse_article_id(folder),
      last_modified: obj.last_modified,
      size: obj.size
    }
  end

  defp extract_folder(parts) when length(parts) >= 2, do: Enum.at(parts, 1)
  defp extract_folder(_parts), do: ""

  defp parse_article_id(folder) do
    case Integer.parse(folder) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp bucket do
    Application.get_env(:gallformers, :images)[:bucket]
  end

  defp image_prefix do
    Application.get_env(:gallformers, :s3_image_prefix)
  end
end
