defmodule Gallformers.Catalog.LegacyCitation do
  @moduledoc """
  One of today's record-level citations of a Gall (`9449` §6): a
  `species_source` row of any Source but the Gallformers Source, carried
  over by the data migration so the Gall page can show it as today — the
  Source, its narrative (`description`), whether it is the default
  description (`useasdefault`) and the deep link (`externallink`) — until
  the backscan replaces it with attributed Facts. It is not a Fact.

  `legacy_id` is the `species_source` row's ID.
  """
  use Ecto.Schema

  alias Gallformers.Catalog.Gall

  @type t :: %__MODULE__{
          id: integer() | nil,
          gall_id: integer() | nil,
          source_id: integer() | nil,
          description: String.t(),
          useasdefault: boolean(),
          externallink: String.t(),
          legacy_id: integer() | nil
        }

  schema "legacy_citations" do
    # A foreign key to `source`; Sources are known by ID here.
    field :source_id, :integer
    field :description, :string, default: ""
    field :useasdefault, :boolean, default: false
    field :externallink, :string, default: ""
    field :legacy_id, :integer

    belongs_to :gall, Gall
  end
end
