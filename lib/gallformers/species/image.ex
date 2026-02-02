defmodule Gallformers.Species.Image do
  @moduledoc """
  Ecto schema for the image table.

  Images are associated with species and stored on S3/CloudFront.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour Gallformers.SchemaFields

  @required_fields [:species_id, :path]

  # CloudFront base URL for images
  @image_base_url "https://dhz6u1p7t6okk.cloudfront.net"

  @type t :: %__MODULE__{
          id: integer() | nil,
          species_id: integer() | nil,
          source_id: integer() | nil,
          path: String.t() | nil,
          sort_order: integer(),
          creator: String.t() | nil,
          attribution: String.t() | nil,
          license: String.t() | nil,
          licenselink: String.t() | nil,
          sourcelink: String.t() | nil,
          uploader: String.t() | nil,
          lastchangedby: String.t() | nil,
          caption: String.t() | nil
        }

  schema "image" do
    field :path, :string
    field :sort_order, :integer, default: 0
    field :creator, :string
    field :attribution, :string
    field :license, :string
    field :licenselink, :string
    field :sourcelink, :string
    field :uploader, :string
    field :lastchangedby, :string
    field :caption, :string

    belongs_to :species, Gallformers.Species.Species
    belongs_to :source, Gallformers.Sources.Source
  end

  # Image sizes available on CloudFront
  # Paths in the database use "original", other sizes replace that word
  @type size :: :original | :small | :medium | :large | :xlarge

  @doc """
  Returns the full CloudFront URL for an image.
  """
  @spec url(t()) :: String.t() | nil
  def url(%__MODULE__{path: path}) when is_binary(path) do
    @image_base_url <> "/" <> path
  end

  def url(_), do: nil

  @doc """
  Returns the CloudFront URL for an image at a specific size.

  Image paths in the database contain "original" which gets replaced
  with the size name (small, medium, large, xlarge).
  """
  @spec sized_url(String.t(), size()) :: String.t()
  def sized_url(path, :original) when is_binary(path) do
    @image_base_url <> "/" <> path
  end

  def sized_url(path, size) when is_binary(path) and size in [:small, :medium, :large, :xlarge] do
    sized_path = String.replace(path, "original", Atom.to_string(size))
    @image_base_url <> "/" <> sized_path
  end

  @doc """
  Returns the CloudFront base URL.
  """
  @spec base_url() :: String.t()
  def base_url, do: @image_base_url

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Creates a changeset for an image.

  Note: Attribution validation (checking creator for non-CC0 licenses) is handled
  separately by the Images context since it requires preloaded source data.
  """
  def changeset(image, attrs) do
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
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:species_id)
    |> foreign_key_constraint(:source_id)
  end

  @doc """
  Returns true if this is the default image (sort_order = 1).
  """
  def default?(%__MODULE__{sort_order: 1}), do: true
  def default?(_), do: false
end
