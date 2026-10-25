defmodule Gallformers.Taxa.TaxonName do
  @moduledoc """
  A scientific name of a taxon (`9449` §3): its one accepted name, or a
  synonym.

    * `normalized_name` — `Gallformers.Taxa.NameNormalizer.normalize/1` of
      `name`, computed here; import resolution matches on it. A taxon holds a
      normalized name once (per `sensu`).
    * `sensu` — for a misapplied name, the usage meant, as written ("O. S.
      non Harris"). Resolution skips such names unless asked for that sensu.
    * `authorship` — null until phase 2.

  Names are not globally unique: homonyms across kingdoms are two taxa with
  the same name.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Taxa.NameNormalizer
  alias Gallformers.Taxa.Taxon

  @type status :: :accepted | :synonym

  @type t :: %__MODULE__{
          id: integer() | nil,
          taxon_id: integer() | nil,
          name: String.t() | nil,
          normalized_name: String.t() | nil,
          status: status() | nil,
          sensu: String.t() | nil,
          authorship: String.t() | nil,
          taxon: Taxon.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "taxon_names" do
    field :name, :string
    field :normalized_name, :string
    field :status, Ecto.Enum, values: [:accepted, :synonym]
    field :sensu, :string
    field :authorship, :string

    belongs_to :taxon, Taxon

    timestamps(type: :utc_datetime)
  end

  @doc "Creates a changeset for a name: `name`, `status`, `sensu`, `authorship`."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(taxon_name, attrs) do
    taxon_name
    |> cast(attrs, [:taxon_id, :name, :status, :sensu, :authorship])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:taxon_id, :name, :status])
    |> put_normalized_name()
    |> unique_constraint(:status,
      name: :taxon_names_one_accepted_index,
      message: "the taxon already has an accepted name"
    )
    |> unique_constraint(:name,
      name: :taxon_names_taxon_id_normalized_name_sensu_index,
      message: "is already a name of this taxon"
    )
    |> foreign_key_constraint(:taxon_id)
  end

  @doc "Changes a name's status (`:accepted` or `:synonym`)."
  @spec status_changeset(t(), status()) :: Ecto.Changeset.t()
  def status_changeset(taxon_name, status) do
    taxon_name
    |> change(status: status)
    |> unique_constraint(:status,
      name: :taxon_names_one_accepted_index,
      message: "the taxon already has an accepted name"
    )
  end

  defp put_normalized_name(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :normalized_name, NameNormalizer.normalize(name))
    end
  end
end
