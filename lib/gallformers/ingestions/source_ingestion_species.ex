defmodule Gallformers.Ingestions.SourceIngestionSpecies do
  @moduledoc """
  Persisted gall-level review item derived from a source ingestion.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Gallformers.ChangesetHelpers, only: [trim_strings: 1, empty_strings_to_nil: 2]

  defmodule ExtractedSpecies do
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
            name: String.t() | nil,
            authority: String.t() | nil,
            family: String.t() | nil,
            order: String.t() | nil
          }

    @primary_key false
    embedded_schema do
      field :name, :string
      field :authority, :string
      field :family, :string
      field :order, :string
    end

    def changeset(extracted_species, attrs) do
      cast(extracted_species, attrs, [:name, :authority, :family, :order])
    end
  end

  defmodule DescriptionEvidence do
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{text: String.t() | nil}

    @primary_key false
    embedded_schema do
      field :text, :string
    end

    def changeset(description_evidence, attrs) do
      cast(description_evidence, attrs, [:text])
    end
  end

  defmodule ExtractedTraitValue do
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
            original: String.t() | nil,
            suggested: [String.t()]
          }

    @primary_key false
    embedded_schema do
      field :original, :string
      field :suggested, {:array, :string}, default: []
    end

    def changeset(extracted_trait_value, attrs) do
      cast(extracted_trait_value, attrs, [:original, :suggested])
    end
  end

  defmodule ExtractedTraits do
    use Ecto.Schema
    import Ecto.Changeset

    @trait_fields ~w(shape color texture walls cells alignment plant_part form season)a

    @type t :: %__MODULE__{
            shape: ExtractedTraitValue.t() | nil,
            color: ExtractedTraitValue.t() | nil,
            texture: ExtractedTraitValue.t() | nil,
            walls: ExtractedTraitValue.t() | nil,
            cells: ExtractedTraitValue.t() | nil,
            alignment: ExtractedTraitValue.t() | nil,
            plant_part: ExtractedTraitValue.t() | nil,
            form: ExtractedTraitValue.t() | nil,
            season: ExtractedTraitValue.t() | nil,
            detachable: String.t() | nil
          }

    @primary_key false
    embedded_schema do
      embeds_one :shape, ExtractedTraitValue, on_replace: :update
      embeds_one :color, ExtractedTraitValue, on_replace: :update
      embeds_one :texture, ExtractedTraitValue, on_replace: :update
      embeds_one :walls, ExtractedTraitValue, on_replace: :update
      embeds_one :cells, ExtractedTraitValue, on_replace: :update
      embeds_one :alignment, ExtractedTraitValue, on_replace: :update
      embeds_one :plant_part, ExtractedTraitValue, on_replace: :update
      embeds_one :form, ExtractedTraitValue, on_replace: :update
      embeds_one :season, ExtractedTraitValue, on_replace: :update
      field :detachable, :string
    end

    def changeset(extracted_traits, attrs) do
      extracted_traits
      |> cast(attrs, [:detachable])
      |> cast_trait_embeds()
    end

    defp cast_trait_embeds(changeset) do
      Enum.reduce(@trait_fields, changeset, fn field, acc ->
        cast_embed(acc, field)
      end)
    end
  end

  defmodule ExtractionPayload do
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
            gall_species: ExtractedSpecies.t() | nil,
            host_species: ExtractedSpecies.t() | nil,
            hosts: [ExtractedSpecies.t()],
            aliases: [String.t()],
            traits: ExtractedTraits.t() | nil,
            description_evidence: [DescriptionEvidence.t()],
            location: String.t() | nil,
            confidence: float() | nil
          }

    @primary_key false
    embedded_schema do
      embeds_one :gall_species, ExtractedSpecies, on_replace: :update
      embeds_one :host_species, ExtractedSpecies, on_replace: :update
      embeds_many :hosts, ExtractedSpecies, on_replace: :delete
      field :aliases, {:array, :string}, default: []
      embeds_one :traits, ExtractedTraits, on_replace: :update
      embeds_many :description_evidence, DescriptionEvidence, on_replace: :delete
      field :location, :string
      field :confidence, :float
    end

    def changeset(extraction_payload, attrs) do
      attrs = normalize_embed_attrs(attrs)

      extraction_payload
      |> cast(attrs, [:aliases, :location, :confidence])
      |> cast_embed(:gall_species)
      |> cast_embed(:host_species)
      |> cast_embed(:hosts)
      |> cast_embed(:traits)
      |> cast_embed(:description_evidence)
    end

    defp normalize_embed_attrs(attrs) do
      attrs
      |> Map.new()
      |> normalize_embed_attr(:gall_species, %{}, &is_map/1)
      |> normalize_embed_attr(:host_species, %{}, &is_map/1)
      |> normalize_embed_attr(:hosts, [], &is_list/1)
      |> normalize_embed_attr(:traits, %{}, &is_map/1)
      |> normalize_embed_attr(:description_evidence, [], &is_list/1)
    end

    defp normalize_embed_attr(attrs, key, fallback, predicate) do
      string_key = Atom.to_string(key)

      cond do
        Map.has_key?(attrs, key) ->
          put_normalized_embed_attr(attrs, key, fallback, predicate)

        Map.has_key?(attrs, string_key) ->
          put_normalized_embed_attr(attrs, string_key, fallback, predicate)

        true ->
          attrs
      end
    end

    defp put_normalized_embed_attr(attrs, key, fallback, predicate) do
      value = Map.get(attrs, key)
      Map.put(attrs, key, if(predicate.(value), do: value, else: fallback))
    end
  end

  defmodule SpeciesReview do
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
            decision: String.t() | nil,
            species_id: integer() | nil,
            family_id: integer() | nil,
            accepted_aliases: [String.t()],
            notes: String.t() | nil
          }

    @primary_key false
    embedded_schema do
      field :decision, :string
      field :species_id, :integer
      field :family_id, :integer
      field :accepted_aliases, {:array, :string}, default: []
      field :notes, :string
    end

    def changeset(species_review, attrs) do
      cast(species_review, attrs, [:decision, :species_id, :family_id, :accepted_aliases, :notes])
    end
  end

  defmodule HostReview do
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
            extracted_name: String.t() | nil,
            extracted_authority: String.t() | nil,
            decision: String.t() | nil,
            species_id: integer() | nil,
            family_id: integer() | nil
          }

    @primary_key false
    embedded_schema do
      field :extracted_name, :string
      field :extracted_authority, :string
      field :decision, :string
      field :species_id, :integer
      field :family_id, :integer
    end

    def changeset(host_review, attrs) do
      cast(host_review, attrs, [
        :extracted_name,
        :extracted_authority,
        :decision,
        :species_id,
        :family_id
      ])
    end
  end

  defmodule TraitReview do
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
            name: String.t() | nil,
            selected_values: [String.t()],
            raw_evidence: [String.t()]
          }

    @primary_key false
    embedded_schema do
      field :name, :string
      field :selected_values, {:array, :string}, default: []
      field :raw_evidence, {:array, :string}, default: []
    end

    def changeset(trait_review, attrs) do
      cast(trait_review, attrs, [:name, :selected_values, :raw_evidence])
    end
  end

  defmodule DescriptionReview do
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{edited: boolean() | nil}

    @primary_key false
    embedded_schema do
      field :edited, :boolean
    end

    def changeset(description_review, attrs) do
      cast(description_review, attrs, [:edited])
    end
  end

  defmodule ReviewPayload do
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
            species_review: SpeciesReview.t() | nil,
            host_reviews: [HostReview.t()],
            trait_reviews: [TraitReview.t()],
            description_review: DescriptionReview.t() | nil
          }

    @primary_key false
    embedded_schema do
      embeds_one :species_review, SpeciesReview, on_replace: :update
      embeds_many :host_reviews, HostReview, on_replace: :delete
      embeds_many :trait_reviews, TraitReview, on_replace: :delete
      embeds_one :description_review, DescriptionReview, on_replace: :update
    end

    def changeset(review_payload, attrs) do
      review_payload
      |> cast(attrs, [])
      |> cast_embed(:species_review)
      |> cast_embed(:host_reviews)
      |> cast_embed(:trait_reviews)
      |> cast_embed(:description_review)
    end
  end

  @statuses ~w(pending mapped created skipped complete)
  @required_fields [:source_ingestion_id, :position, :status]

  @optional_fields [
    :extracted_name,
    :extracted_authority,
    :species_id,
    :description_prose,
    :reviewed_by_id,
    :reviewed_at
  ]

  @type status :: String.t()

  @type t :: %__MODULE__{
          id: integer() | nil,
          source_ingestion_id: integer() | nil,
          position: integer() | nil,
          extracted_name: String.t() | nil,
          extracted_authority: String.t() | nil,
          species_id: integer() | nil,
          status: status(),
          description_prose: String.t(),
          extraction_payload: ExtractionPayload.t() | nil,
          review_payload: ReviewPayload.t() | nil,
          reviewed_by_id: integer() | nil,
          reviewed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "source_ingestion_species" do
    field :position, :integer
    field :extracted_name, :string
    field :extracted_authority, :string
    field :status, :string, default: "pending"
    field :description_prose, :string, default: ""
    embeds_one :extraction_payload, ExtractionPayload, on_replace: :update
    embeds_one :review_payload, ReviewPayload, on_replace: :update
    field :reviewed_at, :utc_datetime

    belongs_to :source_ingestion, Gallformers.Ingestions.SourceIngestion
    belongs_to :species, Gallformers.Species.Species
    belongs_to :reviewed_by, Gallformers.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc """
  Creates a changeset for a gall-level ingestion review item.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(source_ingestion_species, attrs) do
    source_ingestion_species
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> cast_embed(:extraction_payload)
    |> cast_embed(:review_payload)
    |> trim_strings()
    |> empty_strings_to_nil([:extracted_name, :extracted_authority])
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> unique_constraint([:source_ingestion_id, :position],
      name: :source_ingestion_species_unique_position,
      message: "position has already been used for this ingestion"
    )
    |> foreign_key_constraint(:source_ingestion_id)
    |> foreign_key_constraint(:species_id)
    |> foreign_key_constraint(:reviewed_by_id)
  end
end
