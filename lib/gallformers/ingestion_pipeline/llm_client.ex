defmodule Gallformers.IngestionPipeline.LLMClient do
  @moduledoc """
  Thin OpenAI-compatible client for ingestion pipeline stages.
  """

  use Boundary, deps: [], exports: :all

  require Logger

  @default_model "deepseek-ai/DeepSeek-V3-0324"
  @default_max_tokens 8192
  @default_receive_timeout 120_000
  @default_retry_backoffs [1_000, 2_000, 4_000]
  @default_api_url "https://api.deepinfra.com/v1/openai/chat/completions"

  @doc """
  Executes a completion request for a pipeline stage.
  """
  @spec completion(atom(), String.t(), String.t(), keyword()) ::
          {:ok, String.t(), %{prompt_tokens: integer(), completion_tokens: integer()}}
          | {:error, :rate_limited}
          | {:error, :http_error, integer()}
          | {:error, :server_error, integer()}
          | {:error, :transport_error, term()}
          | {:error, :invalid_response}
          | {:error, :timeout}
  def completion(stage, system_prompt, user_text, opts \\ [])
      when is_atom(stage) and is_binary(system_prompt) and is_binary(user_text) do
    model = model_for(stage)
    input_chars = String.length(user_text)

    Logger.info("LLM request starting",
      stage: stage,
      model: model,
      input_chars: input_chars
    )

    start = System.monotonic_time(:millisecond)
    body = request_body(stage, system_prompt, user_text, opts)
    headers = request_headers()
    result = do_completion(body, headers, retry_backoffs())
    elapsed_ms = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, content, usage} ->
        Logger.info("LLM request completed",
          stage: stage,
          model: model,
          elapsed_ms: elapsed_ms,
          input_chars: input_chars,
          output_chars: String.length(content),
          prompt_tokens: usage.prompt_tokens,
          completion_tokens: usage.completion_tokens
        )

      {:error, reason} ->
        Logger.warning("LLM request failed",
          stage: stage,
          model: model,
          elapsed_ms: elapsed_ms,
          input_chars: input_chars,
          error: inspect(reason)
        )

      {:error, reason, status} ->
        Logger.warning("LLM request failed",
          stage: stage,
          model: model,
          elapsed_ms: elapsed_ms,
          input_chars: input_chars,
          error: inspect(reason),
          status: status
        )
    end

    result
  end

  @doc """
  Splits text on paragraph boundaries into chunks up to `max_chars`.
  """
  @spec chunk_text(String.t(), pos_integer()) :: [String.t()]
  def chunk_text(text, max_chars)
      when is_binary(text) and is_integer(max_chars) and max_chars > 0 do
    text
    |> String.split("\n\n", trim: true)
    |> Enum.reduce([], &append_chunk(&1, &2, max_chars))
    |> Enum.reverse()
  end

  defp append_chunk(paragraph, [], _max_chars), do: [paragraph]

  defp append_chunk(paragraph, [current | rest], max_chars) do
    candidate = current <> "\n\n" <> paragraph

    if String.length(current) <= max_chars and String.length(candidate) <= max_chars do
      [candidate | rest]
    else
      [paragraph, current | rest]
    end
  end

  defp do_completion(body, headers, retries_remaining) do
    case normalize_request_result(request_fun().(api_url(), headers, body)) do
      {:ok, response_body} ->
        parse_success(response_body)

      {:error, :rate_limited} ->
        {:error, :rate_limited}

      {:error, :server_error, status} ->
        retry_server_error(status, body, headers, retries_remaining)

      {:error, :http_error, status} ->
        {:error, :http_error, status}

      {:error, :timeout} ->
        retry_timeout(body, headers, retries_remaining)

      {:error, :transport_error, reason} ->
        {:error, :transport_error, reason}

      {:error, :invalid_response} ->
        {:error, :invalid_response}
    end
  end

  defp normalize_request_result({:ok, %{status: 200, body: response_body}}),
    do: {:ok, response_body}

  defp normalize_request_result({:ok, %{status: 429}}), do: {:error, :rate_limited}

  defp normalize_request_result({:ok, %{status: status}})
       when is_integer(status) and status >= 500 and status <= 599 do
    {:error, :server_error, status}
  end

  defp normalize_request_result({:ok, %{status: status}}) when is_integer(status) do
    {:error, :http_error, status}
  end

  defp normalize_request_result({:ok, _response}), do: {:error, :invalid_response}
  defp normalize_request_result({:error, :timeout}), do: {:error, :timeout}

  defp normalize_request_result({:error, :transport_error, reason}),
    do: {:error, :transport_error, reason}

  defp normalize_request_result({:error, reason}), do: {:error, :transport_error, reason}

  defp parse_success(response_body) when is_map(response_body) do
    with %{"choices" => choices, "usage" => usage} <- response_body,
         [%{"message" => %{"content" => content}} | _] <- choices,
         %{"prompt_tokens" => prompt_tokens, "completion_tokens" => completion_tokens} <- usage,
         true <-
           is_binary(content) and is_integer(prompt_tokens) and is_integer(completion_tokens) do
      {:ok, content, %{prompt_tokens: prompt_tokens, completion_tokens: completion_tokens}}
    else
      _ -> {:error, :invalid_response}
    end
  end

  defp parse_success(_response_body), do: {:error, :invalid_response}

  defp retry_server_error(status, _body, _headers, []), do: {:error, :server_error, status}

  defp retry_server_error(status, body, headers, [backoff_ms | rest]) do
    sleep_fun().(backoff_ms)
    retry_or_server_error(do_completion(body, headers, rest), status)
  end

  defp retry_or_server_error({:error, :timeout}, status), do: {:error, :server_error, status}
  defp retry_or_server_error(result, _status), do: result

  defp retry_timeout(_body, _headers, []), do: {:error, :timeout}

  defp retry_timeout(body, headers, [backoff_ms | rest]) do
    sleep_fun().(backoff_ms)
    do_completion(body, headers, rest)
  end

  defp request_body(stage, system_prompt, user_text, opts) do
    %{
      "model" => model_for(stage),
      "messages" => messages(system_prompt, user_text, Keyword.get(opts, :merge_prompt, false)),
      "max_tokens" => Keyword.get(opts, :max_tokens, @default_max_tokens)
    }
  end

  defp messages(system_prompt, user_text, true) do
    [%{"role" => "user", "content" => system_prompt <> "\n\n" <> user_text}]
  end

  defp messages(system_prompt, user_text, false) do
    [
      %{"role" => "system", "content" => system_prompt},
      %{"role" => "user", "content" => user_text}
    ]
  end

  defp request_headers do
    [
      {"authorization", "Bearer " <> System.fetch_env!("DEEPINFRA_API_KEY")},
      {"content-type", "application/json"}
    ]
  end

  defp model_for(stage) do
    config()[:models][stage] || @default_model
  end

  defp api_url, do: config()[:api_url] || @default_api_url
  defp receive_timeout, do: config()[:receive_timeout] || @default_receive_timeout
  defp retry_backoffs, do: config()[:retry_backoffs] || @default_retry_backoffs

  defp config do
    Application.get_env(:gallformers, :ingestion_pipeline, %{})
  end

  defp request_fun do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:request_fun, &default_request_fun/3)
  end

  defp sleep_fun do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:sleep_fun, &:timer.sleep/1)
  end

  defp default_request_fun(url, headers, body) do
    case Req.post(url: url, headers: headers, json: body, receive_timeout: receive_timeout()) do
      {:ok, %Req.Response{status: status, body: response_body}} ->
        {:ok, %{status: status, body: response_body}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, %Req.TransportError{reason: :connect_timeout}} ->
        {:error, :timeout}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, :transport_error, reason}

      {:error, reason} ->
        {:error, :transport_error, reason}
    end
  end
end
