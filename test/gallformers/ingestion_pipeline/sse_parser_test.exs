defmodule Gallformers.IngestionPipeline.SSEParserTest do
  use ExUnit.Case, async: true

  alias Gallformers.IngestionPipeline.SSEParser

  describe "new/0" do
    test "returns initial accumulator state" do
      state = SSEParser.new()

      assert state == %{
               buffer: "",
               content: [],
               usage: nil,
               finish_reason: nil,
               done: false
             }
    end
  end

  describe "feed/2" do
    test "parses a single complete SSE event with content delta" do
      state = SSEParser.new()

      chunk =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}],\"usage\":null}\n\n"

      {events_count, updated} = SSEParser.feed(state, chunk)

      assert events_count == 1
      assert updated.content == ["Hello"]
      assert updated.buffer == ""
      assert updated.done == false
    end

    test "parses multiple events in one chunk (TCP coalescing)" do
      state = SSEParser.new()

      chunk =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}],\"usage\":null}\n\ndata: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" world\"},\"finish_reason\":null}],\"usage\":null}\n\n"

      {events_count, updated} = SSEParser.feed(state, chunk)

      assert events_count == 2
      # content is reversed (iolist built by prepending)
      assert updated.content == [" world", "Hello"]
    end

    test "parses event split across two chunks (TCP fragmentation)" do
      state = SSEParser.new()

      # Split mid-JSON: the JSON is cut in the middle of "Hello"
      full_event =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}],\"usage\":null}\n\n"

      # Split at an arbitrary point in the middle
      split_point = 40
      chunk1 = String.slice(full_event, 0, split_point)
      chunk2 = String.slice(full_event, split_point, String.length(full_event) - split_point)

      {events_count1, state1} = SSEParser.feed(state, chunk1)
      # First chunk doesn't complete any event
      assert events_count1 == 0
      assert state1.buffer != ""

      {events_count2, state2} = SSEParser.feed(state1, chunk2)
      assert events_count2 == 1
      assert state2.content == ["Hello"]
      assert state2.buffer == ""
    end

    test "handles [DONE] sentinel" do
      state = SSEParser.new()
      chunk = "data: [DONE]\n\n"

      {events_count, updated} = SSEParser.feed(state, chunk)

      assert events_count == 0
      assert updated.done == true
    end

    test "extracts usage from final chunk with continuous_usage_stats" do
      state = SSEParser.new()

      chunk =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12,\"estimated_cost\":0.00123}}\n\n"

      {_events_count, updated} = SSEParser.feed(state, chunk)

      assert updated.usage == %{
               "prompt_tokens" => 10,
               "completion_tokens" => 2,
               "total_tokens" => 12,
               "estimated_cost" => 0.00123
             }

      assert updated.finish_reason == "stop"
    end

    test "handles finish_reason length" do
      state = SSEParser.new()

      chunk =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"length\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":8192,\"total_tokens\":8202}}\n\n"

      {_events_count, updated} = SSEParser.feed(state, chunk)
      assert updated.finish_reason == "length"
    end

    test "handles SSE comment lines" do
      state = SSEParser.new()

      chunk =
        ": this is a comment\ndata: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}],\"usage\":null}\n\n"

      {events_count, updated} = SSEParser.feed(state, chunk)

      assert events_count == 1
      assert updated.content == ["Hi"]
    end

    test "handles empty content delta" do
      state = SSEParser.new()

      # Some providers send empty string content
      chunk_empty =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"\"},\"finish_reason\":null}],\"usage\":null}\n\n"

      {events_count, updated} = SSEParser.feed(state, chunk_empty)
      assert events_count == 0
      assert updated.content == []

      # Some providers send null content
      chunk_null =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{\"content\":null},\"finish_reason\":null}],\"usage\":null}\n\n"

      {events_count2, updated2} = SSEParser.feed(state, chunk_null)
      assert events_count2 == 0
      assert updated2.content == []

      # Delta with no content key at all (e.g., finish chunk)
      chunk_no_content =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":null}],\"usage\":null}\n\n"

      {events_count3, updated3} = SSEParser.feed(state, chunk_no_content)
      assert events_count3 == 0
      assert updated3.content == []
    end
  end

  describe "finish/1" do
    test "finish_reason stop produces truncated: false" do
      state = SSEParser.new()

      events =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello world\"},\"finish_reason\":null}],\"usage\":null}\n\ndata: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12}}\n\ndata: [DONE]\n\n"

      {_count, state} = SSEParser.feed(state, events)
      {:ok, content, meta} = SSEParser.finish(state)

      assert content == "Hello world"
      assert meta.prompt_tokens == 10
      assert meta.completion_tokens == 2
      assert meta.finish_reason == "stop"
      assert meta.truncated == false
      assert meta.estimated_cost == nil
    end

    test "finish_reason length produces truncated: true" do
      state = SSEParser.new()

      events =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"partial\"},\"finish_reason\":null}],\"usage\":null}\n\ndata: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"length\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":8192,\"total_tokens\":8202}}\n\ndata: [DONE]\n\n"

      {_count, state} = SSEParser.feed(state, events)
      {:ok, content, meta} = SSEParser.finish(state)

      assert content == "partial"
      assert meta.truncated == true
      assert meta.finish_reason == "length"
    end

    test "handles missing estimated_cost gracefully" do
      state = SSEParser.new()

      events =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}],\"usage\":null}\n\ndata: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":1,\"total_tokens\":6}}\n\ndata: [DONE]\n\n"

      {_count, state} = SSEParser.feed(state, events)
      {:ok, _content, meta} = SSEParser.finish(state)

      assert meta.estimated_cost == nil
    end

    test "handles estimated_cost when present" do
      state = SSEParser.new()

      events =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}],\"usage\":null}\n\ndata: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":1,\"total_tokens\":6,\"estimated_cost\":0.00042}}\n\ndata: [DONE]\n\n"

      {_count, state} = SSEParser.feed(state, events)
      {:ok, _content, meta} = SSEParser.finish(state)

      assert meta.estimated_cost == 0.00042
    end

    test "returns error on empty/incomplete stream" do
      state = SSEParser.new()

      assert {:error, :incomplete_stream} = SSEParser.finish(state)
    end

    test "returns error on partial stream (content received but no [DONE])" do
      state = SSEParser.new()

      chunk =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"partial data\"},\"finish_reason\":null}],\"usage\":null}\n\n"

      {_count, state} = SSEParser.feed(state, chunk)

      assert {:error, :partial_stream} = SSEParser.finish(state)
    end

    test "content iolist is joined correctly from multiple deltas" do
      state = SSEParser.new()

      chunk1 =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}],\"usage\":null}\n\n"

      chunk2 =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" beautiful\"},\"finish_reason\":null}],\"usage\":null}\n\n"

      chunk3 =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" world\"},\"finish_reason\":null}],\"usage\":null}\n\n"

      done =
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"Qwen/Qwen2.5-72B-Instruct\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":3,\"total_tokens\":13}}\n\ndata: [DONE]\n\n"

      {_, state} = SSEParser.feed(state, chunk1)
      {_, state} = SSEParser.feed(state, chunk2)
      {_, state} = SSEParser.feed(state, chunk3)
      {_, state} = SSEParser.feed(state, done)

      {:ok, content, _meta} = SSEParser.finish(state)

      assert content == "Hello beautiful world"
    end
  end
end
