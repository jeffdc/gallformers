defmodule Gallformers.IngestionPipeline.LLMClient do
  @moduledoc """
  Thin OpenAI-compatible client for ingestion pipeline stages.
  """

  use Boundary, deps: [], exports: :all

  require Logger

  @default_model "Qwen/Qwen2.5-72B-Instruct"
  @default_max_tokens 8192
  @default_receive_timeout 300_000
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
    {model, resolved} = resolve_config(stage, opts)
    input_chars = String.length(user_text)

    Logger.info("LLM request starting", stage: stage, model: model, input_chars: input_chars)

    start = System.monotonic_time(:millisecond)
    body = request_body(model, system_prompt, user_text, opts)
    headers = request_headers()
    req_fn = build_request_fn(resolved.recv_timeout)
    result = do_completion(body, headers, resolved.retries, resolved.api_url, req_fn)
    elapsed_ms = System.monotonic_time(:millisecond) - start

    log_result(result, stage, model, elapsed_ms, input_chars)
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

  defp do_completion(body, headers, retries_remaining, api_url, req_fn) do
    case normalize_request_result(req_fn.(api_url, headers, body)) do
      {:ok, response_body} ->
        parse_success(response_body)

      {:error, :rate_limited} ->
        {:error, :rate_limited}

      {:error, :server_error, status} ->
        retry_server_error(status, body, headers, retries_remaining, api_url, req_fn)

      {:error, :http_error, status} ->
        {:error, :http_error, status}

      {:error, :timeout} ->
        retry_timeout(body, headers, retries_remaining, api_url, req_fn)

      {:error, :transport_error, reason} ->
        {:error, :transport_error, reason}

      {:error, :invalid_response} ->
        {:error, :invalid_response}
    end
  end

  defp normalize_request_result({:ok, %{status: 200, body: response_body}}),
    do: {:ok, response_body}

  defp normalize_request_result({:ok, %{status: 429}}), do: {:error, :rate_limited}

  defp normalize_request_result({:ok, %{status: 499}}), do: {:error, :server_error, 499}

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

  defp retry_server_error(status, _body, _headers, [], _api_url, _req_fn),
    do: {:error, :server_error, status}

  defp retry_server_error(status, body, headers, [backoff_ms | rest], api_url, req_fn) do
    sleep_fun().(backoff_ms)
    retry_or_server_error(do_completion(body, headers, rest, api_url, req_fn), status)
  end

  defp retry_or_server_error({:error, :timeout}, status), do: {:error, :server_error, status}
  defp retry_or_server_error(result, _status), do: result

  defp retry_timeout(_body, _headers, [], _api_url, _req_fn), do: {:error, :timeout}

  defp retry_timeout(body, headers, [backoff_ms | rest], api_url, req_fn) do
    sleep_fun().(backoff_ms)
    do_completion(body, headers, rest, api_url, req_fn)
  end

  defp resolve_config(stage, opts) do
    model = Keyword.get(opts, :model) || model_for(stage)

    resolved = %{
      api_url: Keyword.get(opts, :api_url) || api_url(),
      retries: Keyword.get(opts, :retry_backoffs) || retry_backoffs(),
      recv_timeout: Keyword.get(opts, :receive_timeout) || receive_timeout()
    }

    {model, resolved}
  end

  defp log_result({:ok, content, usage}, stage, model, elapsed_ms, input_chars) do
    Logger.info("LLM request completed",
      stage: stage,
      model: model,
      elapsed_ms: elapsed_ms,
      input_chars: input_chars,
      output_chars: String.length(content),
      prompt_tokens: usage.prompt_tokens,
      completion_tokens: usage.completion_tokens
    )
  end

  defp log_result({:error, reason}, stage, model, elapsed_ms, input_chars) do
    Logger.warning("LLM request failed",
      stage: stage,
      model: model,
      elapsed_ms: elapsed_ms,
      input_chars: input_chars,
      error: inspect(reason)
    )
  end

  defp log_result({:error, reason, status}, stage, model, elapsed_ms, input_chars) do
    Logger.warning("LLM request failed",
      stage: stage,
      model: model,
      elapsed_ms: elapsed_ms,
      input_chars: input_chars,
      error: inspect(reason),
      status: status
    )
  end

  defp request_body(model, system_prompt, user_text, opts) do
    %{
      "model" => model,
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

  defp build_request_fn(recv_timeout) do
    case Keyword.get(Application.get_env(:gallformers, __MODULE__, []), :request_fun) do
      nil -> fn url, headers, body -> default_request(url, headers, body, recv_timeout) end
      custom_fn -> custom_fn
    end
  end

  defp default_request(url, headers, body, recv_timeout) do
    case Req.post(url: url, headers: headers, json: body, receive_timeout: recv_timeout) do
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

  defp sleep_fun do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:sleep_fun, &:timer.sleep/1)
  end
end
