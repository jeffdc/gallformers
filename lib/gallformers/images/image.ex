defmodule Gallformers.Images.Image do
  @moduledoc """
  Ecto schema for the image table.

  Images are associated with species and stored on S3/CloudFront.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Gallformers.ChangesetHelpers, only: [trim_strings: 1]

  @behaviour Gallformers.SchemaFields
  alias Gallformers.Storage.Images, as: ImageStorage

  @required_fields [:species_id, :path]

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
          caption: String.t() | nil,
          gall_id: integer() | nil,
          taxon_id: integer() | nil
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
    # The typed reference (a Gall or a taxon, at most one), filled by the
    # catalog data migration beside `species_id`; read-only here.
    field :gall_id, :integer
    field :taxon_id, :integer

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
    ImageStorage.public_url(path)
  end

  def url(_), do: nil

  @doc """
  Returns the CloudFront URL for an image at a specific size.

  Image paths in the database contain "original" which gets replaced
  with the size name (small, medium, large, xlarge).
  """
  @spec sized_url(String.t(), size()) :: String.t()
  def sized_url(path, :original) when is_binary(path) do
    ImageStorage.variant_public_url(path, :original)
  end

  def sized_url(path, size) when is_binary(path) and size in [:small, :medium, :large, :xlarge] do
    ImageStorage.variant_public_url(path, size)
  end

  @doc """
  Returns the CloudFront base URL.
  """
  @spec base_url() :: String.t()
  def base_url, do: ImageStorage.cdn_url()

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
    |> trim_strings()
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
