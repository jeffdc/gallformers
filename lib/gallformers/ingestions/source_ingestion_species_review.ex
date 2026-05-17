defmodule Gallformers.Ingestions.SourceIngestionSpeciesReview do
  @moduledoc false

  import Ecto.Changeset, only: [add_error: 3]

  alias Gallformers.Galls
  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.{SourceIngestion, SourceIngestionSpecies}
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Species, as: SpeciesContext
  alias Gallformers.Storage.SourceArtifacts
  alias Gallformers.Taxonomy
  alias Gallformers.Taxonomy.{Genus, Lineage}
  alias Gallformers.Utils

  @source_ingestion_species_workspace_preloads [:species, source_ingestion: [:source]]

  @trait_option_keys %{
    "color" => :colors,
    "shape" => :shapes,
    "texture" => :textures,
    "walls" => :walls,
    "cells" => :cells,
    "alignment" => :alignments,
    "plant_part" => :plant_parts,
    "form" => :forms,
    "season" => :seasons,
    "detachable" => :detachable
  }

  @spec workspace!(integer()) :: map()
  def workspace!(id) when is_integer(id) do
    source_ingestion_species =
      id
      |> Ingestions.get_source_ingestion_species!()
      |> Repo.preload(@source_ingestion_species_workspace_preloads)

    species_review = workspace_species_review(source_ingestion_species)
    host_reviews = workspace_host_reviews(source_ingestion_species)
    trait_reviews = workspace_trait_reviews(source_ingestion_species)

    %{
      id: source_ingestion_species.id,
      source_ingestion_id: source_ingestion_species.source_ingestion_id,
      position: source_ingestion_species.position,
      extracted_name: source_ingestion_species.extracted_name,
      extracted_authority: source_ingestion_species.extracted_authority,
      status: source_ingestion_species.status,
      description_prose: source_ingestion_species.description_prose,
      extracted_aliases: workspace_extracted_aliases(source_ingestion_species),
      description_evidence: workspace_description_evidence(source_ingestion_species),
      species_review: species_review,
      host_reviews: host_reviews,
      trait_reviews: trait_reviews,
      description_review: workspace_description_review(source_ingestion_species)
    }
  end

  @spec full_text(integer()) :: {:ok, String.t()} | {:error, term()}
  def full_text(source_ingestion_id) when is_integer(source_ingestion_id) do
    [
      {:llm_clean, "text.txt"},
      {:preprocess, "text.txt"},
      {:extract, "text.txt"},
      {:assemble, "output.md"}
    ]
    |> Enum.reduce_while({:error, :not_found}, fn {stage, filename}, _acc ->
      case safe_download_review_artifact(source_ingestion_id, stage, filename) do
        {:ok, text} when is_binary(text) and text != "" -> {:halt, {:ok, text}}
        _ -> {:cont, {:error, :not_found}}
      end
    end)
  end

  @spec update_review(SourceIngestionSpecies.t(), map(), integer()) ::
          {:ok, SourceIngestionSpecies.t()} | {:error, Ecto.Changeset.t()}
  def update_review(%SourceIngestionSpecies{} = source_ingestion_species, attrs, reviewed_by_id)
      when is_integer(reviewed_by_id) do
    source_ingestion_species =
      source_ingestion_species
      |> Repo.preload(@source_ingestion_species_workspace_preloads)

    with :ok <- ensure_source_associated_for_review(source_ingestion_species),
         {:ok, normalized_review} <-
           normalize_source_ingestion_species_review(source_ingestion_species, attrs),
         {:ok, status} <-
           review_status_for_update(source_ingestion_species, normalized_review) do
      Repo.transaction(fn ->
        with {:ok, finalized_review} <-
               maybe_apply_completed_review(source_ingestion_species, normalized_review, status),
             {:ok, updated_entry} <-
               Ingestions.transition_source_ingestion_species_status(
                 source_ingestion_species,
                 status,
                 %{
                   species_id: finalized_review.species_id,
                   description_prose: finalized_review.description_prose,
                   review_payload: finalized_review.review_payload,
                   reviewed_by_id: reviewed_by_id
                 }
               ) do
          updated_entry
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, updated_entry} -> {:ok, updated_entry}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp safe_download_review_artifact(source_ingestion_id, stage, filename) do
    SourceArtifacts.download_private_artifact(source_ingestion_id, stage, filename)
  rescue
    CaseClauseError -> {:error, :not_found}
  end

  defp ensure_source_associated_for_review(%SourceIngestionSpecies{
         source_ingestion: %SourceIngestion{source_id: source_id}
       })
       when not is_nil(source_id),
       do: :ok

  defp ensure_source_associated_for_review(%SourceIngestionSpecies{} = source_ingestion_species) do
    {:error,
     source_ingestion_species
     |> SourceIngestionSpecies.changeset(%{})
     |> add_error(:source_ingestion_id, "must be associated with a source before gall review")}
  end

  defp normalize_source_ingestion_species_review(source_ingestion_species, attrs) do
    attrs = Map.new(attrs)

    with {:ok, species_review} <- normalize_workspace_species_review(attrs),
         {:ok, host_reviews} <- normalize_workspace_host_reviews(attrs),
         {:ok, trait_reviews} <-
           normalize_workspace_trait_reviews(source_ingestion_species, attrs),
         {:ok, action} <- normalize_workspace_action(attrs) do
      description_prose =
        attrs
        |> Utils.attr_value(:description_prose)
        |> Utils.normalize_optional_string(source_ingestion_species.description_prose)

      review_payload = %{
        "species_review" => species_review.payload,
        "host_reviews" => Enum.map(host_reviews, & &1.payload),
        "trait_reviews" => trait_reviews.payload,
        "description_review" => %{
          "edited" => description_prose != source_ingestion_species.description_prose
        }
      }

      {:ok,
       %{
         action: action,
         species_id: species_review.species_id,
         description_prose: description_prose,
         review_payload: review_payload
       }}
    end
  end

  defp normalize_workspace_species_review(attrs) do
    species_review_attrs = Utils.nested_value(attrs, :species_review, %{})
    decision = Utils.nested_value(species_review_attrs, :decision, nil)
    species_id = Utils.nested_integer(species_review_attrs, :species_id)
    family_id = Utils.nested_integer(species_review_attrs, :family_id)

    accepted_aliases =
      species_review_attrs
      |> Utils.nested_value(:accepted_aliases, [])
      |> Utils.normalize_string_list()

    notes = Utils.normalize_optional_string(Utils.nested_value(species_review_attrs, :notes, nil))

    cond do
      decision == "mapped" and is_nil(species_id) ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:species_id, "must be selected for a mapped review")}

      decision == "mapped" ->
        {:ok,
         %{
           species_id: species_id,
           payload: %{
             "decision" => "mapped",
             "species_id" => species_id,
             "family_id" => nil,
             "accepted_aliases" => accepted_aliases,
             "notes" => notes
           }
         }}

      decision == "new" ->
        {:ok,
         %{
           species_id: nil,
           payload: %{
             "decision" => "new",
             "species_id" => nil,
             "family_id" => family_id,
             "accepted_aliases" => accepted_aliases,
             "notes" => notes
           }
         }}

      decision == "skip" ->
        {:ok,
         %{
           species_id: nil,
           payload: %{
             "decision" => "skip",
             "species_id" => nil,
             "family_id" => nil,
             "accepted_aliases" => [],
             "notes" => notes
           }
         }}

      true ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:review_payload, "species review decision is required")}
    end
  end

  defp normalize_workspace_host_reviews(attrs) do
    attrs
    |> Utils.nested_value(:host_reviews, %{})
    |> Utils.normalize_indexed_values()
    |> Enum.reduce_while({:ok, []}, fn host_review_attrs, {:ok, acc} ->
      decision = Utils.nested_value(host_review_attrs, :decision, "unresolved")
      species_id = Utils.nested_integer(host_review_attrs, :species_id)

      payload = %{
        "extracted_name" => Utils.nested_value(host_review_attrs, :extracted_name, nil),
        "extracted_authority" => Utils.nested_value(host_review_attrs, :extracted_authority, nil)
      }

      case decision do
        "mapped" when is_nil(species_id) ->
          {:halt,
           {:error,
            %SourceIngestionSpecies{}
            |> SourceIngestionSpecies.changeset(%{})
            |> add_error(:review_payload, "mapped host reviews must select a host species")}}

        "mapped" ->
          {:cont,
           {:ok,
            [
              %{
                payload:
                  Map.merge(payload, %{
                    "decision" => "mapped",
                    "species_id" => species_id
                  })
              }
              | acc
            ]}}

        "skip" ->
          {:cont,
           {:ok,
            [
              %{
                payload:
                  Map.merge(payload, %{
                    "decision" => "skip",
                    "species_id" => nil
                  })
              }
              | acc
            ]}}

        "unresolved" ->
          {:cont,
           {:ok,
            [
              %{
                payload:
                  Map.merge(payload, %{
                    "decision" => "unresolved",
                    "species_id" => nil
                  })
              }
              | acc
            ]}}

        _ ->
          {:halt,
           {:error,
            %SourceIngestionSpecies{}
            |> SourceIngestionSpecies.changeset(%{})
            |> add_error(:review_payload, "host review decision is invalid")}}
      end
    end)
    |> case do
      {:ok, host_reviews} -> {:ok, Enum.reverse(host_reviews)}
      error -> error
    end
  end

  defp normalize_workspace_trait_reviews(source_ingestion_species, attrs) do
    extraction_traits = extraction_traits(source_ingestion_species.extraction_payload)

    payload =
      attrs
      |> Utils.nested_value(:trait_reviews, %{})
      |> normalize_trait_review_values()
      |> Enum.sort_by(fn {name, _trait_review_attrs} -> name end)
      |> Enum.map(fn {name, trait_review_attrs} ->
        selected_values =
          trait_review_attrs
          |> Utils.nested_value(:selected_values, [])
          |> Utils.normalize_string_list()

        %{
          "name" => name,
          "selected_values" => selected_values,
          "raw_evidence" => extract_trait_raw_evidence(Map.get(extraction_traits, name))
        }
      end)

    {:ok, %{payload: payload}}
  end

  defp normalize_workspace_action(attrs) do
    case Utils.attr_value(attrs, :action) do
      "save" ->
        {:ok, "save"}

      "complete" ->
        {:ok, "complete"}

      nil ->
        {:ok, "save"}

      _ ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:status, "review action is invalid")}
    end
  end

  defp review_status_for_update(
         %SourceIngestionSpecies{source_ingestion: %SourceIngestion{source_id: source_id}},
         %{action: "complete", review_payload: review_payload}
       ) do
    host_reviews = Map.get(review_payload, "host_reviews", [])
    species_review = Map.get(review_payload, "species_review", %{})
    description_review = Map.get(review_payload, "description_review", %{})
    species_decision = Map.get(species_review, "decision")
    species_id = Map.get(species_review, "species_id")

    cond do
      is_nil(source_id) ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:status, "cannot mark complete until a source is associated")}

      species_decision == "mapped" and is_nil(species_id) ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:status, "cannot mark complete until the gall is mapped")}

      species_decision not in ["mapped", "new"] ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:status, "cannot mark complete until the gall identity is resolved")}

      Enum.any?(host_reviews, &(Map.get(&1, "decision") not in ["mapped", "skip"])) ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:status, "cannot mark complete while host reviews are unresolved")}

      is_nil(Map.get(description_review, "edited")) ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:status, "cannot mark complete until the description is reviewed")}

      true ->
        {:ok, "complete"}
    end
  end

  defp review_status_for_update(_source_ingestion_species, %{review_payload: review_payload}) do
    case get_in(review_payload, ["species_review", "decision"]) do
      "mapped" ->
        {:ok, "mapped"}

      "new" ->
        {:ok, "pending"}

      "skip" ->
        {:ok, "skipped"}

      _ ->
        {:error,
         %SourceIngestionSpecies{}
         |> SourceIngestionSpecies.changeset(%{})
         |> add_error(:status, "review decision is invalid")}
    end
  end

  defp workspace_species_review(source_ingestion_species) do
    persisted_review =
      Utils.nested_value(source_ingestion_species.review_payload, :species_review, %{})

    decision =
      Utils.nested_value(
        persisted_review,
        :decision,
        if(source_ingestion_species.species_id, do: "mapped")
      )

    species_id =
      Utils.nested_integer(persisted_review, :species_id) || source_ingestion_species.species_id

    %{
      decision: decision,
      species_id: species_id,
      family_id: Utils.nested_integer(persisted_review, :family_id),
      accepted_aliases:
        persisted_review
        |> Utils.nested_value(:accepted_aliases, [])
        |> Utils.normalize_string_list(),
      notes: Utils.nested_value(persisted_review, :notes, nil),
      selected_species: maybe_species_summary(species_id, source_ingestion_species.species)
    }
  end

  defp workspace_host_reviews(source_ingestion_species) do
    persisted_reviews =
      source_ingestion_species.review_payload
      |> Utils.nested_value(:host_reviews, [])
      |> Utils.normalize_indexed_values()

    selected_species =
      persisted_reviews
      |> Enum.map(&Utils.nested_integer(&1, :species_id))
      |> Enum.reject(&is_nil/1)
      |> load_species_summaries()

    source_ingestion_species.extraction_payload
    |> extraction_hosts()
    |> Enum.with_index()
    |> Enum.map(fn {host, index} ->
      persisted_review = matching_host_review(host, persisted_reviews)
      species_id = Utils.nested_integer(persisted_review, :species_id)

      %{
        index: index,
        extracted_name: Utils.nested_value(host, :name, nil),
        extracted_authority: Utils.nested_value(host, :authority, nil),
        decision: Utils.nested_value(persisted_review, :decision, "unresolved"),
        species_id: species_id,
        selected_species: Map.get(selected_species, species_id),
        search_query: "",
        search_results: []
      }
    end)
  end

  defp workspace_trait_reviews(source_ingestion_species) do
    persisted_trait_reviews = review_trait_reviews(source_ingestion_species.review_payload)

    extraction_traits = extraction_traits(source_ingestion_species.extraction_payload)

    extraction_traits
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map(fn name ->
      persisted_trait_review = Map.get(persisted_trait_reviews, name, %{})
      extracted_trait = Map.get(extraction_traits, name)

      %{
        name: name,
        selected_values:
          persisted_trait_review
          |> Utils.nested_value(
            :selected_values,
            extracted_trait_suggested_values(extracted_trait)
          )
          |> Utils.normalize_string_list(),
        suggested_values: extracted_trait_suggested_values(extracted_trait),
        raw_evidence:
          persisted_trait_review
          |> Utils.nested_value(:raw_evidence, extract_trait_raw_evidence(extracted_trait))
      }
    end)
  end

  defp workspace_description_review(source_ingestion_species) do
    persisted_review =
      Utils.nested_value(source_ingestion_species.review_payload, :description_review, %{})

    %{edited: Utils.nested_value(persisted_review, :edited, false)}
  end

  defp workspace_description_evidence(source_ingestion_species) do
    source_ingestion_species.extraction_payload
    |> Utils.nested_value(:description_evidence, [])
    |> Utils.normalize_indexed_values()
    |> Enum.flat_map(fn evidence ->
      case Utils.nested_value(evidence, :text, nil) do
        text when is_binary(text) and text != "" -> [text]
        _ -> []
      end
    end)
  end

  defp workspace_extracted_aliases(source_ingestion_species) do
    source_ingestion_species.extraction_payload
    |> Utils.nested_value(:aliases, [])
    |> Utils.normalize_string_list()
  end

  defp maybe_apply_completed_review(_source_ingestion_species, normalized_review, status)
       when status != "complete" do
    {:ok, normalized_review}
  end

  defp maybe_apply_completed_review(source_ingestion_species, normalized_review, "complete") do
    source_id = source_ingestion_species.source_ingestion.source_id
    species_review = Map.fetch!(normalized_review.review_payload, "species_review")
    decision = Map.get(species_review, "decision")

    accepted_aliases =
      Utils.normalize_string_list(Map.get(species_review, "accepted_aliases", []))

    with {:ok, species_id} <-
           complete_species_identity(
             source_ingestion_species,
             normalized_review.review_payload,
             decision,
             accepted_aliases
           ),
         :ok <-
           upsert_species_source_mapping(
             species_id,
             source_id,
             normalized_review.description_prose
           ) do
      updated_payload =
        normalized_review.review_payload
        |> put_in(["species_review", "species_id"], species_id)

      {:ok,
       normalized_review
       |> Map.put(:species_id, species_id)
       |> Map.put(:review_payload, updated_payload)}
    end
  end

  defp complete_species_identity(
         source_ingestion_species,
         review_payload,
         "mapped",
         accepted_aliases
       ) do
    species_id = get_in(review_payload, ["species_review", "species_id"])

    source_ingestion_species
    |> sync_reviewed_gall(species_id, review_payload, accepted_aliases)
    |> case do
      {:ok, _species} -> {:ok, species_id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp complete_species_identity(
         source_ingestion_species,
         review_payload,
         "new",
         accepted_aliases
       ) do
    source_ingestion_species
    |> create_reviewed_gall(review_payload, accepted_aliases)
    |> case do
      {:ok, species} -> {:ok, species.id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp complete_species_identity(
         _source_ingestion_species,
         _review_payload,
         _decision,
         _aliases
       ) do
    {:error, review_changeset_error(:status, "gall identity is not ready for completion")}
  end

  defp create_reviewed_gall(source_ingestion_species, review_payload, accepted_aliases) do
    extracted_name = source_ingestion_species.extracted_name
    family_id = get_in(review_payload, ["species_review", "family_id"])

    with {:ok, %{taxonomy: taxonomy, parent_id: parent_id}} <-
           resolve_review_taxonomy(extracted_name, family_id, :gall) do
      Galls.create_gall_with_associations(%{
        species_attrs: %{name: extracted_name, taxoncode: "gall"},
        taxonomy: taxonomy,
        parent_id: parent_id,
        hosts: mapped_host_additions(review_payload),
        aliases: alias_payloads(accepted_aliases),
        filter_values: build_filter_values_from_review(review_payload),
        detachable: detachable_from_review(review_payload, "unknown"),
        undescribed: Taxonomy.placeholder_genus?(taxonomy)
      })
    end
  end

  defp sync_reviewed_gall(_source_ingestion_species, species_id, review_payload, accepted_aliases) do
    species = SpeciesContext.get_species!(species_id)
    current_filter_values = Galls.get_gall_filter_values(species_id)
    current_host_ids = current_host_ids(species_id)

    if is_nil(Galls.get_gall_traits(species_id)) do
      {:ok, _traits} = Galls.create_gall_traits(species_id)
    end

    Galls.update_gall_with_associations(species, %{
      species_attrs: %{},
      alias_changes: {new_alias_additions(species, accepted_aliases), MapSet.new()},
      host_changes: {mapped_host_additions(review_payload, current_host_ids), MapSet.new()},
      original_filter_values: current_filter_values,
      filter_values:
        merge_filter_values(
          current_filter_values,
          build_filter_values_from_review(review_payload)
        ),
      detachable: detachable_from_review(review_payload, current_detachable(species_id)),
      undescribed: Galls.undescribed?(species_id)
    })
    |> case do
      {:ok, updated_species} -> {:ok, updated_species}
      {:error, reason} -> {:error, reason}
    end
  end

  defp upsert_species_source_mapping(species_id, source_id, description_prose)
       when is_integer(species_id) and is_integer(source_id) do
    attrs = %{
      species_id: species_id,
      source_id: source_id,
      description: description_prose || ""
    }

    case Sources.get_species_source_by_ids(species_id, source_id) do
      nil ->
        case Sources.create_species_source(attrs) do
          {:ok, _mapping} -> :ok
          {:error, changeset} -> {:error, changeset}
        end

      species_source ->
        case Sources.update_species_source(species_source, attrs) do
          {:ok, _mapping} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  defp resolve_review_taxonomy(name, selected_family_id, family_filter) when is_binary(name) do
    family_ids =
      family_filter
      |> Taxonomy.list_families_for_select()
      |> MapSet.new(fn {_name, family_id} -> family_id end)

    name
    |> Taxonomy.lookup_taxonomy_for_new_species()
    |> Taxonomy.resolve_taxonomy_for_species(family_ids)
    |> finalize_review_taxonomy(selected_family_id)
  end

  defp finalize_review_taxonomy(%{taxonomy: nil}, _selected_family_id) do
    {:error, review_changeset_error(:species_id, "taxonomy could not be resolved for this gall")}
  end

  defp finalize_review_taxonomy(%{possible_families: []} = resolved, nil)
       when resolved.genus_is_new do
    {:error, review_changeset_error(:species_id, "select a family before creating this gall")}
  end

  defp finalize_review_taxonomy(
         %{taxonomy: %Lineage{} = taxonomy, possible_families: [], genus_is_new: true},
         selected_family_id
       )
       when is_integer(selected_family_id) do
    family = Taxonomy.get_family(selected_family_id)

    {:ok,
     %{
       taxonomy: %{taxonomy | family: family},
       parent_id: selected_family_id
     }}
  end

  defp finalize_review_taxonomy(
         %{taxonomy: taxonomy, possible_families: [], family_id: family_id},
         _selected_family_id
       ) do
    {:ok, %{taxonomy: taxonomy, parent_id: family_id}}
  end

  defp finalize_review_taxonomy(%{taxonomy: taxonomy, possible_families: _possible_families}, nil) do
    genus_name = taxonomy.genus && taxonomy.genus.name

    {:error,
     review_changeset_error(
       :species_id,
       "select the family for #{genus_name || "this genus"} before creating the gall"
     )}
  end

  defp finalize_review_taxonomy(
         %{taxonomy: taxonomy, possible_families: possible_families},
         selected_family_id
       ) do
    case Enum.find(possible_families, &(&1.family.id == selected_family_id)) do
      nil ->
        {:error,
         review_changeset_error(:species_id, "selected family is not valid for this genus")}

      selected ->
        {:ok,
         %{
           taxonomy: %Lineage{
             genus: %Genus{id: selected.genus_id, name: taxonomy.genus.name},
             family: selected.family,
             section: selected.section
           },
           parent_id: selected.family.id
         }}
    end
  end

  defp build_filter_values_from_review(review_payload) do
    filter_options = Galls.get_all_filter_options()
    trait_reviews = review_trait_reviews(review_payload)

    @trait_option_keys
    |> Enum.reject(fn {_trait_name, filter_key} -> filter_key == :detachable end)
    |> Enum.reduce(%{}, fn {trait_name, filter_key}, acc ->
      selected_values =
        trait_reviews
        |> Map.get(trait_name, %{})
        |> Utils.nested_value("selected_values", [])
        |> Utils.normalize_string_list()

      options_by_value =
        filter_options
        |> Map.get(filter_key, [])
        |> Map.new(fn option -> {option.field, option} end)

      Map.put(
        acc,
        filter_key,
        Enum.flat_map(selected_values, &filter_option_for_value(options_by_value, &1))
      )
    end)
  end

  defp merge_filter_values(current_filter_values, reviewed_filter_values) do
    Map.merge(current_filter_values, reviewed_filter_values, fn _key, current, reviewed ->
      (current ++ reviewed)
      |> Enum.uniq_by(& &1.id)
    end)
  end

  defp current_host_ids(species_id) do
    species_id
    |> Galls.get_hosts_for_gall()
    |> Map.new(&{&1.host_species_id, true})
  end

  defp mapped_host_additions(review_payload, existing_host_ids \\ %{}) do
    review_payload
    |> Map.get("host_reviews", [])
    |> Enum.flat_map(fn host_review ->
      case {Map.get(host_review, "decision"), Map.get(host_review, "species_id")} do
        {"mapped", species_id} when is_integer(species_id) ->
          maybe_mapped_host_addition(existing_host_ids, species_id)

        _ ->
          []
      end
    end)
  end

  defp filter_option_for_value(options_by_value, value) do
    case Map.get(options_by_value, value) do
      nil -> []
      option -> [option]
    end
  end

  defp maybe_mapped_host_addition(existing_host_ids, species_id) do
    if Map.has_key?(existing_host_ids, species_id) do
      []
    else
      [%{host_species_id: species_id}]
    end
  end

  defp current_detachable(species_id) do
    case Galls.get_gall_traits(species_id) do
      %{detachable: detachable} when detachable in ~w(unknown integral detachable both) ->
        detachable

      _ ->
        "unknown"
    end
  end

  defp detachable_from_review(review_payload, fallback) do
    review_payload
    |> review_trait_reviews()
    |> Map.get("detachable", %{})
    |> Utils.nested_value("selected_values", [])
    |> Utils.normalize_string_list()
    |> case do
      [value | _] -> value
      [] -> fallback
    end
  end

  defp new_alias_additions(species, accepted_aliases) do
    existing_alias_names =
      species.id
      |> SpeciesContext.get_aliases_for_species()
      |> Enum.map(&String.downcase(&1.name || ""))
      |> MapSet.new()
      |> MapSet.put(String.downcase(species.name || ""))

    accepted_aliases
    |> Enum.reject(&MapSet.member?(existing_alias_names, String.downcase(&1)))
    |> alias_payloads()
  end

  defp alias_payloads(alias_names) do
    alias_names
    |> Utils.normalize_string_list()
    |> Enum.map(&%{name: &1, type: "scientific"})
  end

  defp review_changeset_error(field, message) do
    %SourceIngestionSpecies{}
    |> SourceIngestionSpecies.changeset(%{})
    |> add_error(field, message)
  end

  defp matching_host_review(host, persisted_reviews) do
    Enum.find(persisted_reviews, %{}, fn persisted_review ->
      Utils.nested_value(persisted_review, :extracted_name, nil) ==
        Utils.nested_value(host, :name, nil) and
        Utils.nested_value(persisted_review, :extracted_authority, nil) ==
          Utils.nested_value(host, :authority, nil)
    end)
  end

  defp maybe_species_summary(nil, _species), do: nil

  defp maybe_species_summary(species_id, nil) do
    species_id
    |> SpeciesContext.get_species()
    |> species_summary()
  end

  defp maybe_species_summary(_species_id, species), do: species_summary(species)

  defp load_species_summaries([]), do: %{}

  defp load_species_summaries(species_ids) do
    species_ids
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn species_id, acc ->
      case SpeciesContext.get_species(species_id) do
        nil -> acc
        species -> Map.put(acc, species_id, species_summary(species))
      end
    end)
  end

  defp species_summary(nil), do: nil

  defp species_summary(species) do
    %{
      id: species.id,
      name: species.name,
      taxoncode: species.taxoncode
    }
  end

  defp extraction_hosts(extraction_payload) do
    case Utils.nested_value(extraction_payload, :hosts, []) do
      hosts when is_list(hosts) -> hosts
      _ -> []
    end
  end

  defp extraction_traits(extraction_payload) do
    case Utils.nested_value(extraction_payload, :traits, %{}) do
      %SourceIngestionSpecies.ExtractedTraits{} = traits ->
        extracted_traits_to_map(traits)

      traits when is_map(traits) ->
        traits

      _ ->
        %{}
    end
  end

  defp extracted_traits_to_map(%SourceIngestionSpecies.ExtractedTraits{} = traits) do
    traits
    |> Map.from_struct()
    |> Enum.reject(fn {key, value} -> key in [:__meta__, :__struct__] or is_nil(value) end)
    |> Map.new(fn
      {key, %SourceIngestionSpecies.ExtractedTraitValue{} = value} ->
        {Atom.to_string(key),
         %{
           "original" => value.original,
           "suggested" => List.wrap(value.suggested)
         }}

      {key, value} ->
        {Atom.to_string(key), value}
    end)
  end

  defp review_trait_reviews(%SourceIngestionSpecies.ReviewPayload{} = review_payload) do
    review_payload
    |> Map.get(:trait_reviews, [])
    |> Enum.reduce(%{}, fn trait_review, acc ->
      Map.put(acc, trait_review.name, %{
        "selected_values" => List.wrap(trait_review.selected_values),
        "raw_evidence" => List.wrap(trait_review.raw_evidence)
      })
    end)
  end

  defp review_trait_reviews(review_payload) when is_map(review_payload) do
    case Utils.nested_value(review_payload, :trait_reviews, %{}) do
      reviews when is_list(reviews) ->
        Enum.reduce(reviews, %{}, &merge_review_trait(&1, &2))

      reviews when is_map(reviews) ->
        reviews

      _ ->
        %{}
    end
  end

  defp review_trait_reviews(_review_payload), do: %{}

  defp merge_review_trait(review, acc) do
    case Utils.nested_value(review, :name, nil) do
      name when is_binary(name) and name != "" ->
        Map.put(acc, name, %{
          "selected_values" =>
            review
            |> Utils.nested_value(:selected_values, [])
            |> Utils.normalize_string_list(),
          "raw_evidence" =>
            review
            |> Utils.nested_value(:raw_evidence, [])
            |> Utils.normalize_string_list()
        })

      _ ->
        acc
    end
  end

  defp extracted_trait_suggested_values(nil), do: []

  defp extracted_trait_suggested_values(extracted_trait) do
    extracted_trait
    |> Utils.nested_value(:suggested, [])
    |> Utils.normalize_string_list()
  end

  defp extract_trait_raw_evidence(nil), do: []

  defp extract_trait_raw_evidence(extracted_trait) do
    case extracted_trait do
      trait when is_map(trait) ->
        originals = Utils.nested_value(trait, :originals, nil)

        cond do
          is_list(originals) ->
            Utils.normalize_string_list(originals)

          is_binary(Utils.nested_value(trait, :original, nil)) ->
            [Utils.nested_value(trait, :original, nil)]

          true ->
            []
        end

      _ ->
        []
    end
  end

  defp normalize_trait_review_values(trait_reviews) when is_map(trait_reviews) do
    trait_reviews
    |> Enum.map(fn {name, value} -> {to_string(name), value} end)
    |> Enum.filter(fn {name, _} -> Map.has_key?(@trait_option_keys, name) end)
    |> Map.new()
  end

  defp normalize_trait_review_values(_), do: %{}
end
