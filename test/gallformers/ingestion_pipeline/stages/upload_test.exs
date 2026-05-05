defmodule Gallformers.IngestionPipeline.Stages.UploadTest do
  use Gallformers.DataCase, async: false

  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.Stages.Upload
  alias Gallformers.Ingestions
  alias Gallformers.Storage.SourceArtifacts

  defmodule StorageBackendStub do
    @behaviour Gallformers.Storage.SourceArtifacts.Backend

    @impl true
    def upload(_bucket, _path, _content, _content_type), do: {:ok, %{}}

    @impl true
    def get_object(bucket, path) do
      send(test_pid(), {:get_object, bucket, path})

      case Process.get(:upload_get_object_fixtures, %{}) do
        %{^path => body} -> {:ok, %{body: body}}
        _ -> {:error, :not_found}
      end
    end

    @impl true
    def list_objects(bucket, prefix, continuation_token) do
      send(test_pid(), {:list_objects, bucket, prefix, continuation_token})

      case Process.get(:upload_list_objects_results, []) do
        [next_result | rest] ->
          Process.put(:upload_list_objects_results, rest)
          next_result

        [] ->
          {:ok, %{keys: [], next_continuation_token: nil, is_truncated: false}}
      end
    end

    @impl true
    def delete_objects(_bucket, _keys), do: {:ok, %{}}

    @impl true
    def copy_object(_dest_bucket, _dest_path, _src_bucket, _src_path), do: {:ok, %{}}

    defp test_pid, do: Process.get(:upload_test_pid, self())
  end

  setup do
    previous_storage_config = Application.get_env(:gallformers, SourceArtifacts)

    Process.put(:upload_test_pid, self())
    Application.put_env(:gallformers, SourceArtifacts, backend: StorageBackendStub)

    on_exit(fn ->
      Process.delete(:upload_get_object_fixtures)
      Process.delete(:upload_list_objects_results)
      Process.delete(:upload_test_pid)

      if previous_storage_config == nil do
        Application.delete_env(:gallformers, SourceArtifacts)
      else
        Application.put_env(:gallformers, SourceArtifacts, previous_storage_config)
      end
    end)

    :ok
  end

  test "transitions the ingestion to review and broadcasts review_ready" do
    ingestion = source_ingestion_fixture()
    ingestion_id = ingestion.id
    bucket = SourceArtifacts.private_bucket()
    prefix = "source-ingestions/#{ingestion.id}/"
    data_extract_path = "source-ingestions/#{ingestion.id}/data_extract/output.json"
    Broadcaster.subscribe(ingestion.id)

    set_list_results([
      {:ok,
       %{
         keys: [
           "source-ingestions/#{ingestion.id}/extract/text.txt",
           "source-ingestions/#{ingestion.id}/preprocess/text.txt"
         ],
         next_continuation_token: "page-2",
         is_truncated: true
       }},
      {:ok,
       %{
         keys: [
           "source-ingestions/#{ingestion.id}/metadata/output.json",
           "source-ingestions/#{ingestion.id}/assemble/output.md"
         ],
         next_continuation_token: nil,
         is_truncated: false
       }}
    ])

    put_get_object_fixtures(%{
      data_extract_path =>
        Jason.encode!([valid_record("Andricus uploadii", "Quercus alba", 0.91)])
    })

    assert {:ok, updated_ingestion} = Upload.perform_stage(ingestion)

    assert_receive {:get_object, ^bucket, ^data_extract_path}
    assert_receive {:list_objects, ^bucket, ^prefix, nil}
    assert_receive {:list_objects, ^bucket, ^prefix, "page-2"}
    assert_receive {:review_ready, ^ingestion_id}

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion.id)
    species_entries = Ingestions.list_source_ingestion_species(ingestion.id)

    assert updated_ingestion.status == "needs_review"
    assert updated_ingestion.processing_stage == "review"
    assert reloaded_ingestion.status == "needs_review"
    assert reloaded_ingestion.processing_stage == "review"

    assert Enum.map(species_entries, &{&1.position, &1.extracted_name, &1.status}) == [
             {0, "Andricus uploadii", "pending"}
           ]
  end

  test "artifact_manifest/1 returns all stage artifact keys across paginated results" do
    ingestion = source_ingestion_fixture()

    set_list_results([
      {:ok,
       %{
         keys: [
           "source-ingestions/#{ingestion.id}/llm_clean/text.txt",
           "source-ingestions/#{ingestion.id}/extract/text.txt"
         ],
         next_continuation_token: "page-2",
         is_truncated: true
       }},
      {:ok,
       %{
         keys: [
           "source-ingestions/#{ingestion.id}/data_extract/output.json",
           "source-ingestions/#{ingestion.id}/assemble/output.md"
         ],
         next_continuation_token: nil,
         is_truncated: false
       }}
    ])

    assert {:ok, manifest} = Upload.artifact_manifest(ingestion.id)

    assert manifest == [
             "source-ingestions/#{ingestion.id}/assemble/output.md",
             "source-ingestions/#{ingestion.id}/data_extract/output.json",
             "source-ingestions/#{ingestion.id}/extract/text.txt",
             "source-ingestions/#{ingestion.id}/llm_clean/text.txt"
           ]
  end

  defp source_ingestion_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          input_type: "pdf",
          status: "processing",
          processing_stage: "assemble"
        },
        attrs
      )

    {:ok, ingestion} = Ingestions.create_source_ingestion(attrs)
    ingestion
  end

  defp set_list_results(results) do
    Process.put(:upload_list_objects_results, results)
  end

  defp put_get_object_fixtures(fixtures) do
    Process.put(:upload_get_object_fixtures, fixtures)
  end

  defp valid_record(gall_name, host_name, confidence) do
    %{
      "gall_species" => %{
        "name" => gall_name,
        "authority" => nil,
        "family" => "Cynipidae",
        "order" => "Hymenoptera"
      },
      "host_species" => %{
        "name" => host_name,
        "authority" => nil,
        "family" => "Fagaceae"
      },
      "traits" => %{},
      "description" => "Gall description",
      "location" => nil,
      "confidence" => confidence
    }
  end
end
