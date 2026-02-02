defmodule Gallformers.Images do
  @moduledoc """
  The Images context.

  Provides functions for managing species images including S3 uploads,
  presigned URLs, image processing, and database operations.
  """

  require Logger

  import Ecto.Query
  alias Gallformers.Licenses
  alias Gallformers.Repo
  alias Gallformers.Species.Image, as: ImageSchema
  alias Gallformers.Species.Species

  # Image processing library (vix-based)
  alias Image, as: ImageLib

  # Image sizes for resizing (width in pixels)
  @sizes %{
    small: 300,
    medium: 800,
    large: 1200,
    xlarge: 2000
  }

  # Accepted MIME types for upload
  @accepted_types ~w(image/jpeg image/png image/jpg)

  @doc """
  Returns the list of accepted MIME types for image upload.
  """
  @spec accepted_types() :: [String.t()]
  def accepted_types, do: @accepted_types

  @doc """
  Returns the CDN base URL for images.
  """
  @spec cdn_url() :: String.t()
  def cdn_url do
    Application.get_env(:gallformers, :images)[:cdn_url]
  end

  @doc """
  Returns the S3 bucket name.
  """
  @spec bucket() :: String.t()
  def bucket do
    Application.get_env(:gallformers, :images)[:bucket]
  end

  @doc """
  Generates the S3 path for an image.

  Format: gall/{species_id}/{species_id}_{timestamp}_original.{ext}
  """
  @spec generate_path(integer(), String.t()) :: String.t()
  def generate_path(species_id, extension) do
    timestamp = System.system_time(:millisecond)
    ext = String.trim_leading(extension, ".")
    "gall/#{species_id}/#{species_id}_#{timestamp}_original.#{ext}"
  end

  @doc """
  Generates a presigned URL for uploading an image to S3.

  Returns {:ok, presigned_url} or {:error, reason}.
  """
  @spec presigned_upload_url(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def presigned_upload_url(path, content_type) do
    expiry = Application.get_env(:gallformers, :images)[:presign_expiry] || 300

    config = ExAws.Config.new(:s3)

    case ExAws.S3.presigned_url(config, :put, bucket(), path,
           expires_in: expiry,
           query_params: [{"Content-Type", content_type}]
         ) do
      {:ok, url} -> {:ok, url}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets all images for a species, ordered by sort_order.
  """
  @spec list_images_for_species(integer()) :: [ImageSchema.t()]
  def list_images_for_species(species_id) do
    from(i in ImageSchema,
      left_join: src in assoc(i, :source),
      where: i.species_id == ^species_id,
      order_by: [asc: i.sort_order, asc: i.id],
      preload: [source: src]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single image by ID.
  """
  @spec get_image(integer()) :: ImageSchema.t() | nil
  def get_image(id) do
    Repo.get(ImageSchema, id) |> Repo.preload(:source)
  end

  @doc """
  Gets a single image by ID, raising if not found.
  """
  @spec get_image!(integer()) :: ImageSchema.t()
  def get_image!(id) do
    Repo.get!(ImageSchema, id) |> Repo.preload(:source)
  end

  @doc """
  Creates a new image record.

  Automatically assigns the next sort_order for the species (appends to end).
  """
  @spec create_image(map()) :: {:ok, ImageSchema.t()} | {:error, Ecto.Changeset.t()}
  def create_image(attrs) do
    attrs = assign_next_sort_order(attrs)

    %ImageSchema{}
    |> image_changeset(attrs)
    |> Repo.insert()
  end

  defp assign_next_sort_order(attrs) do
    species_id = attrs[:species_id] || attrs["species_id"]

    if species_id do
      max_order =
        from(i in ImageSchema,
          where: i.species_id == ^species_id,
          select: max(i.sort_order)
        )
        |> Repo.one() || -1

      Map.put(attrs, :sort_order, max_order + 1)
    else
      attrs
    end
  end

  @doc """
  Updates an image record.
  """
  @spec update_image(ImageSchema.t(), map()) ::
          {:ok, ImageSchema.t()} | {:error, Ecto.Changeset.t()}
  def update_image(%ImageSchema{} = image, attrs) do
    image
    |> image_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Copy metadata from source image to target images.

  Copies: creator, license, licenselink, sourcelink, attribution, caption, source_id
  Updates: lastchangedby on all targets

  Returns {:ok, count} on success, {:error, reason} on failure.
  """
  @spec copy_metadata(integer(), [integer()], String.t()) ::
          {:ok, integer()} | {:error, :source_not_found | term()}
  def copy_metadata(_source_id, [], _updated_by), do: {:ok, 0}

  def copy_metadata(source_id, target_ids, updated_by) when is_list(target_ids) do
    case get_image(source_id) do
      nil ->
        {:error, :source_not_found}

      source ->
        metadata = %{
          creator: source.creator,
          license: source.license,
          licenselink: source.licenselink,
          sourcelink: source.sourcelink,
          attribution: source.attribution,
          caption: source.caption,
          source_id: source.source_id,
          lastchangedby: updated_by
        }

        {count, _} =
          from(i in ImageSchema, where: i.id in ^target_ids)
          |> Repo.update_all(set: Map.to_list(metadata))

        {:ok, count}
    end
  end

  @doc """
  Deletes an image from the database and S3.

  Deletes all size variants (original, small, medium, large, xlarge) from S3.
  """
  @spec delete_image(ImageSchema.t()) :: {:ok, ImageSchema.t()} | {:error, term()}
  def delete_image(%ImageSchema{} = image) do
    # Delete from S3 first
    case delete_image_from_s3(image.path) do
      :ok ->
        Repo.delete(image)

      {:error, reason} ->
        {:error, {:s3_error, reason}}
    end
  end

  @doc """
  Deletes all images from S3 for a species without touching the database.

  Used when cascade deleting a species where the image DB rows will be
  automatically removed by the foreign key constraint. Logs warnings for
  any S3 deletion failures but continues processing all images.

  Returns :ok regardless of individual S3 errors to allow the delete to proceed.
  """
  @spec delete_images_from_s3_for_species(integer()) :: :ok
  def delete_images_from_s3_for_species(species_id) do
    images =
      from(i in ImageSchema, where: i.species_id == ^species_id, select: i.path)
      |> Repo.all()

    Enum.each(images, fn path ->
      case delete_image_from_s3(path) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to delete S3 image #{path}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  @doc """
  Deletes multiple images by IDs for a species.
  """
  @spec delete_images(integer(), [integer()]) :: {:ok, integer()} | {:error, term()}
  def delete_images(species_id, image_ids) when is_list(image_ids) do
    images =
      from(i in ImageSchema,
        where: i.species_id == ^species_id and i.id in ^image_ids
      )
      |> Repo.all()

    # Delete from S3 first
    s3_results =
      images
      |> Enum.map(fn image -> delete_image_from_s3(image.path) end)
      |> Enum.filter(fn result -> result != :ok end)

    if s3_results == [] do
      {count, _} =
        from(i in ImageSchema,
          where: i.species_id == ^species_id and i.id in ^image_ids
        )
        |> Repo.delete_all()

      {:ok, count}
    else
      {:error, {:s3_errors, s3_results}}
    end
  end

  @doc """
  Sets an image as the default for its species.

  The default image is the one with sort_order = 1.
  This reorders all images for the species, moving the target to position 1.
  """
  @spec set_default(ImageSchema.t()) :: {:ok, ImageSchema.t()} | {:error, Ecto.Changeset.t()}
  def set_default(%ImageSchema{} = image) do
    Repo.transaction(fn ->
      # Temporarily set target image to sort_order 0
      from(i in ImageSchema, where: i.id == ^image.id)
      |> Repo.update_all(set: [sort_order: 0])

      # Get all images for this species, ordered by sort_order
      # (target will be first since it's at 0)
      images =
        from(i in ImageSchema,
          where: i.species_id == ^image.species_id,
          order_by: [asc: i.sort_order, asc: i.id]
        )
        |> Repo.all()

      # Renumber all images: target gets 1, others get 2, 3, 4...
      images
      |> Enum.with_index(1)
      |> Enum.each(fn {img, index} ->
        from(i in ImageSchema, where: i.id == ^img.id)
        |> Repo.update_all(set: [sort_order: index])
      end)

      # Return the updated target image
      Repo.get!(ImageSchema, image.id)
    end)
    |> case do
      {:ok, updated} -> {:ok, updated}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Reorders images for a species.

  Takes a list of image IDs in the desired order. Persists the sort_order
  for each image based on its position in the list.
  """
  @spec reorder_images(integer(), [integer()]) :: :ok | {:error, term()}
  def reorder_images(_species_id, ordered_ids) when is_list(ordered_ids) do
    Repo.transaction(fn ->
      # Update sort_order for each image based on position in list
      ordered_ids
      |> Enum.with_index()
      |> Enum.each(fn {image_id, index} ->
        from(i in ImageSchema, where: i.id == ^image_id)
        |> Repo.update_all(set: [sort_order: index])
      end)
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generates image size variants and uploads them to S3.

  This is called after the original image has been uploaded.
  The function downloads the original, resizes it, and uploads
  the variants asynchronously.
  """
  @spec generate_size_variants(String.t()) :: :ok | {:error, term()}
  def generate_size_variants(original_path) do
    original_url = cdn_url() <> "/" <> original_path

    case fetch_original_image(original_url) do
      {:ok, body} ->
        spawn_resize_tasks(body, original_path)
        :ok

      {:error, reason} ->
        Logger.error("Failed to generate size variants for #{original_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_original_image(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:fetch_failed, status}}
      {:error, reason} -> {:error, {:fetch_failed, reason}}
    end
  end

  defp spawn_resize_tasks(body, original_path) do
    Enum.each(@sizes, fn {size_name, width} ->
      Gallformers.Async.run(fn -> resize_and_upload(body, original_path, size_name, width) end)
    end)
  end

  # Private functions

  defp image_changeset(image, attrs) do
    import Ecto.Changeset

    image
    |> cast(attrs, [
      :species_id,
      :source_id,
      :path,
      :sort_order,
      :creator,
      :attribution,
      :license,
      :licenselink,
      :sourcelink,
      :uploader,
      :lastchangedby,
      :caption
    ])
    |> validate_required([:species_id, :path])
  end

  defp delete_image_from_s3(path) when is_binary(path) do
    # Generate all size variant keys
    keys =
      [:original, :small, :medium, :large, :xlarge]
      |> Enum.map(fn size ->
        size_str = Atom.to_string(size)
        String.replace(path, "original", size_str)
      end)

    # Delete all variants - pass keys directly as strings
    case ExAws.S3.delete_multiple_objects(bucket(), keys) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_image_from_s3(_), do: :ok

  defp resize_and_upload(image_data, original_path, size_name, target_width) do
    size_str = Atom.to_string(size_name)
    new_path = String.replace(original_path, "original", size_str)
    format = get_image_format(original_path)
    content_type = format_to_content_type(format)

    with {:ok, img} <- ImageLib.open(image_data),
         {:ok, resized} <- ImageLib.thumbnail(img, target_width),
         {:ok, output_data} <- ImageLib.write(resized, :memory, suffix: ".#{format}"),
         {:ok, _response} <- upload_to_s3(new_path, output_data, content_type) do
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

  defp upload_to_s3(path, data, content_type) do
    ExAws.S3.put_object(bucket(), path, data,
      content_type: content_type
      # Note: No ACL needed - bucket has public read policy
    )
    |> ExAws.request()
  end

  @doc """
  Gets all images for a source, ordered by species name.
  """
  @spec list_images_for_source(integer()) :: [ImageSchema.t()]
  def list_images_for_source(source_id) do
    from(i in ImageSchema,
      join: src in assoc(i, :source),
      left_join: sp in Species,
      on: i.species_id == sp.id,
      where: i.source_id == ^source_id,
      order_by: [asc: sp.name, asc: i.id],
      preload: [source: src]
    )
    |> Repo.all()
  end

  @doc """
  Returns the total count of images in the database.
  """
  @spec count_images() :: integer()
  def count_images do
    from(i in ImageSchema, select: count(i.id))
    |> Repo.one()
  end

  @doc """
  Lists all species that have images, with their image counts.
  """
  @spec list_species_with_images() :: [map()]
  def list_species_with_images do
    from(i in ImageSchema,
      join: s in Species,
      on: i.species_id == s.id,
      group_by: [s.id, s.name],
      select: %{
        species_id: s.id,
        species_name: s.name,
        image_count: count(i.id)
      },
      order_by: s.name
    )
    |> Repo.all()
  end

  @doc """
  Searches for species by name for image management.
  """
  @spec search_species(String.t()) :: [map()]
  def search_species(query) when is_binary(query) do
    search_term = "%#{String.downcase(query)}%"

    from(s in Species,
      left_join: i in ImageSchema,
      on: i.species_id == s.id,
      where: fragment("lower(?) LIKE ?", s.name, ^search_term),
      group_by: [s.id, s.name],
      select: %{
        id: s.id,
        name: s.name,
        image_count: count(i.id)
      },
      order_by: s.name,
      limit: 20
    )
    |> Repo.all()
  end

  # Article Image Functions

  @doc """
  Generates the S3 path for an article image.

  Format: articles/{article_id}/{timestamp}.{ext}

  Uses article ID instead of slug since slugs can change but IDs are stable.
  """
  @spec generate_article_path(integer(), String.t()) :: String.t()
  def generate_article_path(article_id, extension) when is_integer(article_id) do
    timestamp = System.system_time(:millisecond)
    ext = String.trim_leading(extension, ".")
    "articles/#{article_id}/#{timestamp}.#{ext}"
  end

  @doc """
  Returns the full CDN URL for an article image path.
  """
  @spec article_image_url(String.t()) :: String.t()
  def article_image_url(path) do
    "#{cdn_url()}/#{path}"
  end

  @doc """
  Lists all images in the articles folder on S3.

  Returns a list of maps with :path, :url, :name, :folder, and :article_id keys.
  """
  @spec list_article_images() :: [map()]
  def list_article_images do
    list_article_images_with_prefix("articles/")
  end

  @doc """
  Lists images for a specific article by ID.
  """
  @spec list_article_images_for_article(integer()) :: [map()]
  def list_article_images_for_article(article_id) do
    list_article_images_with_prefix("articles/#{article_id}/")
  end

  # Lists images in a specific articles subfolder on S3.
  @spec list_article_images_with_prefix(String.t()) :: [map()]
  defp list_article_images_with_prefix(prefix) do
    case ExAws.S3.list_objects(bucket(), prefix: prefix) |> ExAws.request() do
      {:ok, %{body: body}} ->
        # contents may be missing, nil, or a list depending on S3 response
        contents = Map.get(body, :contents) || []
        contents = if is_list(contents), do: contents, else: []

        contents
        |> Enum.filter(&image_file?/1)
        |> Enum.map(&transform_s3_object/1)
        |> Enum.sort_by(& &1.last_modified, :desc)

      {:error, reason} ->
        Logger.warning("Failed to list article images: #{inspect(reason)}")
        []
    end
  end

  defp image_file?(obj) do
    String.ends_with?(obj.key, [".jpg", ".jpeg", ".png", ".gif", ".webp"])
  end

  defp transform_s3_object(obj) do
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

  @doc """
  Deletes an article image from S3.

  Takes the full S3 path (e.g., "articles/123/1234567890.jpg").
  Returns :ok on success or {:error, reason} on failure.
  """
  @spec delete_article_image(String.t()) :: :ok | {:error, term()}
  def delete_article_image(path) when is_binary(path) do
    Logger.info("Attempting to delete article image: #{path} from bucket: #{bucket()}")

    case ExAws.S3.delete_object(bucket(), path) |> ExAws.request() do
      {:ok, _} ->
        Logger.info("Successfully deleted article image: #{path}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to delete article image: #{path}, reason: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # =============================================================================
  # Image Audit Functions
  # =============================================================================

  @doc """
  Lists all image paths from S3 under the gall/ prefix.

  Returns a list of S3 object maps with :key, :last_modified, and :size.
  This can be slow for large buckets - consider using the AuditCache for cached results.
  """
  @spec list_all_s3_gall_paths() :: {:ok, [map()]} | {:error, term()}
  def list_all_s3_gall_paths do
    if Application.get_env(:gallformers, :s3_enabled, true) do
      list_s3_gall_paths_recursive("gall/", nil, [])
    else
      # Return empty list in test environment to avoid real S3 calls
      {:ok, []}
    end
  end

  defp list_s3_gall_paths_recursive(prefix, continuation_token, acc) do
    opts =
      [prefix: prefix]
      |> maybe_add_continuation_token(continuation_token)

    case ExAws.S3.list_objects_v2(bucket(), opts) |> ExAws.request() do
      {:ok, %{body: body}} ->
        contents = body[:contents] || []
        # Filter to only original images (not size variants)
        new_paths =
          contents
          |> Enum.filter(&original_gall_image?/1)
          |> Enum.map(&extract_s3_object_info/1)

        all_paths = acc ++ new_paths

        # Check for more pages
        if body[:is_truncated] == "true" && body[:next_continuation_token] do
          list_s3_gall_paths_recursive(prefix, body[:next_continuation_token], all_paths)
        else
          {:ok, all_paths}
        end

      {:error, reason} ->
        Logger.error("Failed to list S3 gall paths: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_add_continuation_token(opts, nil), do: opts

  defp maybe_add_continuation_token(opts, token),
    do: Keyword.put(opts, :continuation_token, token)

  defp original_gall_image?(obj) do
    String.contains?(obj[:key], "_original.") && image_extension?(obj[:key])
  end

  defp image_extension?(path) do
    String.ends_with?(path, [".jpg", ".jpeg", ".png", ".gif", ".webp"])
  end

  defp extract_s3_object_info(obj) do
    %{
      key: obj[:key],
      last_modified: obj[:last_modified],
      size: obj[:size]
    }
  end

  @doc """
  Parses the species ID from an S3 gall image path.

  ## Examples

      iex> parse_species_id_from_path("gall/123/123_1234567890_original.jpg")
      {:ok, 123}

      iex> parse_species_id_from_path("gall/abc/image.jpg")
      {:error, :invalid_path}

      iex> parse_species_id_from_path("articles/1/image.jpg")
      {:error, :invalid_path}
  """
  @spec parse_species_id_from_path(String.t()) :: {:ok, integer()} | {:error, :invalid_path}
  def parse_species_id_from_path(path) when is_binary(path) do
    case String.split(path, "/") do
      ["gall", species_id_str | _rest] ->
        case Integer.parse(species_id_str) do
          {id, ""} -> {:ok, id}
          _ -> {:error, :invalid_path}
        end

      _ ->
        {:error, :invalid_path}
    end
  end

  @doc """
  Finds orphan paths from a list of S3 paths.

  An orphan is a path where either:
  1. The species_id parsed from the path doesn't exist in the database
  2. No image record exists with that exact path

  Returns a list of orphan paths with metadata.
  """
  @spec find_orphan_paths([map()]) :: [map()]
  def find_orphan_paths(s3_objects) when is_list(s3_objects) do
    # Get all paths for batch DB query
    paths = Enum.map(s3_objects, & &1.key)

    # Query DB for existing image paths
    existing_paths =
      from(i in ImageSchema, where: i.path in ^paths, select: i.path)
      |> Repo.all()
      |> MapSet.new()

    # Get all valid species IDs
    valid_species_ids =
      from(s in Species, select: s.id)
      |> Repo.all()
      |> MapSet.new()

    # Filter to orphans
    s3_objects
    |> Enum.filter(&orphan?(&1.key, existing_paths, valid_species_ids))
    |> Enum.map(fn obj ->
      species_info = get_species_info(obj.key, valid_species_ids)
      Map.merge(obj, species_info)
    end)
  end

  defp get_species_info(path, valid_species_ids) do
    case parse_species_id_from_path(path) do
      {:ok, id} ->
        %{species_id: id, species_exists: MapSet.member?(valid_species_ids, id)}

      {:error, _} ->
        %{species_id: nil, species_exists: false}
    end
  end

  defp orphan?(path, existing_paths, valid_species_ids) do
    # If path exists in DB, it's not an orphan
    if MapSet.member?(existing_paths, path),
      do: false,
      else: check_species_orphan(path, valid_species_ids)
  end

  defp check_species_orphan(path, valid_species_ids) do
    case parse_species_id_from_path(path) do
      {:ok, species_id} -> !MapSet.member?(valid_species_ids, species_id)
      {:error, _} -> true
    end
  end

  @doc """
  Deletes an orphan image from S3 (not in database).

  Deletes all size variants (original, small, medium, large, xlarge).
  This is for images that exist on S3 but have no database record.
  """
  @spec delete_s3_orphan(String.t()) :: :ok | {:error, term()}
  def delete_s3_orphan(path) when is_binary(path) do
    Logger.info("Deleting S3 orphan image: #{path}")
    delete_image_from_s3(path)
  end

  @doc """
  Creates a database record for an orphan S3 image, assigning it to a species.

  The path must already exist on S3. This creates the database record
  to "adopt" the orphan image.
  """
  @spec create_image_from_orphan(String.t(), integer(), map()) ::
          {:ok, ImageSchema.t()} | {:error, Ecto.Changeset.t()}
  def create_image_from_orphan(path, species_id, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put(:path, path)
      |> Map.put(:species_id, species_id)

    create_image(attrs)
  end

  @doc """
  Checks if a license requires attribution (creator must be specified).

  Public Domain / CC0 does not require attribution.
  All other licenses (CC-BY variants, All Rights Reserved) require attribution.
  """
  @spec requires_attribution?(String.t() | nil) :: boolean()
  def requires_attribution?(nil), do: false
  def requires_attribution?("Public Domain / CC0"), do: false
  def requires_attribution?(license), do: Licenses.valid?(license)

  @doc """
  Checks if an image is properly attributed.

  An image is attributed if:
  1. It has a source with a license, OR
  2. It has sourcelink + license + creator, OR
  3. Its license is Public Domain / CC0 (no attribution required)

  An image is NOT attributed if:
  - License requires attribution but creator is missing
  - No license and no source
  """
  @spec image_attributed?(ImageSchema.t()) :: boolean()
  def image_attributed?(%ImageSchema{} = image) do
    cond do
      # Has source with license - attributed via source
      image.source_id != nil && image.source != nil && image.source.license != nil ->
        true

      # Public domain - no attribution needed
      image.license == "Public Domain / CC0" ->
        true

      # Has license that requires attribution - need creator
      requires_attribution?(image.license) ->
        has_value?(image.creator)

      # No license at all - not attributed
      !has_value?(image.license) ->
        false

      # Fallback - has license, doesn't require attribution
      true ->
        true
    end
  end

  defp has_value?(nil), do: false
  defp has_value?(""), do: false
  defp has_value?(val) when is_binary(val), do: String.trim(val) != ""
  defp has_value?(_), do: false

  @doc """
  Lists images that are not properly attributed.

  Options:
  - :page - page number (default 1)
  - :per_page - items per page (default 50)

  Returns {images, total_count}.
  """
  @spec list_unattributed_images(keyword()) :: {[ImageSchema.t()], integer()}
  def list_unattributed_images(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)
    offset = (page - 1) * per_page

    base_query = unattributed_images_query()

    images =
      base_query
      |> order_by([i, _src, s], asc: s.name, asc: i.id)
      |> limit(^per_page)
      |> offset(^offset)
      |> preload([:source, :species])
      |> Repo.all()

    total = Repo.aggregate(base_query, :count)

    {images, total}
  end

  @doc """
  Returns the count of unattributed images.
  """
  @spec count_unattributed_images() :: integer()
  def count_unattributed_images do
    unattributed_images_query()
    |> Repo.aggregate(:count)
  end

  # Query for images that are not properly attributed.
  # An image is unattributed if:
  # - No source_id AND (no license OR (license requires attribution AND no creator))
  defp unattributed_images_query do
    # Licenses that require attribution (all except CC0)
    attribution_licenses = Licenses.all() -- ["Public Domain / CC0"]

    from(i in ImageSchema,
      left_join: src in assoc(i, :source),
      left_join: s in Species,
      on: i.species_id == s.id,
      # No source with license
      # AND either no license, or license requires attribution but no creator
      where:
        (is_nil(i.source_id) or is_nil(src.license)) and
          (is_nil(i.license) or i.license == "" or
             (i.license in ^attribution_licenses and (is_nil(i.creator) or i.creator == "")))
    )
  end

  @doc """
  Gets an image by ID with species preloaded (for audit display).
  """
  @spec get_image_with_species(integer()) :: ImageSchema.t() | nil
  def get_image_with_species(id) do
    from(i in ImageSchema,
      where: i.id == ^id,
      preload: [:source, :species]
    )
    |> Repo.one()
  end
end
