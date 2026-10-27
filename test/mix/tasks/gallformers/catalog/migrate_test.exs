defmodule Mix.Tasks.Gallformers.Catalog.MigrateTest do
  # Not async: changes the application environment.
  use ExUnit.Case, async: false

  alias Gallformers.CatalogMigration.Curated
  alias Gallformers.CatalogMigration.NameSuffixes
  alias Gallformers.Storage.Private
  alias Gallformers.Storage.PrivateStub
  alias Mix.Tasks.Gallformers.Catalog.Migrate

  setup do
    for key <- [:s3_enabled, :private_storage] do
      previous = Application.fetch_env(:gallformers, key)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:gallformers, key, value)
          :error -> Application.delete_env(:gallformers, key)
        end
      end)
    end

    :ok
  end

  describe "configure_storage/1" do
    test "--no-s3 turns S3 off, so a rehearsal never writes to the real private bucket" do
      Application.put_env(:gallformers, :s3_enabled, true)

      :ok = Migrate.configure_storage(no_s3: true)

      assert Application.get_env(:gallformers, :s3_enabled) == false
    end

    test "--no-s3 stores private objects through S3, which it turned off, never a configured stub" do
      # `MIX_ENV=test` configures the in-memory stub, which only a test run starts
      # (`make test-db` runs the task in that environment).
      assert Private.adapter() == PrivateStub

      :ok = Migrate.configure_storage(no_s3: true)

      assert Private.adapter() == Private.S3Adapter
      assert Private.bucket() == "gallformers-private"
      assert Private.put("sources/58/notes/1/abc.txt", "a note") == :ok
    end

    test "without --no-s3 the configured S3 setting is left alone" do
      Application.put_env(:gallformers, :s3_enabled, true)

      :ok = Migrate.configure_storage([])

      assert Application.get_env(:gallformers, :s3_enabled) == true
    end
  end

  describe "curated_paths/1" do
    setup do
      dir = Path.join(System.tmp_dir!(), "migrate_curated_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)
      %{dir: dir}
    end

    test "--curated reads every curated input and the name suffixes from the directory", %{
      dir: dir
    } do
      inputs = Curated.inputs() ++ [:name_suffixes]
      for input <- inputs, do: File.write!(Path.join(dir, "#{input}.csv"), "")

      assert Map.new(Migrate.curated_paths(dir)) ==
               Map.new(inputs, &{&1, Path.join(dir, "#{&1}.csv")})
    end

    test "a file missing from the directory falls back to the shipped one", %{dir: dir} do
      File.write!(Path.join(dir, "aliases.csv"), "")

      paths = Migrate.curated_paths(dir)

      assert paths[:aliases] == Path.join(dir, "aliases.csv")
      assert paths[:non_galls] == Curated.default_path(:non_galls)
      assert paths[:kingdoms] == Curated.default_path(:kingdoms)
      assert paths[:name_suffixes] == NameSuffixes.default_path()
    end
  end
end
