defmodule Gallformers.Sources.Source do
  @moduledoc """
  Ecto schema for the source table.

  Represents a scientific reference, publication, or citation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour Gallformers.SchemaFields

  alias Gallformers.Licenses

  @required_fields [:title, :author, :pubyear, :link, :citation, :license]

  @type t :: %__MODULE__{
          id: integer() | nil,
          title: String.t() | nil,
          author: String.t() | nil,
          pubyear: String.t() | nil,
          link: String.t() | nil,
          citation: String.t() | nil,
          datacomplete: boolean(),
          license: String.t() | nil,
          licenselink: String.t() | nil
        }

  schema "source" do
    field :title, :string
    field :author, :string
    field :pubyear, :string
    field :link, :string
    field :citation, :string
    field :datacomplete, :boolean, default: false
    field :license, :string
    field :licenselink, :string

    has_many :images, Gallformers.Species.Image
    has_many :species_sources, Gallformers.Species.SpeciesSource

    timestamps(type: :utc_datetime)
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Creates a changeset for a source.
  """
  def changeset(source, attrs) do
    source
    |> cast(attrs, [
      :title,
      :author,
      :pubyear,
      :link,
      :citation,
      :datacomplete,
      :license,
      :licenselink
    ])
    |> normalize_empty_strings([:licenselink])
    |> validate_required(@required_fields)
    |> validate_length(:title, min: 1, max: 500)
    |> validate_format(:pubyear, ~r/^[12][0-9]{3}$/, message: "must be a valid 4-digit year")
    |> validate_license_link()
    |> unsafe_validate_unique(:title, Gallformers.Repo,
      message: "a source with this title already exists"
    )
    |> unique_constraint(:title, message: "a source with this title already exists")
  end

  # Convert nil values to empty strings for NOT NULL columns with DEFAULT ''
  defp normalize_empty_strings(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, cs ->
      case get_field(cs, field) do
        nil -> put_change(cs, field, "")
        _ -> cs
      end
    end)
  end

  defp validate_license_link(changeset) do
    license = get_field(changeset, :license)
    licenselink = get_field(changeset, :licenselink)

    # All CC licenses (except CC0/Public Domain) require attribution via license link
    cc_licenses_requiring_link = [
      "CC-BY",
      "CC-BY-SA",
      "CC-BY-NC",
      "CC-BY-NC-SA",
      "CC-BY-ND",
      "CC-BY-NC-ND"
    ]

    if license in cc_licenses_requiring_link && (is_nil(licenselink) || licenselink == "") do
      add_error(changeset, :licenselink, "is required for CC licenses")
    else
      changeset
    end
  end

  @doc """
  Returns the list of valid license types.
  """
  def license_types, do: Licenses.all()
end
