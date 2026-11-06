defmodule Gallformers.Taxa.TaxonRedirect do
  @moduledoc """
  A plant merged into another (matter `ec2c`, "Plant merges"): its old ID
  (`from_taxon_id`) now names `taxon_id`, so its old URLs and outside
  references keep working (`Gallformers.Taxa.taxon_redirect/1`). It goes
  with the taxon it points to; a merge of that taxon re-points it.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{
          from_taxon_id: integer() | nil,
          taxon_id: integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key {:from_taxon_id, :id, autogenerate: false}
  schema "taxon_redirects" do
    field :taxon_id, :integer

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
