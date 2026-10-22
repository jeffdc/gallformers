defmodule Gallformers.SiteSettingsTest do
  @moduledoc """
  Unit tests for the SiteSettings context.
  """
  use Gallformers.DataCase

  alias Gallformers.SiteSettings

  describe "get/1" do
    test "returns nil for missing key" do
      assert SiteSettings.get("nonexistent_key") == nil
    end
  end

  describe "get/2" do
    test "returns default for missing key" do
      assert SiteSettings.get("nonexistent_key", "fallback") == "fallback"
    end

    test "returns default false for missing boolean key" do
      assert SiteSettings.get("missing_bool", false) == false
    end
  end

  describe "set/2 and get/1 round-trip" do
    test "stores and retrieves a string value" do
      assert :ok = SiteSettings.set("test_string", "hello world")
      assert SiteSettings.get("test_string") == "hello world"
    end

    test "stores and retrieves a boolean true" do
      assert :ok = SiteSettings.set("test_bool_true", true)
      assert SiteSettings.get("test_bool_true") == true
    end

    test "stores and retrieves a boolean false" do
      assert :ok = SiteSettings.set("test_bool_false", false)
      assert SiteSettings.get("test_bool_false") == false
    end

    test "stores and retrieves an integer" do
      assert :ok = SiteSettings.set("test_int", 42)
      assert SiteSettings.get("test_int") == 42
    end

    test "stores and retrieves a map" do
      value = %{"nested" => "data", "count" => 3}
      assert :ok = SiteSettings.set("test_map", value)
      assert SiteSettings.get("test_map") == value
    end

    test "stores and retrieves a list" do
      value = [1, "two", true]
      assert :ok = SiteSettings.set("test_list", value)
      assert SiteSettings.get("test_list") == value
    end

    test "stores and retrieves nil value" do
      assert :ok = SiteSettings.set("test_nil", nil)
      assert SiteSettings.get("test_nil") == nil
    end
  end

  describe "set/2 upsert behavior" do
    test "overwrites existing value" do
      assert :ok = SiteSettings.set("upsert_key", "first")
      assert SiteSettings.get("upsert_key") == "first"

      assert :ok = SiteSettings.set("upsert_key", "second")
      assert SiteSettings.get("upsert_key") == "second"
    end

    test "changes value type on upsert" do
      assert :ok = SiteSettings.set("type_change", "string_value")
      assert SiteSettings.get("type_change") == "string_value"

      assert :ok = SiteSettings.set("type_change", 123)
      assert SiteSettings.get("type_change") == 123
    end
  end

  describe "convenience functions with defaults" do
    test "banner_enabled? returns false by default" do
      assert SiteSettings.banner_enabled?() == false
    end

    test "banner_text returns empty string by default" do
      assert SiteSettings.banner_text() == ""
    end

    test "read_only? returns false by default" do
      assert SiteSettings.read_only?() == false
    end
  end

  describe "convenience functions after set" do
    test "banner_enabled? returns true after setting" do
      SiteSettings.set("banner_enabled", true)
      assert SiteSettings.banner_enabled?() == true
    end

    test "banner_text returns value after setting" do
      SiteSettings.set("banner_text", "Site is under maintenance")
      assert SiteSettings.banner_text() == "Site is under maintenance"
    end

    test "read_only? returns true after setting" do
      SiteSettings.set("read_only", true)
      assert SiteSettings.read_only?() == true
    end
  end

  describe "reset_site_settings/0" do
    test "discards a setting whose broadcast the GenServer has not processed yet" do
      server = Process.whereis(SiteSettings)
      test_pid = self()

      # Park the GenServer inside a :sys callback so the broadcast from set/2
      # is still in its mailbox when the reset runs.
      parked =
        Task.async(fn ->
          :sys.replace_state(server, fn state ->
            send(test_pid, :server_parked)

            receive do
              :release -> state
            end
          end)
        end)

      assert_receive :server_parked
      SiteSettings.set("read_only", true)
      Process.send_after(server, :release, 50)

      reset_site_settings()
      Task.await(parked)
      :sys.get_state(server)

      refute SiteSettings.read_only?()
    end
  end
end
