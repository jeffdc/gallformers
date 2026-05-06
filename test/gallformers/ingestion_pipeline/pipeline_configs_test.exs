defmodule Gallformers.IngestionPipeline.PipelineConfigsTest do
  use Gallformers.DataCase, async: true

  alias Gallformers.IngestionPipeline.PipelineConfig
  alias Gallformers.IngestionPipeline.PipelineConfigs

  @valid_config %{
    "client" => %{
      "api_url" => "https://api.deepinfra.com/v1/openai/chat/completions",
      "receive_timeout" => 120_000,
      "retry_backoffs" => [1000, 2000, 4000]
    },
    "llm_clean" => %{
      "model" => "deepseek-ai/DeepSeek-V3-0324",
      "chunk_size" => 6000,
      "max_tokens" => 8192,
      "max_concurrency" => 2,
      "task_timeout_minutes" => 10
    },
    "metadata" => %{
      "model" => "deepseek-ai/DeepSeek-V3-0324",
      "max_tokens" => 1024,
      "max_input_chars" => 24_000
    },
    "data_extract" => %{
      "model" => "deepseek-ai/DeepSeek-V3-0324",
      "chunk_size" => 3000,
      "max_tokens" => 6000,
      "max_concurrency" => 2,
      "task_timeout_minutes" => 10,
      "json_attempts" => 3
    }
  }

  defp create_config(attrs \\ %{}) do
    {:ok, config} =
      PipelineConfigs.create_pipeline_config(
        Map.merge(%{name: "test-config", config: @valid_config}, attrs)
      )

    config
  end

  describe "list_pipeline_configs/0" do
    test "returns all configs ordered by name" do
      _c2 = create_config(%{name: "bravo"})
      _c1 = create_config(%{name: "alpha"})

      configs = PipelineConfigs.list_pipeline_configs()
      assert length(configs) == 2
      assert hd(configs).name == "alpha"
    end
  end

  describe "get_pipeline_config!/1" do
    test "returns config by id" do
      config = create_config()
      assert PipelineConfigs.get_pipeline_config!(config.id).name == config.name
    end

    test "raises for missing id" do
      assert_raise Ecto.NoResultsError, fn ->
        PipelineConfigs.get_pipeline_config!(0)
      end
    end
  end

  describe "create_pipeline_config/1" do
    test "creates with valid attrs" do
      assert {:ok, %PipelineConfig{} = config} =
               PipelineConfigs.create_pipeline_config(%{
                 name: "new-config",
                 config: @valid_config
               })

      assert config.name == "new-config"
      assert config.config == @valid_config
    end

    test "returns error for invalid attrs" do
      assert {:error, changeset} = PipelineConfigs.create_pipeline_config(%{})
      assert %{name: ["can't be blank"], config: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "update_pipeline_config/2" do
    test "updates name" do
      config = create_config()

      assert {:ok, updated} =
               PipelineConfigs.update_pipeline_config(config, %{name: "renamed"})

      assert updated.name == "renamed"
    end

    test "updates config blob" do
      config = create_config()
      new_blob = put_in(@valid_config, ["llm_clean", "model"], "other-model")

      assert {:ok, updated} =
               PipelineConfigs.update_pipeline_config(config, %{config: new_blob})

      assert updated.config["llm_clean"]["model"] == "other-model"
    end
  end

  describe "delete_pipeline_config/1" do
    test "deletes the config" do
      config = create_config()
      assert {:ok, _} = PipelineConfigs.delete_pipeline_config(config)
      assert_raise Ecto.NoResultsError, fn -> PipelineConfigs.get_pipeline_config!(config.id) end
    end
  end

  describe "change_pipeline_config/2" do
    test "returns a changeset" do
      config = create_config()
      assert %Ecto.Changeset{} = PipelineConfigs.change_pipeline_config(config)
    end
  end

  describe "config_options/0" do
    test "returns id/name pairs for dropdowns" do
      c1 = create_config(%{name: "alpha"})
      c2 = create_config(%{name: "bravo"})

      options = PipelineConfigs.config_options()
      assert length(options) == 2
      assert {c1.id, "alpha"} in options
      assert {c2.id, "bravo"} in options
    end
  end
end
