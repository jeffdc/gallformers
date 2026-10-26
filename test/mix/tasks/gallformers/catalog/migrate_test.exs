defmodule Mix.Tasks.Gallformers.Catalog.MigrateTest do
  # Not async: changes the application environment.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Gallformers.Catalog.Migrate

  setup do
    previous = Application.fetch_env(:gallformers, :s3_enabled)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:gallformers, :s3_enabled, value)
        :error -> Application.delete_env(:gallformers, :s3_enabled)
      end
    end)
  end

  describe "configure_storage/1" do
    test "--no-s3 turns S3 off, so a rehearsal never writes to the real private bucket" do
      Application.put_env(:gallformers, :s3_enabled, true)

      :ok = Migrate.configure_storage(no_s3: true)

      assert Application.get_env(:gallformers, :s3_enabled) == false
    end

    test "without --no-s3 the configured S3 setting is left alone" do
      Application.put_env(:gallformers, :s3_enabled, true)

      :ok = Migrate.configure_storage([])

      assert Application.get_env(:gallformers, :s3_enabled) == true
    end
  end
end
