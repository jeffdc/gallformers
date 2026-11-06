defmodule Gallformers.INaturalist.Observation do
  @moduledoc """
  Represents a parsed iNaturalist observation with its photos: when it was
  seen (`observed_on`), where (`place_ids`, the iNat places containing it,
  and `place_guess`, the observer's words), its `description` and its
  observation field values (`field_values`: `%{name, value, taxon_name}`,
  `taxon_name` for a taxon field such as "Host Plant ID").
  """

  alias Gallformers.INaturalist.Photo

  @enforce_keys [:id, :observer_login, :url, :photos]
  defstruct [
    :id,
    :taxon_id,
    :taxon_name,
    :observer_login,
    :observer_name,
    :url,
    :observed_on,
    :place_guess,
    :description,
    place_ids: [],
    field_values: [],
    photos: []
  ]

  @type t :: %__MODULE__{
          id: integer(),
          taxon_id: integer() | nil,
          taxon_name: String.t() | nil,
          observer_login: String.t(),
          observer_name: String.t() | nil,
          url: String.t(),
          observed_on: Date.t() | nil,
          place_guess: String.t() | nil,
          description: String.t() | nil,
          place_ids: [integer()],
          field_values: [
            %{name: String.t() | nil, value: String.t() | nil, taxon_name: String.t() | nil}
          ],
          photos: [Photo.t()]
        }
end
