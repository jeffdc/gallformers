defmodule Gallformers.IngestionPipeline.BroadcasterTest do
  use ExUnit.Case, async: true

  alias Gallformers.IngestionPipeline.Broadcaster

  describe "subscribe/1" do
    test "isolates broadcasts to the ingestion-specific topic" do
      assert :ok = Broadcaster.subscribe(42)

      assert :ok = Broadcaster.broadcast_stage_complete(42, :extract)
      assert_receive {:stage_complete, :extract}

      assert :ok = Broadcaster.broadcast_stage_complete(43, :extract)
      refute_receive {:stage_complete, :extract}
    end
  end

  describe "broadcast helpers" do
    test "emit the expected messages to subscribers" do
      assert :ok = Broadcaster.subscribe(42)

      assert :ok = Broadcaster.broadcast_progress(42, :preprocess, 25)
      assert_receive {:progress, :preprocess, 25}

      assert :ok = Broadcaster.broadcast_error(42, :metadata, :timeout)
      assert_receive {:error, :metadata, :timeout}

      assert :ok = Broadcaster.broadcast_duplicate_review(42, [%{candidate_id: 7}])
      assert_receive {:needs_duplicate_review, [%{candidate_id: 7}]}

      assert :ok = Broadcaster.broadcast_review_ready(42)
      assert_receive {:review_ready, 42}
    end

    test "delivers the same message to multiple subscribers" do
      parent = self()
      other_subscriber = spawn_link(fn -> subscriber_loop(parent, 42) end)

      assert_receive {:subscriber_ready, ^other_subscriber}

      assert :ok = Broadcaster.subscribe(42)
      assert :ok = Broadcaster.broadcast_progress(42, :assemble, 80)

      assert_receive {:progress, :assemble, 80}
      assert_receive {:subscriber_message, ^other_subscriber, {:progress, :assemble, 80}}
    end

    test "broadcast_chunk_progress delivers chunk progress to subscribers" do
      assert :ok = Broadcaster.subscribe(42)

      progress = %{chunk: 3, total_chunks: 12, tokens: 847, tokens_per_sec: 142.0}
      assert :ok = Broadcaster.broadcast_chunk_progress(42, :data_extract, progress)
      assert_receive {:chunk_progress, :data_extract, ^progress}
    end

    test "broadcast_chunk_warning delivers chunk warning to subscribers" do
      assert :ok = Broadcaster.subscribe(42)

      warning = %{message: "Output truncated at 8192 tokens", chunk: 3}
      assert :ok = Broadcaster.broadcast_chunk_warning(42, :data_extract, warning)
      assert_receive {:chunk_warning, :data_extract, ^warning}
    end

    test "does not deliver broadcasts to non-subscribers" do
      parent = self()
      listener = spawn_link(fn -> non_subscriber_loop(parent) end)

      send(listener, :check_mailbox)
      assert_receive {:mailbox_empty, ^listener}

      assert :ok = Broadcaster.broadcast_error(99, :upload, :failed)

      send(listener, :check_mailbox)
      assert_receive {:mailbox_empty, ^listener}
    end
  end

  defp subscriber_loop(parent, ingestion_id) do
    :ok = Broadcaster.subscribe(ingestion_id)
    send(parent, {:subscriber_ready, self()})

    receive do
      message ->
        send(parent, {:subscriber_message, self(), message})
    end
  end

  defp non_subscriber_loop(parent) do
    receive do
      :check_mailbox ->
        receive do
          message ->
            send(parent, {:unexpected_message, self(), message})
        after
          25 ->
            send(parent, {:mailbox_empty, self()})
        end

        non_subscriber_loop(parent)
    end
  end
end
