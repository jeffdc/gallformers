defmodule Gallformers.Facts.AttributionObservation do
  @moduledoc """
  An Observation an attribution cites (`9449` §2): its provider, the
  provider's ID for it, a URL, and for an iNaturalist observation its
  quality grade when cited and a thumbnail (matter `87a1`). Observations
  are evidence, never Sources.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Facts.Attribution

  @type provider :: :inaturalist | :bugguide | :other

  @type t :: %__MODULE__{
          id: integer() | nil,
          attribution_id: integer() | nil,
          provider: provider() | nil,
          external_id: String.t() | nil,
          url: String.t() | nil,
          quality_grade: String.t() | nil,
          thumbnail_url: String.t() | nil
        }

  @content_fields [:provider, :external_id, :url, :quality_grade, :thumbnail_url]
  @grades ~w(research needs_id casual)

  schema "attribution_observations" do
    field :provider, Ecto.Enum, values: [:inaturalist, :bugguide, :other]
    field :external_id, :string
    field :url, :string
    field :quality_grade, :string
    field :thumbnail_url, :string

    belongs_to :attribution, Attribution
  end

  @doc "The fields that make two Observations the same."
  @spec content_fields() :: [atom()]
  def content_fields, do: @content_fields

  @doc "Creates a changeset for a cited Observation."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(observation, attrs) do
    observation
    |> cast(attrs, @content_fields)
    |> validate_required([:provider, :external_id])
    |> validate_inclusion(:quality_grade, @grades)
    |> unique_constraint([:attribution_id, :provider, :external_id])
  end
end
