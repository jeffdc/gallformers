defmodule Gallformers.IngestionPipeline.SSEParser do
  @moduledoc """
  Pure-function module for parsing OpenAI-compatible Server-Sent Events streams.

  Designed for use with Req's `into:` streaming callback. Accumulates content deltas
  from chunked SSE responses and extracts usage metadata on completion.
  """

  use Boundary, deps: [], exports: :all

  require Logger

  @doc """
  Returns initial accumulator state for SSE stream parsing.
  """
  @spec new() :: map()
  def new do
    %{
      buffer: "",
      content: [],
      usage: nil,
      finish_reason: nil,
      done: false
    }
  end

  @doc """
  Feeds a raw binary chunk into the parser state.

  Prepends the existing buffer to the chunk, splits on newlines, and processes
  each complete SSE line. Incomplete trailing lines are kept in the buffer.

  Returns `{events_count, updated_state}` where `events_count` is the number
  of content deltas processed (used for stall detection).
  """
  @spec feed(map(), binary()) :: {non_neg_integer(), map()}
  def feed(state, chunk) do
    full = state.buffer <> chunk
    lines = String.split(full, "\n")

    # The last element is either "" (if chunk ended with \n) or an incomplete line
    {complete_lines, [remainder]} = Enum.split(lines, -1)

    state = %{state | buffer: remainder}

    Enum.reduce(complete_lines, {0, state}, fn line, {count, acc} ->
      process_line(String.trim(line), count, acc)
    end)
  end

  @doc """
  Finalizes the parsed stream and returns the content and metadata.

  Returns `{:ok, content_string, metadata}` on success, or
  `{:error, :incomplete_stream}` if the stream ended without content or
  the [DONE] sentinel.
  """
  @spec finish(map()) :: {:ok, binary(), map()} | {:error, :incomplete_stream | :partial_stream}
  def finish(%{done: false, content: []}) do
    {:error, :incomplete_stream}
  end

  def finish(%{done: false}) do
    {:error, :partial_stream}
  end

  def finish(state) do
    content =
      state.content
      |> Enum.reverse()
      |> IO.iodata_to_binary()

    usage = state.usage || %{}

    {:ok, content,
     %{
       prompt_tokens: Map.get(usage, "prompt_tokens", 0),
       completion_tokens: Map.get(usage, "completion_tokens", 0),
       estimated_cost: Map.get(usage, "estimated_cost"),
       finish_reason: state.finish_reason,
       truncated: state.finish_reason == "length"
     }}
  end

  # Skip empty lines (SSE event separators)
  defp process_line("", count, state), do: {count, state}

  # Skip SSE comment lines
  defp process_line(":" <> _rest, count, state), do: {count, state}

  # Process data lines
  defp process_line("data: [DONE]", count, state) do
    {count, %{state | done: true}}
  end

  defp process_line("data: " <> json, count, state) do
    case Jason.decode(json) do
      {:ok, data} ->
        state = extract_usage(state, data)
        state = extract_finish_reason(state, data)
        {delta_count, state} = extract_content(state, data)
        {count + delta_count, state}

      {:error, reason} ->
        Logger.warning("SSE JSON parse failed",
          error: inspect(reason),
          data: String.slice(json, 0, 200)
        )

        {count, state}
    end
  end

  # Skip any unrecognized lines
  defp process_line(_line, count, state), do: {count, state}

  defp extract_usage(state, %{"usage" => usage}) when is_map(usage) do
    %{state | usage: usage}
  end

  defp extract_usage(state, _data), do: state

  defp extract_finish_reason(state, data) do
    case get_in(data, ["choices", Access.at(0), "finish_reason"]) do
      nil -> state
      reason -> %{state | finish_reason: reason}
    end
  end

  defp extract_content(state, data) do
    case get_in(data, ["choices", Access.at(0), "delta", "content"]) do
      content when is_binary(content) and content != "" ->
        {1, %{state | content: [content | state.content]}}

      _other ->
        {0, state}
    end
  end
end
