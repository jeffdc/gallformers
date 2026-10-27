defmodule Gallformers.Images.Image do
  @moduledoc """
  Ecto schema for the image table.

  An image belongs to its owner — a Gall (`gall_id`) or a taxon
  (`taxon_id`), exactly one — and is stored on S3/CloudFront. `species_id`
  is the old-model key of the migrated rows, no longer written.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Gallformers.ChangesetHelpers, only: [trim_strings: 1]

  @behaviour Gallformers.SchemaFields
  alias Gallformers.Storage.Images, as: ImageStorage

  @required_fields [:path]

  @owner_error "must belong to exactly one Gall or taxon"

  @typedoc "What an image shows: a Gall or a taxon, by ID."
  @type owner :: {:gall, integer()} | {:taxon, integer()}

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
    # The owner: a Gall or a taxon, exactly one (`changeset/2`; the database's
    # `image_one_typed_ref` check allows at most one, for the rows left on
    # excluded non-galls).
    field :gall_id, :integer
    field :taxon_id, :integer
    # The old model's key (`species`), kept on the migrated rows; no longer
    # written.
    field :species_id, :integer

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

  Requires exactly one owner (`gall_id` or `taxon_id`).

  Note: Attribution validation (checking creator for non-CC0 licenses) is handled
  separately by the Images context since it requires preloaded source data.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(image, attrs) do
    image
    |> cast(attrs, [
      :gall_id,
      :taxon_id,
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
    |> validate_one_owner()
    |> check_constraint(:gall_id, name: :image_one_typed_ref, message: @owner_error)
    |> foreign_key_constraint(:gall_id)
    |> foreign_key_constraint(:taxon_id)
    |> foreign_key_constraint(:species_id)
    |> foreign_key_constraint(:source_id)
  end

  defp validate_one_owner(changeset) do
    case {get_field(changeset, :gall_id), get_field(changeset, :taxon_id)} do
      {nil, nil} -> add_error(changeset, :gall_id, @owner_error)
      {_gall_id, nil} -> changeset
      {nil, _taxon_id} -> changeset
      {_gall_id, _taxon_id} -> add_error(changeset, :gall_id, @owner_error)
    end
  end

  @doc "The image attrs naming `owner`."
  @spec owner_attrs(owner()) :: %{gall_id: integer()} | %{taxon_id: integer()}
  def owner_attrs({:gall, id}) when is_integer(id), do: %{gall_id: id}
  def owner_attrs({:taxon, id}) when is_integer(id), do: %{taxon_id: id}

  @doc """
  Returns true if this is the default image (sort_order = 1).
  """
  def default?(%__MODULE__{sort_order: 1}), do: true
  def default?(_), do: false
end
