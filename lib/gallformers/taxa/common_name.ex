defmodule Gallformers.Taxa.CommonName do
  @moduledoc """
  A common name of a taxon's organism (`9449` §3), e.g. "Poplar vagabond
  aphid": today's plant common names, and editorial common names. Held once
  per taxon, ignoring case. (Common names of Galls are gall aliases, owned by
  `Catalog`.)
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Taxa.Taxon

  @type t :: %__MODULE__{
          id: integer() | nil,
          taxon_id: integer() | nil,
          name: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "taxon_common_names" do
    field :name, :string

    belongs_to :taxon, Taxon

    timestamps(type: :utc_datetime)
  end

  @doc "Creates a changeset for a common name."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(common_name, attrs) do
    common_name
    |> cast(attrs, [:taxon_id, :name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:taxon_id, :name])
    |> unique_constraint(:name,
      name: :taxon_common_names_taxon_id_name_index,
      message: "is already a common name of this taxon"
    )
    |> foreign_key_constraint(:taxon_id)
  end
end
