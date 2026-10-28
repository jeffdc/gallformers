defmodule Gallformers.Catalog.Vocab.GenerationGroupTaxon do
  @moduledoc """
  A generation group's mapping to a taxon at any rank. The groups that apply
  to a Gall are those of its Inducer's nearest mapped ancestor (a deeper
  mapping overrides a higher one); if no ancestor is mapped, every group
  mapped below the Inducer's taxon (`8567` *Generation groups*).

  Changed only by a database update. The catalog migration writes them from
  `priv/catalog_migration/generation_group_taxa.csv`
  (`Gallformers.CatalogMigration.GenerationGroupTaxa`; `294c` step 3).
  """
  use Ecto.Schema

  alias Gallformers.Catalog.Vocab.GenerationGroup
  alias Gallformers.Taxa.Taxon

  @type t :: %__MODULE__{
          group_id: integer() | nil,
          taxon_id: integer() | nil,
          group: GenerationGroup.t() | Ecto.Association.NotLoaded.t(),
          taxon: Taxon.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key false
  schema "generation_group_taxa" do
    belongs_to :group, GenerationGroup, primary_key: true
    belongs_to :taxon, Taxon, primary_key: true
  end
end
