defmodule Gallformers.IngestionPipeline.PipelineConfigReaderTest do
  use Gallformers.DataCase, async: true

  alias Gallformers.IngestionPipeline.PipelineConfigReader
  alias Gallformers.IngestionPipeline.PipelineConfigs

  import Gallformers.IngestionPipelineFixtures

  @full_config %{
    "client" => %{
      "api_url" => "https://custom.api/v1/chat",
      "receive_timeout" => 60_000,
      "retry_backoffs" => [500, 1000]
    },
    "llm_clean" => %{
      "model" => "custom-model-v1",
      "chunk_size" => 4000,
      "max_tokens" => 4096,
      "max_concurrency" => 4,
      "task_timeout_minutes" => 5
    },
    "metadata" => %{
      "model" => "custom-model-v2",
      "max_tokens" => 2048,
      "max_input_chars" => 12_000
    },
    "data_extract" => %{
      "model" => "custom-model-v3",
      "chunk_size" => 1500,
      "max_tokens" => 3000,
      "max_concurrency" => 1,
      "task_timeout_minutes" => 15,
      "json_attempts" => 5
    }
  }

  defp create_config_and_ingestion(config_blob \\ @full_config) do
    {:ok, pipeline_config} =
      PipelineConfigs.create_pipeline_config(%{
        name: "test-#{System.unique_integer()}",
        config: config_blob
      })

    ingestion = source_ingestion_fixture(%{pipeline_config_id: pipeline_config.id})
    {pipeline_config, ingestion}
  end

  describe "get/4 with pipeline config" do
    test "reads a stage setting from the config blob" do
      {_config, ingestion} = create_config_and_ingestion()
      assert PipelineConfigReader.get(ingestion, :llm_clean, :chunk_size, 6000) == 4000
    end

    test "reads a client setting from the config blob" do
      {_config, ingestion} = create_config_and_ingestion()

      assert PipelineConfigReader.get(ingestion, :client, :api_url, "default") ==
               "https://custom.api/v1/chat"
    end

    test "returns default when key is missing from config blob" do
      sparse_config = %{"llm_clean" => %{"model" => "sparse-model"}}
      {_config, ingestion} = create_config_and_ingestion(sparse_config)

      assert PipelineConfigReader.get(ingestion, :llm_clean, :chunk_size, 6000) == 6000
    end

    test "returns default when stage section is missing from config blob" do
      sparse_config = %{"llm_clean" => %{"model" => "only-clean"}}
      {_config, ingestion} = create_config_and_ingestion(sparse_config)

      assert PipelineConfigReader.get(ingestion, :metadata, :max_tokens, 1024) == 1024
    end
  end

  describe "get/4 without pipeline config" do
    test "returns default when ingestion has no pipeline_config_id" do
      ingestion = source_ingestion_fixture()
      assert PipelineConfigReader.get(ingestion, :llm_clean, :chunk_size, 6000) == 6000
    end

    test "returns default when pipeline_config_id is nil" do
      ingestion = source_ingestion_fixture(%{pipeline_config_id: nil})
      assert PipelineConfigReader.get(ingestion, :llm_clean, :model, "fallback") == "fallback"
    end
  end

  describe "load/1" do
    test "returns the config map when pipeline config exists" do
      {_config, ingestion} = create_config_and_ingestion()
      assert %{} = config = PipelineConfigReader.load(ingestion)
      assert config["llm_clean"]["model"] == "custom-model-v1"
    end

    test "returns nil when no pipeline config" do
      ingestion = source_ingestion_fixture()
      assert PipelineConfigReader.load(ingestion) == nil
    end
  end
end
