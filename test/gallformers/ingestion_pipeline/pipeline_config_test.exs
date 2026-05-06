defmodule Gallformers.IngestionPipeline.PipelineConfigTest do
  use Gallformers.DataCase, async: true

  alias Gallformers.IngestionPipeline.PipelineConfig

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

  describe "changeset/2" do
    test "valid attrs produces a valid changeset" do
      changeset =
        PipelineConfig.changeset(%PipelineConfig{}, %{name: "default", config: @valid_config})

      assert changeset.valid?
    end

    test "name is required" do
      changeset = PipelineConfig.changeset(%PipelineConfig{}, %{config: @valid_config})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "config is required" do
      changeset = PipelineConfig.changeset(%PipelineConfig{}, %{name: "default"})
      assert %{config: ["can't be blank"]} = errors_on(changeset)
    end

    test "blank name is invalid" do
      changeset =
        PipelineConfig.changeset(%PipelineConfig{}, %{name: "  ", config: @valid_config})

      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "name uniqueness is enforced" do
      {:ok, _} =
        Repo.insert(
          PipelineConfig.changeset(%PipelineConfig{}, %{
            name: "unique-test",
            config: @valid_config
          })
        )

      {:error, changeset} =
        Repo.insert(
          PipelineConfig.changeset(%PipelineConfig{}, %{
            name: "unique-test",
            config: @valid_config
          })
        )

      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "name is trimmed" do
      changeset =
        PipelineConfig.changeset(%PipelineConfig{}, %{name: "  padded  ", config: @valid_config})

      assert get_change(changeset, :name) == "padded"
    end
  end
end
