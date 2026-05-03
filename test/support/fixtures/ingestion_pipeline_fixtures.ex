defmodule Gallformers.IngestionPipelineFixtures do
  @moduledoc false

  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.{DuplicateCandidate, SourceIngestion, SourceIngestionSpecies}

  @spec source_ingestion_fixture(map()) :: SourceIngestion.t()
  def source_ingestion_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          input_type: "pdf",
          status: "processing",
          processing_stage: "submitted"
        },
        attrs
      )

    {:ok, ingestion} = Ingestions.create_source_ingestion(attrs)
    ingestion
  end

  @spec duplicate_candidate_fixture(SourceIngestion.t(), SourceIngestion.t(), map()) ::
          DuplicateCandidate.t()
  def duplicate_candidate_fixture(ingestion, candidate, attrs \\ %{}) do
    {:ok, duplicate_candidate} =
      Ingestions.create_duplicate_candidate(ingestion, candidate, attrs)

    duplicate_candidate
  end

  @spec duplicate_candidate_fixture(SourceIngestion.t(), SourceIngestion.t(), map(), map()) ::
          DuplicateCandidate.t()
  def duplicate_candidate_fixture(ingestion, candidate, evidence, attrs)
      when is_map(evidence) and is_map(attrs) do
    attrs =
      attrs
      |> Map.put_new(:evidence, evidence)

    duplicate_candidate_fixture(ingestion, candidate, attrs)
  end

  @spec review_ready_ingestion_fixture(map()) :: SourceIngestion.t()
  def review_ready_ingestion_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          input_type: "pdf",
          status: "needs_review",
          processing_stage: "review",
          source_id: Map.get(attrs, :source_id)
        },
        attrs
      )

    source_ingestion_fixture(attrs)
  end

  @spec source_ingestion_species_fixture(SourceIngestion.t() | integer(), integer(), map()) ::
          SourceIngestionSpecies.t()
  def source_ingestion_species_fixture(source_ingestion, position, attrs \\ %{})

  def source_ingestion_species_fixture(%SourceIngestion{id: source_ingestion_id}, position, attrs) do
    source_ingestion_species_fixture(source_ingestion_id, position, attrs)
  end

  def source_ingestion_species_fixture(source_ingestion_id, position, attrs)
      when is_integer(source_ingestion_id) and is_integer(position) do
    default_payload = %{
      "hosts" => [%{"name" => "Quercus alba", "evidence" => "On Quercus alba twigs"}],
      "traits" => %{
        "shape" => %{"original" => "globular", "suggested" => ["globular"]},
        "surface" => %{"original" => "woolly", "suggested" => ["woolly"]}
      },
      "description_evidence" => [
        %{"text" => "Rounded woolly gall on oak twigs.", "page" => 3}
      ]
    }

    attrs =
      Map.merge(
        %{
          source_ingestion_id: source_ingestion_id,
          position: position,
          status: "pending",
          extracted_name: "Gall #{position}",
          extracted_authority: "Author",
          description_prose: "Rounded woolly gall on oak twigs.",
          extraction_payload: default_payload
        },
        attrs
      )

    {:ok, source_ingestion_species} =
      Ingestions.create_source_ingestion_species(attrs)

    source_ingestion_species
  end

  @spec ingestion_with_species_entries_fixture(map(), [map()]) :: SourceIngestion.t()
  def ingestion_with_species_entries_fixture(ingestion_attrs \\ %{}, species_attrs_list \\ []) do
    ingestion =
      review_ready_ingestion_fixture(
        Map.merge(
          %{
            source_id: Map.get(ingestion_attrs, :source_id)
          },
          ingestion_attrs
        )
      )

    species_attrs_list
    |> Enum.with_index()
    |> Enum.each(fn {species_attrs, index} ->
      source_ingestion_species_fixture(
        ingestion,
        Map.get(species_attrs, :position, index),
        species_attrs
      )
    end)

    ingestion
  end
end
