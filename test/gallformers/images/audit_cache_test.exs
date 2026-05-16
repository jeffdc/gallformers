defmodule Gallformers.Images.AuditCacheTest do
  @moduledoc """
  Unit tests for the Images.AuditCache GenServer.
  """
  use Gallformers.DataCase

  import ExUnit.CaptureLog

  alias Ecto.Adapters.SQL.Sandbox
  alias Gallformers.Images.AuditCache

  # Use a unique name for test instances to avoid conflicts with the application's cache
  defp start_test_cache(opts \\ []) do
    name = :"test_cache_#{System.unique_integer([:positive])}"
    opts = Keyword.put(opts, :name, name)
    {:ok, pid} = AuditCache.start_link(opts)
    # Allow the GenServer to access the test's sandbox connection
    Sandbox.allow(Gallformers.Repo, self(), pid)
    {pid, name}
  end

  describe "start_link/1" do
    test "starts the GenServer" do
      {pid, _name} = start_test_cache()
      assert Process.alive?(pid) == true
      GenServer.stop(pid)
    end
  end

  describe "status/0" do
    test "returns initial status with empty cache" do
      {pid, name} = start_test_cache()

      status = GenServer.call(name, :status)

      assert status.count == 0
      assert status.last_scanned == nil
      assert status.stale? == true
      assert status.scanning? == false
      assert status.error == nil

      GenServer.stop(pid)
    end
  end

  describe "get_count/0" do
    test "returns count and stale flag" do
      {pid, name} = start_test_cache()

      {count, stale?} = GenServer.call(name, :get_count)

      assert count == 0
      assert stale? == true

      GenServer.stop(pid)
    end
  end

  describe "get_orphans/1" do
    test "returns empty list initially with stale flag" do
      {pid, name} = start_test_cache()

      {orphans, total, stale?} = GenServer.call(name, {:get_orphans, []})

      assert orphans == []
      assert total == 0
      assert stale? == true

      GenServer.stop(pid)
    end

    test "respects pagination options" do
      {pid, name} = start_test_cache()

      # First request
      {orphans, _total, _stale?} =
        GenServer.call(name, {:get_orphans, [page: 1, per_page: 10]})

      assert is_list(orphans)

      GenServer.stop(pid)
    end
  end

  describe "refresh/0" do
    test "triggers a scan" do
      {pid, name} = start_test_cache()

      # Check initial state
      status_before = GenServer.call(name, :status)
      assert status_before.last_scanned == nil

      # Trigger refresh
      GenServer.cast(name, :refresh)

      # Give the async task a moment to start
      Process.sleep(50)

      # Status should show the scan completed (with s3_enabled: false, it completes instantly)
      status_after = GenServer.call(name, :status)
      assert status_after.last_scanned != nil

      GenServer.stop(pid)
    end
  end

  describe "TTL behavior" do
    test "marks cache as stale after TTL expires" do
      # TTL must be long enough that the GenServer call after the initial sleep
      # completes well within it, even under parallel test load.
      {pid, name} = start_test_cache(ttl_ms: 200)

      # Simulate a completed scan by sending the message directly
      send(pid, {:scan_complete, []})

      # Give it a moment to process
      Process.sleep(20)

      # Should not be stale yet
      status1 = GenServer.call(name, :status)
      assert status1.stale? == false

      # Wait for TTL to expire
      Process.sleep(250)

      # Should be stale now
      status2 = GenServer.call(name, :status)
      assert status2.stale? == true

      GenServer.stop(pid)
    end
  end

  describe "get_count and get_orphans do not auto-trigger scans" do
    test "get_count does not trigger a scan when stale" do
      {pid, name} = start_test_cache()

      # Cache is stale (never scanned), but calling get_count should NOT trigger a scan
      {0, true} = GenServer.call(name, :get_count)
      Process.sleep(50)

      status = GenServer.call(name, :status)
      assert status.last_scanned == nil
      assert status.scanning? == false

      GenServer.stop(pid)
    end

    test "get_orphans does not trigger a scan when stale" do
      {pid, name} = start_test_cache()

      {[], 0, true} = GenServer.call(name, {:get_orphans, []})
      Process.sleep(50)

      status = GenServer.call(name, :status)
      assert status.last_scanned == nil
      assert status.scanning? == false

      GenServer.stop(pid)
    end
  end

  describe "scan_complete sets data correctly" do
    test "stores orphans and updates count and timestamp" do
      {pid, name} = start_test_cache()

      orphans = [
        %{key: "gall/1/1_123_original.jpg", size: "1000", last_modified: "2026-01-01"},
        %{key: "gall/2/2_456_original.jpg", size: "2000", last_modified: "2026-01-02"}
      ]

      send(pid, {:scan_complete, orphans})
      Process.sleep(10)

      {count, false} = GenServer.call(name, :get_count)
      assert count == 2

      {page, 2, false} = GenServer.call(name, {:get_orphans, [page: 1, per_page: 10]})
      assert length(page) == 2

      status = GenServer.call(name, :status)
      assert status.last_scanned != nil
      assert status.scanning? == false

      GenServer.stop(pid)
    end
  end

  describe "scan_error handling" do
    test "records error and clears scanning flag" do
      {pid, name} = start_test_cache()

      log =
        capture_log([level: :error], fn ->
          send(pid, {:scan_error, :timeout})
          Process.sleep(10)
        end)

      assert log =~ "Image audit cache scan failed: :timeout"

      status = GenServer.call(name, :status)
      assert status.scanning? == false
      assert status.error == :timeout

      GenServer.stop(pid)
    end
  end

  describe "remove_path/1" do
    test "removes a single path from cached orphans" do
      {pid, name} = start_test_cache()

      orphans = [
        %{key: "gall/1/1_123_original.jpg", size: "1000", last_modified: "2026-01-01"},
        %{key: "gall/2/2_456_original.jpg", size: "2000", last_modified: "2026-01-02"},
        %{key: "gall/3/3_789_original.jpg", size: "3000", last_modified: "2026-01-03"}
      ]

      send(pid, {:scan_complete, orphans})
      Process.sleep(10)

      GenServer.cast(name, {:remove_path, "gall/2/2_456_original.jpg"})
      Process.sleep(10)

      {count, _stale?} = GenServer.call(name, :get_count)
      assert count == 2

      {remaining, 2, _stale?} = GenServer.call(name, {:get_orphans, []})
      keys = Enum.map(remaining, & &1.key)
      assert "gall/1/1_123_original.jpg" in keys
      assert "gall/3/3_789_original.jpg" in keys
      refute "gall/2/2_456_original.jpg" in keys

      GenServer.stop(pid)
    end

    test "no-op when path not in cache" do
      {pid, name} = start_test_cache()

      send(
        pid,
        {:scan_complete,
         [%{key: "gall/1/1_123_original.jpg", size: "1000", last_modified: "2026-01-01"}]}
      )

      Process.sleep(10)

      GenServer.cast(name, {:remove_path, "nonexistent.jpg"})
      Process.sleep(10)

      {count, _stale?} = GenServer.call(name, :get_count)
      assert count == 1

      GenServer.stop(pid)
    end
  end

  describe "PubSub notification" do
    test "broadcasts :scan_complete on image_audit topic" do
      Phoenix.PubSub.subscribe(Gallformers.PubSub, "image_audit")

      {pid, _name} = start_test_cache()

      send(pid, {:scan_complete, []})

      assert_receive :scan_complete, 1000

      GenServer.stop(pid)
    end
  end
end
