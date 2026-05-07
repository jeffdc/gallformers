defmodule Gallformers.IngestionPipeline.LLMClientTest do
  use ExUnit.Case, async: false

  alias Gallformers.IngestionPipeline.LLMClient

  setup do
    previous_config = Application.get_env(:gallformers, LLMClient)
    previous_api_key = System.get_env("DEEPINFRA_API_KEY")

    System.put_env("DEEPINFRA_API_KEY", "test-key")

    on_exit(fn ->
      if previous_config == nil do
        Application.delete_env(:gallformers, LLMClient)
      else
        Application.put_env(:gallformers, LLMClient, previous_config)
      end

      if is_nil(previous_api_key) do
        System.delete_env("DEEPINFRA_API_KEY")
      else
        System.put_env("DEEPINFRA_API_KEY", previous_api_key)
      end
    end)

    :ok
  end

  test "successful 200 response returns text and usage" do
    set_request_stub(fn _url, headers, body ->
      send(self(), {:request, headers, body})

      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [%{"message" => %{"content" => "cleaned text"}}],
           "usage" => %{"prompt_tokens" => 12, "completion_tokens" => 34}
         }
       }}
    end)

    assert {:ok, "cleaned text", %{prompt_tokens: 12, completion_tokens: 34}} =
             LLMClient.completion(:llm_clean, "system prompt", "user text")

    assert_received {:request, headers, body}
    assert {"authorization", "Bearer test-key"} in headers
    assert body["model"] == "Qwen/Qwen2.5-72B-Instruct"
    assert body["max_tokens"] == 8192
  end

  test "429 returns rate_limited without retry" do
    set_request_stub(fn _url, _headers, _body ->
      send(self(), :attempt)
      {:ok, %{status: 429, body: %{}}}
    end)

    assert {:error, :rate_limited} =
             LLMClient.completion(:metadata, "system prompt", "user text")

    assert_received :attempt
    refute_receive :attempt
  end

  test "non-retryable non-200 status returns http_error without retry" do
    set_request_stub(fn _url, _headers, _body ->
      send(self(), :attempt)
      {:ok, %{status: 401, body: %{}}}
    end)

    assert {:error, :http_error, 401} =
             LLMClient.completion(:metadata, "system prompt", "user text")

    assert_received :attempt
    refute_receive :attempt
  end

  test "499 is retried like a server error" do
    Process.put(:attempt_count, 0)

    set_request_stub(fn _url, _headers, _body ->
      attempt_count = Process.get(:attempt_count, 0) + 1
      Process.put(:attempt_count, attempt_count)
      {:ok, %{status: 499, body: %{}}}
    end)

    set_sleep_stub(fn _backoff_ms -> :ok end)

    assert {:error, :server_error, 499} =
             LLMClient.completion(:metadata, "system prompt", "user text")

    assert Process.get(:attempt_count) == 4
  end

  test "5xx retries up to 3 times then returns server_error" do
    Process.put(:attempt_count, 0)

    set_request_stub(fn _url, _headers, _body ->
      attempt_count = Process.get(:attempt_count, 0) + 1
      Process.put(:attempt_count, attempt_count)
      {:ok, %{status: 503, body: %{}}}
    end)

    set_sleep_stub(fn backoff_ms -> send(self(), {:sleep, backoff_ms}) end)

    assert {:error, :server_error, 503} =
             LLMClient.completion(:metadata, "system prompt", "user text")

    assert Process.get(:attempt_count) == 4
    assert_received {:sleep, 1_000}
    assert_received {:sleep, 2_000}
    assert_received {:sleep, 4_000}
  end

  test "timeout retries up to 3 times then returns timeout" do
    Process.put(:attempt_count, 0)

    set_request_stub(fn _url, _headers, _body ->
      attempt_count = Process.get(:attempt_count, 0) + 1
      Process.put(:attempt_count, attempt_count)
      {:error, :timeout}
    end)

    set_sleep_stub(fn backoff_ms -> send(self(), {:sleep, backoff_ms}) end)

    assert {:error, :timeout} =
             LLMClient.completion(:metadata, "system prompt", "user text")

    assert Process.get(:attempt_count) == 4
    assert_received {:sleep, 1_000}
    assert_received {:sleep, 2_000}
    assert_received {:sleep, 4_000}
  end

  test "non-timeout transport errors are normalized without retry" do
    set_request_stub(fn _url, _headers, _body ->
      send(self(), :attempt)
      {:error, :econnrefused}
    end)

    assert {:error, :transport_error, :econnrefused} =
             LLMClient.completion(:metadata, "system prompt", "user text")

    assert_received :attempt
    refute_receive :attempt
  end

  test "malformed 200 body returns invalid_response instead of raising" do
    set_request_stub(fn _url, _headers, _body ->
      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [%{"message" => %{}}],
           "usage" => %{"prompt_tokens" => 12}
         }
       }}
    end)

    assert {:error, :invalid_response} =
             LLMClient.completion(:metadata, "system prompt", "user text")
  end

  test "merge_prompt true sends a single merged user message" do
    set_request_stub(fn _url, _headers, body ->
      send(self(), {:body, body})

      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [%{"message" => %{"content" => "ok"}}],
           "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1}
         }
       }}
    end)

    assert {:ok, "ok", _usage} =
             LLMClient.completion(:data_extract, "system prompt", "user text", merge_prompt: true)

    assert_received {:body, body}
    assert body["messages"] == [%{"role" => "user", "content" => "system prompt\n\nuser text"}]
  end

  test "model opt overrides default model" do
    set_request_stub(fn _url, _headers, body ->
      send(self(), {:body, body})

      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [%{"message" => %{"content" => "ok"}}],
           "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1}
         }
       }}
    end)

    assert {:ok, "ok", _} =
             LLMClient.completion(:llm_clean, "sys", "user", model: "custom-model")

    assert_received {:body, body}
    assert body["model"] == "custom-model"
  end

  test "api_url opt overrides default url" do
    set_request_stub(fn url, _headers, _body ->
      send(self(), {:url, url})

      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [%{"message" => %{"content" => "ok"}}],
           "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1}
         }
       }}
    end)

    assert {:ok, "ok", _} =
             LLMClient.completion(:llm_clean, "sys", "user", api_url: "https://custom.api/v1")

    assert_received {:url, "https://custom.api/v1"}
  end

  test "retry_backoffs opt overrides default retries" do
    Process.put(:attempt_count, 0)

    set_request_stub(fn _url, _headers, _body ->
      attempt_count = Process.get(:attempt_count, 0) + 1
      Process.put(:attempt_count, attempt_count)
      {:ok, %{status: 503, body: %{}}}
    end)

    set_sleep_stub(fn backoff_ms -> send(self(), {:sleep, backoff_ms}) end)

    assert {:error, :server_error, 503} =
             LLMClient.completion(:metadata, "sys", "user", retry_backoffs: [100, 200])

    assert Process.get(:attempt_count) == 3
    assert_received {:sleep, 100}
    assert_received {:sleep, 200}
  end

  test "request body includes streaming options" do
    set_request_stub(fn _url, _headers, body ->
      send(self(), {:body, body})

      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [%{"message" => %{"content" => "ok"}}],
           "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1}
         }
       }}
    end)

    assert {:ok, _, _} = LLMClient.completion(:llm_clean, "sys", "user")
    assert_received {:body, body}
    assert body["stream"] == true
    assert body["stream_options"]["include_usage"] == true
    assert body["stream_options"]["continuous_usage_stats"] == true
  end

  test "usage map includes enriched fields on sync path" do
    set_request_stub(fn _url, _headers, _body ->
      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [%{"message" => %{"content" => "ok"}}],
           "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 20}
         }
       }}
    end)

    assert {:ok, "ok", usage} = LLMClient.completion(:llm_clean, "sys", "user")
    assert usage.prompt_tokens == 10
    assert usage.completion_tokens == 20
    assert is_number(usage.tokens_per_sec) or is_nil(usage.tokens_per_sec)
    assert is_nil(usage.estimated_cost)
    assert is_nil(usage.finish_reason)
    assert usage.truncated == false
  end

  test "stall_timeout opt is accepted" do
    set_request_stub(fn _url, _headers, _body ->
      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [%{"message" => %{"content" => "ok"}}],
           "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1}
         }
       }}
    end)

    assert {:ok, "ok", _} =
             LLMClient.completion(:llm_clean, "sys", "user", stall_timeout: 30_000)
  end

  test "chunk_text respects paragraph boundaries and max size" do
    text = "para one\n\npara two\n\n#{String.duplicate("x", 25)}\n\npara four"

    chunks = LLMClient.chunk_text(text, 20)

    assert chunks == ["para one\n\npara two", String.duplicate("x", 25), "para four"]

    assert Enum.all?(chunks, &(String.length(&1) <= 20 or &1 == String.duplicate("x", 25))) ==
             true
  end

  defp set_request_stub(request_fun) do
    Application.put_env(
      :gallformers,
      LLMClient,
      Keyword.merge(Application.get_env(:gallformers, LLMClient, []), request_fun: request_fun)
    )
  end

  defp set_sleep_stub(sleep_fun) do
    Application.put_env(
      :gallformers,
      LLMClient,
      Keyword.merge(Application.get_env(:gallformers, LLMClient, []), sleep_fun: sleep_fun)
    )
  end
end
