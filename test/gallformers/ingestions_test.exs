defmodule Gallformers.IngestionsTest do
  use Gallformers.DataCase, async: false

  alias Gallformers.Accounts
  alias Gallformers.Ingestions
  alias Gallformers.Sources
  alias Gallformers.Species.Species
  alias Gallformers.Storage.SourceArtifacts
  alias Gallformers.Taxonomy
  alias GallformersWeb.Admin.IngestionReviewLive.Presenter

  defmodule SubmissionStorageBackendStub do
    @behaviour Gallformers.Storage.SourceArtifacts.Backend

    @impl true
    def upload(bucket, path, content, content_type) do
      send(test_pid(), {:upload, bucket, path, content, content_type})

      case Process.get(:submission_storage_upload_result, {:ok, %{}}) do
        {:ok, _response} = ok ->
          objects = Process.get(:submission_storage_objects, %{})
          Process.put(:submission_storage_objects, Map.put(objects, path, %{body: content}))
          ok

        {:error, _reason} = error ->
          error
      end
    end

    @impl true
    def get_object(bucket, path) do
      send(test_pid(), {:get_object, bucket, path})

      case Process.get(:submission_storage_objects, %{}) do
        %{^path => %{body: body}} -> {:ok, %{body: body}}
        _ -> {:error, :not_found}
      end
    end

    @impl true
    def list_objects(bucket, prefix, continuation_token) do
      send(test_pid(), {:list_objects, bucket, prefix, continuation_token})

      keys =
        Process.get(:submission_storage_objects, %{})
        |> Map.keys()
        |> Enum.filter(&String.starts_with?(&1, prefix))
        |> Enum.sort()

      {:ok, %{keys: keys, next_continuation_token: nil}}
    end

    @impl true
    def delete_objects(bucket, keys) do
      send(test_pid(), {:delete_objects, bucket, keys})

      objects =
        Process.get(:submission_storage_objects, %{})
        |> Map.drop(keys)

      Process.put(:submission_storage_objects, objects)

      Process.get(:submission_storage_delete_result, {:ok, %{}})
    end

    @impl true
    def copy_object(_dest_bucket, _dest_path, _src_bucket, _src_path), do: {:ok, %{}}

    defp test_pid, do: Process.get(:ingestions_test_pid, self())
  end

  setup do
    previous_storage_config = Application.get_env(:gallformers, SourceArtifacts)

    Process.put(:ingestions_test_pid, self())
    Process.put(:submission_storage_objects, %{})

    Application.put_env(:gallformers, SourceArtifacts, backend: SubmissionStorageBackendStub)

    on_exit(fn ->
      Process.delete(:ingestions_test_pid)
      Process.delete(:submission_storage_objects)
      Process.delete(:submission_storage_upload_result)
      Process.delete(:submission_storage_delete_result)

      if previous_storage_config == nil do
        Application.delete_env(:gallformers, SourceArtifacts)
      else
        Application.put_env(:gallformers, SourceArtifacts, previous_storage_config)
      end
    end)

    :ok
  end

  describe "create_source_ingestion/1" do
    test "creates a submission with a canonical per-ingestion artifacts path" do
      user = user_fixture()

      assert {:ok, ingestion} =
               Ingestions.create_source_ingestion(%{
                 input_type: "pdf",
                 uploaded_by_id: user.id,
                 title: "A New Gall Paper",
                 authors: ["A. Author", "B. Author"]
               })

      assert ingestion.status == "processing"
      assert ingestion.processing_stage == "submitted"
      assert ingestion.uploaded_by_id == user.id
      assert ingestion.artifacts_path == SourceArtifacts.private_artifact_prefix(ingestion.id)
    end

    test "rejects invalid input types" do
      assert {:error, changeset} = Ingestions.create_source_ingestion(%{input_type: "epub"})

      assert %{input_type: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "delete_failed_source_ingestion/1" do
    test "deletes failed ingestions and their persisted artifacts" do
      user = user_fixture()

      ingestion =
        source_ingestion_fixture(%{
          input_type: "pdf",
          uploaded_by_id: user.id,
          status: "failed",
          processing_stage: "failed",
          error_stage: "upload"
        })

      artifact_path = "source-ingestions/#{ingestion.id}/input/source.pdf"

      Process.put(:submission_storage_objects, %{
        artifact_path => %{body: "%PDF-1.4 failed\n"}
      })

      assert {:ok, deleted_ingestion} = Ingestions.delete_failed_source_ingestion(ingestion.id)

      assert deleted_ingestion.id == ingestion.id
      assert_received {:delete_objects, _, [^artifact_path]}
      assert Ingestions.get_source_ingestion(ingestion.id) == nil
      assert Process.get(:submission_storage_objects) == %{}
    end

    test "rejects clearing an ingestion that is not failed" do
      ingestion =
        source_ingestion_fixture(%{
          input_type: "url",
          status: "needs_review",
          processing_stage: "review"
        })

      assert {:error, changeset} = Ingestions.delete_failed_source_ingestion(ingestion)

      assert %{status: ["only failed or abandoned ingestions can be cleared"]} =
               errors_on(changeset)

      assert Ingestions.get_source_ingestion(ingestion.id).id == ingestion.id
    end

    test "returns artifact cleanup errors without deleting the ingestion" do
      ingestion =
        source_ingestion_fixture(%{
          input_type: "text",
          status: "failed",
          processing_stage: "failed",
          error_stage: "upload"
        })

      artifact_path = "source-ingestions/#{ingestion.id}/input/source.txt"

      Process.put(:submission_storage_objects, %{
        artifact_path => %{body: "failed text"}
      })

      Process.put(:submission_storage_delete_result, {:error, :s3_down})

      assert {:error, :s3_down} = Ingestions.delete_failed_source_ingestion(ingestion.id)
      assert Ingestions.get_source_ingestion(ingestion.id).id == ingestion.id
    end

    test "clears any ingestion stuck in processing as abandoned" do
      ingestion =
        source_ingestion_fixture(%{
          input_type: "text",
          status: "processing",
          processing_stage: "metadata"
        })

      artifact_path = "source-ingestions/#{ingestion.id}/input/source.txt"

      Process.put(:submission_storage_objects, %{
        artifact_path => %{body: "abandoned text"}
      })

      assert Ingestions.source_ingestion_clearability(ingestion.id) == :abandoned
      assert {:ok, deleted_ingestion} = Ingestions.clear_source_ingestion(ingestion.id)

      assert deleted_ingestion.id == ingestion.id
      assert_received {:delete_objects, _, [^artifact_path]}
      assert Ingestions.get_source_ingestion(ingestion.id) == nil
      assert Process.get(:submission_storage_objects) == %{}
    end
  end

  describe "source association and gall-level review" do
    test "keeps species review locked until a source is associated and supports item status transitions" do
      reviewer = user_fixture()
      source = source_fixture()

      ingestion =
        source_ingestion_fixture(%{
          input_type: "pdf",
          status: "needs_review",
          processing_stage: "review"
        })

      refute Ingestions.species_review_unlocked?(ingestion)

      assert {:ok, ingestion} = Ingestions.associate_source(ingestion, source)
      assert Ingestions.species_review_unlocked?(ingestion) == true

      species = species_fixture("Andricus testus")

      assert {:ok, source_ingestion_species} =
               Ingestions.create_source_ingestion_species(%{
                 source_ingestion_id: ingestion.id,
                 position: 0,
                 extracted_name: "Andricus testus",
                 extracted_authority: "Author",
                 description_prose: "Globular leaf gall with a woolly surface.",
                 extraction_payload: %{
                   "hosts" => [%{"name" => "Quercus alba"}],
                   "traits" => %{
                     "shape" => %{"original" => "globular", "suggested" => ["globular"]}
                   }
                 }
               })

      refute Ingestions.all_species_entries_resolved?(ingestion)

      assert {:ok, updated_item} =
               Ingestions.transition_source_ingestion_species_status(
                 source_ingestion_species,
                 :mapped,
                 %{
                   species_id: species.id,
                   reviewed_by_id: reviewer.id
                 }
               )

      assert updated_item.status == "mapped"
      assert updated_item.species_id == species.id
      assert updated_item.reviewed_by_id == reviewer.id
      refute is_nil(updated_item.reviewed_at)
      assert Ingestions.all_species_entries_resolved?(ingestion) == true
    end
  end

  describe "raw_extraction round-trip" do
    test "preserves full Python record map through insert + reload" do
      ingestion =
        source_ingestion_fixture(%{
          input_type: "pdf",
          status: "needs_review",
          processing_stage: "review"
        })

      raw = %{
        "record_id" => "R_001",
        "candidate_id" => "C_001",
        "gall_maker" => %{
          "scientific_name" => %{
            "value" => "Druon flocculentum",
            "confidence" => 1.0,
            "evidence" => [
              %{"block_id" => "S_0145", "page" => 1, "char_start" => 0, "char_end" => 18}
            ]
          }
        },
        "confidence_bucket" => "high",
        "warnings" => []
      }

      assert {:ok, entry} =
               Ingestions.create_source_ingestion_species(%{
                 source_ingestion_id: ingestion.id,
                 position: 0,
                 raw_extraction: raw
               })

      reloaded = Ingestions.get_source_ingestion_species!(entry.id)
      assert reloaded.raw_extraction == raw
    end
  end

  describe "ensure_source_ingestion_species_entries/2" do
    test "collates repeated extracted records into a single species-level entry" do
      ingestion =
        source_ingestion_fixture(%{
          input_type: "pdf",
          status: "needs_review",
          processing_stage: "review"
        })

      records = [
        %{
          gall_species: %{name: "Andricus collatus", authority: "Author"},
          host_species: %{name: "Quercus alba", authority: "L."},
          traits: %{"shape" => %{"original" => "globular", "suggested" => ["globular"]}},
          description: "Rounded gall on oak twigs."
        },
        %{
          gall_species: %{name: "Andricus collatus", authority: "Author"},
          host_species: %{name: "Quercus stellata", authority: "Wangenh."},
          traits: %{"shape" => %{"original" => "ovoid", "suggested" => ["globular", "oval"]}},
          description: "Later mention with additional host evidence."
        }
      ]

      assert {:ok, [entry]} =
               Ingestions.ensure_source_ingestion_species_entries(ingestion, records)

      assert entry.extracted_name == "Andricus collatus"
      assert entry.position == 0
      assert entry.description_prose =~ "Rounded gall on oak twigs."
      assert entry.description_prose =~ "Later mention with additional host evidence."

      hosts = Enum.map(entry.extraction_payload.hosts, & &1.name)
      assert hosts == ["Quercus alba", "Quercus stellata"]

      assert entry.extraction_payload.traits.shape.original =~ "globular"
      assert entry.extraction_payload.traits.shape.original =~ "ovoid"
      assert entry.extraction_payload.traits.shape.suggested == ["globular", "oval"]
      assert length(entry.extraction_payload.description_evidence) == 2
    end
  end

  describe "update_source_ingestion_species_review/3" do
    test "persists a complete review payload and updates the entry status" do
      reviewer = user_fixture()
      source = source_fixture()
      mapped_gall = species_fixture("Andricus reviewed", "gall")
      mapped_host = species_fixture("Quercus workspace", "plant")

      ingestion =
        source_ingestion_fixture(%{
          input_type: "pdf",
          status: "needs_review",
          processing_stage: "review",
          source_id: source.id
        })

      species_entry =
        create_species_entry(ingestion, 0, %{
          extraction_payload: %{
            "hosts" => [%{"name" => "Quercus alba"}],
            "traits" => %{
              "shape" => %{"original" => "globular", "suggested" => ["globular"]}
            },
            "description_evidence" => [%{"text" => "Rounded woody gall on oak twigs."}]
          }
        })

      assert {:ok, updated_entry} =
               Ingestions.update_source_ingestion_species_review(
                 species_entry,
                 %{
                   action: "complete",
                   description_prose: "Edited woody gall description.",
                   species_review: %{
                     decision: "mapped",
                     species_id: mapped_gall.id,
                     notes: "Reviewed against the persisted gall species."
                   },
                   host_reviews: %{
                     "0" => %{
                       extracted_name: "Quercus alba",
                       decision: "mapped",
                       species_id: mapped_host.id
                     }
                   },
                   trait_reviews: %{
                     "shape" => %{selected_values: ["globular", "oval"]}
                   }
                 },
                 reviewer.id
               )

      assert updated_entry.status == "complete"
      assert updated_entry.species_id == mapped_gall.id
      assert updated_entry.reviewed_by_id == reviewer.id
      assert updated_entry.description_prose == "Edited woody gall description."
      assert updated_entry.review_payload.species_review.decision == "mapped"
      assert updated_entry.review_payload.species_review.species_id == mapped_gall.id

      [host_review] = updated_entry.review_payload.host_reviews
      assert host_review.decision == "mapped"
      assert host_review.species_id == mapped_host.id

      trait_review =
        Enum.find(updated_entry.review_payload.trait_reviews, &(&1.name == "shape"))

      assert trait_review.selected_values == ["globular", "oval"]
      assert trait_review.raw_evidence == ["globular"]
      assert updated_entry.review_payload.description_review.edited == true
    end

    test "rejects review updates when the ingestion is not associated with a source" do
      reviewer = user_fixture()
      mapped_gall = species_fixture("Andricus blocked", "gall")

      species_entry =
        create_species_entry(
          source_ingestion_fixture(%{
            input_type: "pdf",
            status: "needs_review",
            processing_stage: "review"
          }),
          0,
          %{}
        )

      assert {:error, changeset} =
               Ingestions.update_source_ingestion_species_review(
                 species_entry,
                 %{
                   description_prose: "Blocked review",
                   species_review: %{decision: "mapped", species_id: mapped_gall.id}
                 },
                 reviewer.id
               )

      assert %{source_ingestion_id: ["must be associated with a source before gall review"]} =
               errors_on(changeset)
    end

    test "creates a new gall species when completion chooses the new-species path" do
      reviewer = user_fixture()
      source = source_fixture()

      assert {:ok, family} =
               Taxonomy.create_taxonomy(%{
                 name: "Reviewfamily#{System.unique_integer([:positive])}",
                 type: "family",
                 description: "Gall"
               })

      ingestion =
        source_ingestion_fixture(%{
          input_type: "pdf",
          status: "needs_review",
          processing_stage: "review",
          source_id: source.id
        })

      species_entry =
        create_species_entry(ingestion, 0, %{
          extracted_name: "Brandnewgallus reviewus",
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{
              "shape" => %{"original" => "globular", "suggested" => ["globular"]}
            },
            "description_evidence" => [%{"text" => "Rounded review gall."}]
          }
        })

      assert {:ok, updated_entry} =
               Ingestions.update_source_ingestion_species_review(
                 species_entry,
                 %{
                   action: "complete",
                   description_prose: "Rounded review gall.",
                   species_review: %{
                     decision: "new",
                     family_id: family.id,
                     accepted_aliases: ["Brandnew review synonym"]
                   },
                   host_reviews: %{},
                   trait_reviews: %{
                     "shape" => %{selected_values: ["globular"]}
                   }
                 },
                 reviewer.id
               )

      assert updated_entry.status == "complete"
      assert is_integer(updated_entry.species_id)

      created_species = Gallformers.Species.get_species!(updated_entry.species_id)
      assert created_species.name == "Brandnewgallus reviewus"

      assert Enum.any?(
               Gallformers.Species.get_aliases_for_species(created_species.id),
               &(&1.name == "Brandnew review synonym")
             ) == true

      species_source = Sources.get_species_source_by_ids(created_species.id, source.id)
      assert species_source.description == "Rounded review gall."
    end
  end

  describe "get_source_ingestion_with_details!/1" do
    test "preloads species entries in review order" do
      ingestion =
        source_ingestion_fixture(%{
          input_type: "pdf",
          status: "needs_review",
          processing_stage: "review"
        })

      assert {:ok, _species_entry} =
               Ingestions.create_source_ingestion_species(%{
                 source_ingestion_id: ingestion.id,
                 position: 2,
                 extracted_name: "Later gall"
               })

      assert {:ok, _species_entry} =
               Ingestions.create_source_ingestion_species(%{
                 source_ingestion_id: ingestion.id,
                 position: 1,
                 extracted_name: "Earlier gall"
               })

      detailed_ingestion = Ingestions.get_source_ingestion_with_details!(ingestion.id)

      assert Enum.map(detailed_ingestion.species_entries, & &1.position) == [1, 2]
    end
  end

  describe "list_source_ingestion_queue_rows/1" do
    test "returns newest-first rows with aggregated counts and uploader names" do
      uploader = user_fixture()
      source = source_fixture()

      processing =
        source_ingestion_fixture(%{
          input_type: "text",
          uploaded_by_id: uploader.id,
          title: "Processing submission",
          status: "processing",
          processing_stage: "metadata"
        })

      review_ready =
        source_ingestion_fixture(%{
          input_type: "url",
          uploaded_by_id: uploader.id,
          status: "needs_review",
          processing_stage: "review",
          source_id: source.id
        })

      complete =
        source_ingestion_fixture(%{
          input_type: "pdf",
          uploaded_by_id: uploader.id,
          title: "Completed submission",
          status: "complete",
          processing_stage: "complete",
          source_id: source.id
        })

      create_species_entry(review_ready, 0, %{status: "pending", extracted_name: "Pending gall"})

      create_species_entry(review_ready, 1, %{status: "mapped", extracted_name: "Mapped gall"})

      rows =
        Ingestions.list_source_ingestion_queue_rows(
          uploaded_by_id: uploader.id,
          include_complete: true
        )

      assert Enum.map(rows, & &1.id) == [complete.id, review_ready.id, processing.id]

      assert Enum.find(rows, &(&1.id == review_ready.id)) == %{
               id: review_ready.id,
               title: nil,
               input_type: "url",
               status: "needs_review",
               processing_stage: "review",
               error_stage: nil,
               inserted_at: review_ready.inserted_at,
               uploaded_by_id: uploader.id,
               uploaded_by_name: "Ingestion Reviewer",
               source_id: source.id,
               duplicate_of_source_ingestion_id: nil,
               total_species_entries_count: 2,
               pending_species_entries_count: 1,
               resolved_species_entries_count: 1
             }
    end

    test "supports status, uploader, and include_complete filters" do
      uploader = user_fixture()
      other_uploader = other_user_fixture()

      hidden_complete =
        source_ingestion_fixture(%{
          input_type: "pdf",
          uploaded_by_id: uploader.id,
          status: "complete",
          processing_stage: "complete"
        })

      included_review =
        source_ingestion_fixture(%{
          input_type: "text",
          uploaded_by_id: uploader.id,
          status: "needs_review",
          processing_stage: "review"
        })

      other_processing =
        source_ingestion_fixture(%{
          input_type: "url",
          uploaded_by_id: other_uploader.id,
          status: "processing",
          processing_stage: "extract"
        })

      assert Enum.map(Ingestions.list_source_ingestion_queue_rows(), & &1.id) == [
               other_processing.id,
               included_review.id
             ]

      assert Enum.map(
               Ingestions.list_source_ingestion_queue_rows(include_complete: true),
               & &1.id
             ) ==
               [other_processing.id, included_review.id, hidden_complete.id]

      assert Enum.map(
               Ingestions.list_source_ingestion_queue_rows(
                 uploaded_by_id: uploader.id,
                 include_complete: true
               ),
               & &1.id
             ) == [included_review.id, hidden_complete.id]

      assert Enum.map(
               Ingestions.list_source_ingestion_queue_rows(
                 status: [:processing, :complete],
                 include_complete: true
               ),
               & &1.id
             ) == [other_processing.id, hidden_complete.id]
    end
  end

  describe "queue_status_label/1" do
    test "returns the expected labels across queue states" do
      assert Presenter.queue_status_label(%{
               status: "needs_review",
               processing_stage: "review",
               source_id: nil,
               total_species_entries_count: 0,
               pending_species_entries_count: 0
             }) == "Needs source review"

      assert Presenter.queue_status_label(%{
               status: "needs_review",
               processing_stage: "review",
               source_id: 12,
               total_species_entries_count: 4,
               pending_species_entries_count: 3
             }) == "3 of 4 galls remaining"

      assert Presenter.queue_status_label(%{
               status: "needs_review",
               processing_stage: "review",
               source_id: 12,
               total_species_entries_count: 4,
               pending_species_entries_count: 0
             }) == "0 of 4 galls remaining"

      assert Presenter.queue_status_label(%{
               status: "complete",
               processing_stage: "complete"
             }) == "Complete"

      assert Presenter.queue_status_label(%{
               status: "duplicate_confirmed",
               processing_stage: "duplicate_review"
             }) == "Duplicate confirmed"

      assert Presenter.queue_status_label(%{
               status: "failed",
               processing_stage: "failed",
               error_stage: "metadata"
             }) == "Failed at metadata"

      assert Presenter.queue_status_label(%{
               status: "failed",
               processing_stage: "failed",
               error_stage: nil
             }) == "Failed"

      assert Presenter.queue_status_label(%{
               status: "failed",
               processing_stage: "metadata",
               error_stage: nil
             }) == "Failed at metadata"

      assert Presenter.queue_status_label(%{
               status: "processing",
               processing_stage: "extract"
             }) == "Processing: extract"

      assert Presenter.processing_stage_label(%{
               status: "processing",
               processing_stage: "metadata"
             }) == "metadata"
    end
  end

  describe "get_source_ingestion/1 and get_source_ingestion!/1" do
    test "returns nil for non-existent ID" do
      assert Ingestions.get_source_ingestion(-1) == nil
      assert Ingestions.get_source_ingestion(9_999_999) == nil
    end

    test "raises for non-existent ID with bang version" do
      assert_raise Ecto.NoResultsError, fn ->
        Ingestions.get_source_ingestion!(-1)
      end
    end

    test "returns ingestion for valid ID" do
      ingestion = source_ingestion_fixture(%{input_type: "pdf"})
      assert Ingestions.get_source_ingestion(ingestion.id) == ingestion
      assert Ingestions.get_source_ingestion!(ingestion.id).id == ingestion.id
    end
  end

  describe "source association" do
    test "clear_source_association removes source link" do
      source = source_fixture()
      ingestion = source_ingestion_fixture(%{input_type: "pdf"})

      assert {:ok, associated} = Ingestions.associate_source(ingestion, source)
      assert associated.source_id == source.id

      assert {:ok, cleared} = Ingestions.clear_source_association(associated)
      assert cleared.source_id == nil
    end
  end

  describe "self-duplicate prevention" do
    test "cannot confirm ingestion as duplicate of itself via direct update" do
      ingestion = source_ingestion_fixture(%{input_type: "pdf"})

      assert {:error, changeset} =
               Ingestions.transition_source_ingestion_status(ingestion, :duplicate_confirmed, %{
                 duplicate_of_source_ingestion_id: ingestion.id
               })

      assert changeset.errors[:duplicate_of_source_ingestion_id] != nil
    end
  end

  describe "transition_source_ingestion_status/3" do
    test "transitions through status workflow" do
      ingestion = source_ingestion_fixture(%{input_type: "pdf"})

      # processing -> needs_review (allowed by validate_inclusion only)
      assert {:ok, needs_review} =
               Ingestions.transition_source_ingestion_status(ingestion, :needs_review)

      assert needs_review.status == "needs_review"
      assert needs_review.processing_stage == "review"

      # needs_review -> complete
      assert {:ok, complete} =
               Ingestions.transition_source_ingestion_status(needs_review, :complete)

      assert complete.status == "complete"
      assert complete.processing_stage == "complete"
    end

    test "failed status records failed_at timestamp" do
      ingestion = source_ingestion_fixture(%{input_type: "pdf"})

      assert {:ok, failed} =
               Ingestions.transition_source_ingestion_status(ingestion, :failed, %{
                 error_stage: "extract",
                 error_message: "Extraction failed"
               })

      assert failed.status == "failed"
      assert failed.error_stage == "extract"
      assert failed.error_message == "Extraction failed"
      assert failed.failed_at != nil
      # Verify timestamp is recent (within last few seconds)
      diff_ms = DateTime.diff(DateTime.utc_now(), failed.failed_at, :millisecond)
      assert diff_ms >= 0 and diff_ms < 5000
    end

    test "rejects invalid status values" do
      ingestion = source_ingestion_fixture(%{input_type: "pdf"})

      assert {:error, changeset} =
               Ingestions.transition_source_ingestion_status(ingestion, "invalid_status")

      assert changeset.errors[:status] != nil
    end
  end

  describe "all_species_entries_resolved?/1" do
    test "returns true when no species entries exist" do
      ingestion = source_ingestion_fixture(%{input_type: "pdf"})
      assert Ingestions.all_species_entries_resolved?(ingestion) == true
    end

    test "returns false when pending entries exist" do
      ingestion = source_ingestion_fixture(%{input_type: "pdf"})

      assert {:ok, _} =
               Ingestions.create_source_ingestion_species(%{
                 source_ingestion_id: ingestion.id,
                 position: 0,
                 extracted_name: "Pending Gall"
               })

      assert Ingestions.all_species_entries_resolved?(ingestion) == false
    end
  end

  describe "maybe_complete_source_ingestion_review/1" do
    test "transitions needs_review ingestions to complete when all species entries are resolved" do
      ingestion =
        source_ingestion_fixture(%{
          input_type: "pdf",
          status: "needs_review",
          processing_stage: "review"
        })

      assert {:ok, _} =
               Ingestions.create_source_ingestion_species(%{
                 source_ingestion_id: ingestion.id,
                 position: 0,
                 extracted_name: "Mapped Gall",
                 status: "mapped"
               })

      assert {:ok, _} =
               Ingestions.create_source_ingestion_species(%{
                 source_ingestion_id: ingestion.id,
                 position: 1,
                 extracted_name: "Created Gall",
                 status: "created"
               })

      assert {:ok, completed_ingestion} =
               Ingestions.maybe_complete_source_ingestion_review(ingestion.id)

      assert completed_ingestion.status == "complete"
      assert completed_ingestion.processing_stage == "complete"
    end

    test "leaves ingestions unchanged when pending species entries remain" do
      ingestion =
        source_ingestion_fixture(%{
          input_type: "pdf",
          status: "needs_review",
          processing_stage: "review"
        })

      assert {:ok, _} =
               Ingestions.create_source_ingestion_species(%{
                 source_ingestion_id: ingestion.id,
                 position: 0,
                 extracted_name: "Pending Gall",
                 status: "pending"
               })

      assert {:ok, unchanged_ingestion} =
               Ingestions.maybe_complete_source_ingestion_review(ingestion.id)

      assert unchanged_ingestion.status == "needs_review"
      assert unchanged_ingestion.processing_stage == "review"
    end
  end

  defp source_ingestion_fixture(attrs) do
    merged_attrs =
      attrs
      |> Map.new()
      |> Map.put_new(:input_type, "pdf")
      |> Map.put_new(:status, "processing")
      |> Map.put_new(:processing_stage, "submitted")

    assert {:ok, source_ingestion} = Ingestions.create_source_ingestion(merged_attrs)
    source_ingestion
  end

  defp source_fixture do
    assert {:ok, source} =
             Sources.create_source(%{
               title: "Test Source #{System.unique_integer([:positive])}",
               author: "Author",
               pubyear: "2024",
               link: "https://example.com/source",
               citation: "Author. 2024. Test Source.",
               license: "CC-BY",
               licenselink: "https://creativecommons.org/licenses/by/4.0/"
             })

    source
  end

  defp species_fixture(name, taxoncode \\ "gall") do
    assert {:ok, species} =
             Repo.insert(%Species{
               name: name,
               taxoncode: taxoncode,
               datacomplete: false
             })

    species
  end

  defp user_fixture do
    assert {:ok, user} =
             Accounts.create_user(%{
               auth0_id: "auth0|ingestion-test-#{System.unique_integer([:positive])}",
               display_name: "Ingestion Reviewer"
             })

    user
  end

  defp other_user_fixture do
    assert {:ok, user} =
             Accounts.create_user(%{
               auth0_id: "auth0|ingestion-test-#{System.unique_integer([:positive])}",
               display_name: "Another Reviewer"
             })

    user
  end

  defp create_species_entry(ingestion, position, attrs) do
    default_payload = %{
      "hosts" => [%{"name" => "Quercus alba"}],
      "traits" => %{
        "shape" => %{"original" => "globular", "suggested" => ["globular"]}
      },
      "description_evidence" => [%{"text" => "Rounded woody gall on oak twigs."}]
    }

    entry_attrs =
      attrs
      |> Map.new()
      |> Map.put_new(:source_ingestion_id, ingestion.id)
      |> Map.put_new(:position, position)
      |> Map.put_new(:description_prose, "Rounded woody gall on oak twigs.")
      |> Map.put_new(:extraction_payload, default_payload)

    assert {:ok, source_ingestion_species} =
             Ingestions.create_source_ingestion_species(entry_attrs)

    source_ingestion_species
  end
end
