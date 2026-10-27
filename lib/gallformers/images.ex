defmodule Gallformers.Images do
  @moduledoc """
  The Images context.

  Provides functions for managing the images of Galls and taxa (an image's
  owner, `t:Gallformers.Images.Image.owner/0`): CRUD, ordering and copying
  metadata. Attribution rules are in `Gallformers.Images.Attribution`;
  image-object storage operations are in `Gallformers.Storage.Images`.
  """
  use Boundary,
    deps: [
      Gallformers.Repo,
      Gallformers.ChangesetHelpers,
      Gallformers.SchemaFields,
      Gallformers.Async,
      Gallformers.Licenses,
      Gallformers.Storage
    ],
    exports: :all

  require Logger

  import Ecto.Query
  alias Gallformers.Images.Image, as: ImageSchema
  alias Gallformers.Repo
  alias Gallformers.Storage.Images, as: ImageStorage

  @species_variant_sizes [small: 300, medium: 800, large: 1200, xlarge: 2000]
  @species_variant_names [:original | Keyword.keys(@species_variant_sizes)]

  @doc """
  Returns the configured species image variant sizes.
  """
  @spec species_variant_sizes() :: keyword(pos_integer())
  def species_variant_sizes, do: @species_variant_sizes

  @doc """
  Returns the species image path variants that should be deleted together.
  """
  @spec species_variant_names() :: [ImageSchema.size()]
  def species_variant_names, do: @species_variant_names

  # =============================================================================
  # Image CRUD Operations
  # =============================================================================

  @doc """
  Gets an owner's images (a Gall's or a taxon's), ordered by sort_order.
  """
  @spec list_images(ImageSchema.owner()) :: [ImageSchema.t()]
  def list_images({:gall, id}), do: list_images_for_gall(id)
  def list_images({:taxon, id}), do: list_images_for_taxon(id)

  @doc """
  Gets a Gall's images (by `image.gall_id`, the typed reference the catalog
  data migration fills), ordered by sort_order.
  """
  @spec list_images_for_gall(integer()) :: [ImageSchema.t()]
  def list_images_for_gall(gall_id) when is_integer(gall_id) do
    gall_id |> images_by(:gall_id) |> Repo.all()
  end

  @doc """
  Gets a taxon's images (by `image.taxon_id`, the typed reference the
  catalog data migration fills), ordered by sort_order.
  """
  @spec list_images_for_taxon(integer()) :: [ImageSchema.t()]
  def list_images_for_taxon(taxon_id) when is_integer(taxon_id) do
    taxon_id |> images_by(:taxon_id) |> Repo.all()
  end

  @doc """
  Each Gall's default image ID (its first by sort_order, as
  `list_images_for_gall/1` orders them), by Gall ID, in one query. Galls
  without images are left out.
  """
  @spec default_image_ids_for_galls([integer()]) :: %{integer() => integer()}
  def default_image_ids_for_galls([]), do: %{}

  def default_image_ids_for_galls(gall_ids) when is_list(gall_ids) do
    from(i in ImageSchema,
      where: i.gall_id in ^gall_ids,
      distinct: i.gall_id,
      order_by: [asc: i.gall_id, asc: i.sort_order, asc: i.id],
      select: {i.gall_id, i.id}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp images_by(id, field) do
    from(i in ImageSchema,
      left_join: src in assoc(i, :source),
      where: field(i, ^field) == ^id,
      order_by: [asc: i.sort_order, asc: i.id],
      preload: [source: src]
    )
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
  Creates `owner`'s image record for an uploaded `path` and schedules
  background size variant generation.

  Used by both the presigned-URL upload flow and the iNat import flow.
  `extra_attrs` can include `:creator`, `:license`, `:licenselink`, `:sourcelink`, etc.
  """
  @spec finalize_upload(String.t(), ImageSchema.owner(), String.t(), map()) ::
          {:ok, ImageSchema.t()} | {:error, Ecto.Changeset.t()}
  def finalize_upload(path, owner, uploader, extra_attrs \\ %{}) do
    attrs =
      extra_attrs
      |> Map.merge(ImageSchema.owner_attrs(owner))
      |> Map.merge(%{path: path, uploader: uploader, lastchangedby: uploader})

    case create_image(attrs) do
      {:ok, image} ->
        schedule_size_variants(path)
        {:ok, image}

      error ->
        error
    end
  end

  defp schedule_size_variants(path) do
    # Skip variant generation when S3 is disabled (test environment)
    if Application.get_env(:gallformers, :s3_enabled, true) do
      do_schedule_size_variants(path)
    end
  end

  defp do_schedule_size_variants(path) do
    Gallformers.Async.run(fn ->
      try do
        # Wait for CDN to propagate
        Process.sleep(5000)

        case ImageStorage.generate_size_variants(path, species_variant_sizes()) do
          :ok ->
            Logger.info("Successfully generated size variants for #{path}")

          {:error, reason} ->
            Logger.error("Failed to generate size variants for #{path}: #{inspect(reason)}")
        end
      rescue
        e ->
          Logger.error(
            "Exception generating size variants for #{path}: #{Exception.format(:error, e, __STACKTRACE__)}"
          )
      end
    end)
  end

  @doc """
  Creates a new image record for the owner its attrs name (`gall_id` or
  `taxon_id`, exactly one).

  Automatically assigns the next sort_order among the owner's images
  (appends to end).
  """
  @spec create_image(map()) :: {:ok, ImageSchema.t()} | {:error, Ecto.Changeset.t()}
  def create_image(attrs) do
    changeset = ImageSchema.changeset(%ImageSchema{}, attrs)

    changeset
    |> Ecto.Changeset.put_change(:sort_order, next_sort_order(changeset))
    |> Repo.insert()
  end

  defp next_sort_order(changeset) do
    case owner_filter(changeset) do
      nil ->
        0

      filter ->
        last = from(i in ImageSchema, where: ^filter, select: max(i.sort_order)) |> Repo.one()
        (last || -1) + 1
    end
  end

  defp owner_filter(changeset) do
    case {Ecto.Changeset.get_field(changeset, :gall_id),
          Ecto.Changeset.get_field(changeset, :taxon_id)} do
      {gall_id, nil} when is_integer(gall_id) -> owner_where({:gall, gall_id})
      {nil, taxon_id} when is_integer(taxon_id) -> owner_where({:taxon, taxon_id})
      _ -> nil
    end
  end

  defp owner_where({:gall, id}), do: dynamic([i], i.gall_id == ^id)
  defp owner_where({:taxon, id}), do: dynamic([i], i.taxon_id == ^id)

  @doc """
  Updates an image record.
  """
  @spec update_image(ImageSchema.t(), map()) ::
          {:ok, ImageSchema.t()} | {:error, Ecto.Changeset.t()}
  def update_image(%ImageSchema{} = image, attrs) do
    image
    |> ImageSchema.changeset(attrs)
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
    case ImageStorage.delete_content_image(image.path, species_variant_names()) do
      :ok ->
        Repo.delete(image)

      {:error, reason} ->
        {:error, {:s3_error, reason}}
    end
  end

  @doc """
  Reorders an owner's images.

  Takes a list of image IDs in the desired order. Persists the sort_order
  for each image based on its position in the list; IDs of other owners'
  images are skipped.
  """
  @spec reorder_images(ImageSchema.owner(), [integer()]) :: :ok | {:error, term()}
  def reorder_images(owner, ordered_ids) when is_list(ordered_ids) do
    owned = owner_where(owner)

    Repo.transaction(fn ->
      # Update sort_order for each image based on position in list
      ordered_ids
      |> Enum.with_index()
      |> Enum.each(fn {image_id, index} ->
        from(i in ImageSchema, where: i.id == ^image_id, where: ^owned)
        |> Repo.update_all(set: [sort_order: index])
      end)
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # =============================================================================
  # Query Functions
  # =============================================================================

  @doc """
  Gets all images for a source, ordered by the name of what each shows: its
  Gall's display name or its taxon's accepted name.

  Reads the `galls` and `taxon_names` tables by name: the Catalog and Taxa
  call this context, so it cannot depend on them.
  """
  @spec list_images_for_source(integer()) :: [ImageSchema.t()]
  def list_images_for_source(source_id) do
    from(i in ImageSchema,
      join: src in assoc(i, :source),
      left_join: g in "galls",
      on: g.id == i.gall_id,
      left_join: n in "taxon_names",
      on: n.taxon_id == i.taxon_id and n.status == "accepted",
      where: i.source_id == ^source_id,
      order_by: [
        asc: fragment("COALESCE(?, ?, ?)", g.name_override, g.name, n.name),
        asc: i.id
      ],
      preload: [source: src]
    )
    |> Repo.all()
  end

  @doc """
  Returns the count of images of Galls and taxa (`gall_id` or `taxon_id`
  set); images left on excluded non-galls have neither and are not counted.
  """
  @spec count_images() :: integer()
  def count_images do
    from(i in ImageSchema,
      where: not is_nil(i.gall_id) or not is_nil(i.taxon_id),
      select: count(i.id)
    )
    |> Repo.one()
  end
end
