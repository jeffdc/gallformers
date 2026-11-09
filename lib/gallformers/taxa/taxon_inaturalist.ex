defmodule Gallformers.Taxa.TaxonInaturalist do
  @moduledoc """
  A taxon's iNaturalist taxon (`taxon_inaturalist`, audited; matter `e1d2`'s
  mapping, made by `cb28`): one row per taxon, deleted with it. An
  iNaturalist taxon is linked to one of ours at most. Set through
  `Gallformers.Taxa.set_inat/3` (the `{:set_inat, taxon, id}` edit of
  `Gallformers.Import.record_taxonomy_edit/2`). Like `taxon_wcvp`, it holds
  the link only: nothing is read from iNaturalist through it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          taxon_id: integer() | nil,
          inat_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:taxon_id, :id, autogenerate: false}
  schema "taxon_inaturalist" do
    field :inat_id, :integer

    timestamps(type: :utc_datetime)
  end

  @doc "A changeset for the link's iNaturalist ID (a positive integer)."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:inat_id])
    |> validate_required([:inat_id])
    |> validate_number(:inat_id, greater_than: 0)
    |> unique_constraint(:inat_id, message: "is linked to another taxon")
    |> foreign_key_constraint(:taxon_id, name: :taxon_inaturalist_taxon_id_fkey)
  end
end
