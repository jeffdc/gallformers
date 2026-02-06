defmodule Gallformers.Images do
  @moduledoc """
  The Images context.

  Provides functions for managing species images including CRUD operations,
  audit functions, and attribution checking. S3 operations are in
  `Gallformers.Storage`.
  """

  require Logger

  import Ecto.Query
  alias Gallformers.Images.Image, as: ImageSchema
  alias Gallformers.Licenses
  alias Gallformers.Repo
  alias Gallformers.Species.Species
  alias Gallformers.Storage

  # Accepted MIME types for upload
  @accepted_types ~w(image/jpeg image/png image/jpg)

  @doc """
  Returns the list of accepted MIME types for image upload.
  """
  @spec accepted_types() :: [String.t()]
  def accepted_types, do: @accepted_types

  # =============================================================================
  # Image CRUD Operations
  # =============================================================================

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
    case Storage.delete_image(image.path) do
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
      case Storage.delete_image(path) do
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
      |> Enum.map(fn image -> Storage.delete_image(image.path) end)
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

  # =============================================================================
  # Query Functions
  # =============================================================================

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

  # =============================================================================
  # Attribution Functions
  # =============================================================================

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
