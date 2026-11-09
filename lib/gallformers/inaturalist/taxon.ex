defmodule Gallformers.INaturalist.Taxon do
  @moduledoc """
  A taxon as iNaturalist has it (`Gallformers.INaturalist.Taxa.fetch/1`):

    * `id`, `name`, `rank` (iNaturalist's: `"section"`, `"complex"`,
      `"zoosection"`…), `rank_level`;
    * `active?`, and for an inactive taxon `replaced_by`, the iNaturalist
      IDs of the taxa that replaced it;
    * `common` (iNaturalist's preferred English common name), `observations`;
    * `kingdom` (its first ancestor's name: `"Plantae"`, `"Animalia"`…);
    * `ancestors`, highest first, and `children`, each
      `%{id, name, rank, active?}`;
    * `names`: every name iNaturalist files under it, `%{name, lexicon}`
      (`"scientific-names"`, `"english"`, …);
    * `url`, its iNaturalist page.
  """

  @type relative :: %{
          id: integer(),
          name: String.t(),
          rank: String.t(),
          active?: boolean()
        }

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          rank: String.t(),
          rank_level: number() | nil,
          active?: boolean(),
          replaced_by: [integer()],
          common: String.t() | nil,
          observations: non_neg_integer(),
          kingdom: String.t() | nil,
          ancestors: [relative()],
          children: [relative()],
          names: [%{name: String.t(), lexicon: String.t()}],
          url: String.t()
        }

  @enforce_keys [:id, :name, :rank]
  defstruct [
    :id,
    :name,
    :rank,
    :rank_level,
    :common,
    :kingdom,
    :url,
    active?: true,
    replaced_by: [],
    observations: 0,
    ancestors: [],
    children: [],
    names: []
  ]
end
