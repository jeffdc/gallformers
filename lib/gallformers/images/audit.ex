defmodule Gallformers.Images.Audit do
  @moduledoc """
  Audit functions for detecting and managing orphan S3 images.

  An orphan is an image file that exists on S3 but has no corresponding
  database record. This module provides functions to find, delete, and
  adopt orphan images. Used by the admin image audit interface.
  """

  require Logger

  import Ecto.Query
  alias Gallformers.Images
  alias Gallformers.Images.Image, as: ImageSchema
  alias Gallformers.Repo
  alias Gallformers.Species.Species
  alias Gallformers.Storage

  @doc """
  Lists all image paths from S3 under the gall/ prefix.

  Returns a list of S3 object maps with :key, :last_modified, and :size.
  This can be slow for large buckets - consider using the AuditCache for cached results.
  """
  @spec list_all_s3_gall_paths() :: {:ok, [map()]} | {:error, term()}
  def list_all_s3_gall_paths do
    Storage.list_all_gall_paths()
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

  @doc """
  Deletes an orphan image from S3 (not in database).

  Deletes all size variants (original, small, medium, large, xlarge).
  This is for images that exist on S3 but have no database record.
  """
  @spec delete_s3_orphan(String.t()) :: :ok | {:error, term()}
  def delete_s3_orphan(path) when is_binary(path) do
    Logger.info("Deleting S3 orphan image: #{path}")
    Storage.delete_image(path)
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

    Images.create_image(attrs)
  end

  # Private helpers

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
end
