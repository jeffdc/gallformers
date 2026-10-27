defmodule Gallformers.Sources.Source do
  @moduledoc """
  Ecto schema for the source table.

  Represents a scientific reference, publication, or citation.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Gallformers.ChangesetHelpers

  @behaviour Gallformers.SchemaFields

  alias Gallformers.Licenses
  alias Gallformers.Sources.PartialDate

  @required_fields [:title, :author, :pubyear, :citation, :license]

  # Today's columns, as the old pages wrote them.
  @citation_fields [
    :title,
    :author,
    :pubyear,
    :link,
    :citation,
    :datacomplete,
    :license,
    :licenselink
  ]

  @kinds [:publication, :website, :database, :unpublished, :research_data, :gallformers]

  @type kind :: :publication | :website | :database | :unpublished | :research_data | :gallformers

  @type t :: %__MODULE__{
          id: integer() | nil,
          title: String.t() | nil,
          author: String.t() | nil,
          pubyear: String.t() | nil,
          link: String.t() | nil,
          citation: String.t() | nil,
          datacomplete: boolean(),
          license: String.t() | nil,
          licenselink: String.t() | nil,
          kind: kind() | nil,
          authors: [String.t()],
          authored_date: Date.t() | nil,
          authored_precision: PartialDate.precision() | nil,
          authored_as_written: String.t() | nil,
          doi: String.t() | nil,
          url: String.t() | nil,
          isbn: String.t() | nil,
          license_value: String.t() | nil,
          license_as_written: String.t() | nil,
          retracted_by_id: integer() | nil,
          retracted_on: Date.t() | nil
        }

  schema "source" do
    # Today's columns, still read and written by the old pages.
    field :title, :string
    field :author, :string
    field :pubyear, :string
    field :link, :string
    field :citation, :string
    field :datacomplete, :boolean, default: false
    field :license, :string
    field :licenselink, :string

    # The new back-end's description of a Source (`9449` §2).
    field :kind, Ecto.Enum, values: @kinds
    field :authors, {:array, :string}, default: []
    field :authored, :string, virtual: true
    field :authored_date, :date
    field :authored_precision, Ecto.Enum, values: [:year, :month, :day]
    field :authored_as_written, :string
    field :doi, :string
    field :url, :string
    field :isbn, :string
    field :license_value, :string
    field :license_as_written, :string
    field :retracted_on, :date

    belongs_to :retracted_by, __MODULE__

    has_many :images, Gallformers.Images.Image

    timestamps(type: :utc_datetime)
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Creates the changeset of the Source editor: today's columns (`title`,
  `author`, `pubyear`, `link`, `citation`, `datacomplete`, `license`,
  `licenselink`) and the new descriptive fields (`details_changeset/2`)
  together.

  Today's rules hold: title, author, year, citation and license are
  required, the year has four digits, links are URLs, titles are unique and
  a CC license needs its link. A license with a canonical, read-only link
  (`Gallformers.Licenses.url_readonly?/1`) gets that link whatever was
  given. `link` may be empty, as on an imported Source that names no URL or
  DOI. The license is one value: `license_value` follows `license`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(source, attrs) do
    source
    |> cast(attrs, @citation_fields)
    |> trim_strings()
    |> put_canonical_license_link()
    |> normalize_empty_strings([:link, :licenselink])
    |> validate_required(@required_fields)
    |> validate_length(:title, min: 1, max: 500)
    |> validate_format(:pubyear, ~r/^[12][0-9]{3}$/, message: "must be a valid 4-digit year")
    |> validate_url(:link)
    |> validate_url(:licenselink)
    |> validate_license_link()
    |> unsafe_validate_unique(:title, Gallformers.Repo,
      message: "a source with this title already exists"
    )
    |> unique_constraint(:title, message: "a source with this title already exists")
    |> then(&details_changeset(&1, Map.drop(attrs, [:license_value, "license_value"])))
    |> trim_strings()
    |> validate_url(:url)
    |> put_license_value()
  end

  @doc """
  Creates a changeset for a Source's new descriptive fields.

  `authored` takes a partial date (`"1897"`, `"1897-05"`, `"1897-05-14"`) and
  sets `authored_date` and `authored_precision` from it.
  """
  @spec details_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def details_changeset(source, attrs) do
    source
    |> cast(attrs, [
      :kind,
      :authors,
      :authored,
      :authored_as_written,
      :doi,
      :url,
      :isbn,
      :license_value,
      :license_as_written
    ])
    |> put_authored()
    |> validate_change(:authors, fn :authors, authors ->
      if Enum.any?(authors, &(String.trim(&1) == "")),
        do: [authors: "must not contain blank names"],
        else: []
    end)
    |> check_constraint(:kind, name: :source_kind_check)
    |> check_constraint(:authored, name: :source_authored_date_precision)
    |> unique_constraint(:kind,
      name: :source_one_gallformers,
      message: "there is already a Gallformers Source"
    )
  end

  @doc """
  Creates a changeset for a Source the importer creates from a package's
  Source block (`Gallformers.Import`): today's columns (`title`, `author`,
  `pubyear`, `link`, `citation`, `license`, `licenselink`) and the new
  descriptive fields together. `link` may be empty (the Source names no URL
  or DOI); the old pages show a link only when it is a valid URL.
  """
  @spec import_changeset(t(), map()) :: Ecto.Changeset.t()
  def import_changeset(source, attrs) do
    source
    |> cast(attrs, [:title, :author, :pubyear, :link, :citation, :license, :licenselink])
    |> trim_strings()
    |> normalize_empty_strings([:link, :licenselink])
    |> validate_required([:title, :author, :pubyear, :citation, :license])
    |> validate_format(:pubyear, ~r/^[12][0-9]{3}$/, message: "must be a valid 4-digit year")
    |> unique_constraint(:title, message: "a source with this title already exists")
    |> then(&details_changeset(&1, attrs))
    |> validate_required([:kind, :authored_date])
  end

  @doc """
  Creates a changeset for a Source Gallformers records itself, such as the
  data migration's "Gallformers legacy data": today's columns, which may be
  empty where they do not apply (`pubyear` for an undated Source), and the
  new descriptive fields. `kind` is required; the authored date is not.
  """
  @spec record_changeset(t(), map()) :: Ecto.Changeset.t()
  def record_changeset(source, attrs) do
    source
    |> cast(attrs, [:title, :author, :pubyear, :link, :citation, :license, :licenselink],
      empty_values: [nil]
    )
    |> trim_strings()
    |> validate_required([:title, :author, :citation])
    |> unique_constraint(:title, message: "a source with this title already exists")
    |> then(&details_changeset(&1, attrs))
    |> validate_required([:kind])
  end

  @doc """
  Creates a changeset marking `source` as retracted by the Source `notice`
  on `retracted_on`.
  """
  @spec retract_changeset(t(), t(), Date.t()) :: Ecto.Changeset.t()
  def retract_changeset(source, %__MODULE__{id: notice_id}, %Date{} = retracted_on) do
    source
    |> change(retracted_by_id: notice_id, retracted_on: retracted_on)
    |> validate_required([:retracted_by_id, :retracted_on])
    |> validate_change(:retracted_by_id, fn :retracted_by_id, id ->
      if id == source.id, do: [retracted_by_id: "cannot be the Source itself"], else: []
    end)
    |> foreign_key_constraint(:retracted_by_id)
    |> check_constraint(:retracted_by_id, name: :source_not_self_retracted)
  end

  @doc """
  Creates a changeset undoing `source`'s retraction: the notice and the date
  are cleared. A Source that is not retracted is an error.
  """
  @spec unretract_changeset(t()) :: Ecto.Changeset.t()
  def unretract_changeset(%__MODULE__{retracted_by_id: nil} = source) do
    source
    |> change()
    |> add_error(:retracted_by_id, "is not retracted")
  end

  def unretract_changeset(%__MODULE__{} = source),
    do: change(source, retracted_by_id: nil, retracted_on: nil)

  @doc """
  The authored date as the partial date it was given (`"1897"`), or nil.
  """
  @spec authored(t()) :: String.t() | nil
  def authored(%__MODULE__{authored_date: %Date{} = date, authored_precision: precision})
      when not is_nil(precision),
      do: PartialDate.format(date, precision)

  def authored(%__MODULE__{}), do: nil

  defp put_authored(changeset) do
    case fetch_change(changeset, :authored) do
      {:ok, partial} ->
        case PartialDate.parse(partial) do
          {:ok, {date, precision}} ->
            change(changeset, authored_date: date, authored_precision: precision)

          :error ->
            add_error(changeset, :authored, "must be YYYY, YYYY-MM or YYYY-MM-DD")
        end

      :error ->
        changeset
    end
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

  defp put_canonical_license_link(changeset) do
    license = get_field(changeset, :license)

    if Licenses.url_readonly?(license),
      do: put_change(changeset, :licenselink, Licenses.url(license)),
      else: changeset
  end

  defp put_license_value(changeset) do
    case get_field(changeset, :license) do
      license when is_binary(license) and license != "" ->
        put_change(changeset, :license_value, license)

      _ ->
        changeset
    end
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
