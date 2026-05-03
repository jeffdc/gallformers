defmodule Gallformers.IngestionPipeline.Stages.AssembleTest do
  use Gallformers.DataCase, async: false

  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.Stages.Assemble
  alias Gallformers.Ingestions
  alias Gallformers.Repo
  alias Gallformers.Species
  alias Gallformers.Species.Species, as: SpeciesRecord
  alias Gallformers.Storage.SourceArtifacts

  defmodule StorageBackendStub do
    @behaviour Gallformers.Storage.SourceArtifacts.Backend

    @impl true
    def upload(bucket, path, content, content_type) do
      send(test_pid(), {:upload, bucket, path, content, content_type})
      {:ok, %{}}
    end

    @impl true
    def get_object(bucket, path) do
      send(test_pid(), {:get_object, bucket, path})

      case Map.fetch(fixtures(), path) do
        {:ok, body} -> {:ok, %{body: body}}
        :error -> {:error, :not_found}
      end
    end

    @impl true
    def list_objects(_bucket, _prefix, _continuation_token),
      do: {:ok, %{keys: [], next_continuation_token: nil}}

    @impl true
    def delete_objects(_bucket, _keys), do: {:ok, %{}}

    @impl true
    def copy_object(_dest_bucket, _dest_path, _src_bucket, _src_path), do: {:ok, %{}}

    defp fixtures, do: Process.get(:assemble_storage_fixtures, %{})
    defp test_pid, do: Process.get(:assemble_test_pid, self())
  end

  setup do
    previous_storage_config = Application.get_env(:gallformers, SourceArtifacts)

    Process.put(:assemble_test_pid, self())
    Application.put_env(:gallformers, SourceArtifacts, backend: StorageBackendStub)

    on_exit(fn ->
      Process.delete(:assemble_storage_fixtures)
      Process.delete(:assemble_test_pid)

      if previous_storage_config == nil do
        Application.delete_env(:gallformers, SourceArtifacts)
      else
        Application.put_env(:gallformers, SourceArtifacts, previous_storage_config)
      end
    end)

    :ok
  end

  test "builds markdown with frontmatter, traits, species resolution, and uploads the artifact" do
    ingestion = source_ingestion_fixture()
    gall = create_species("Resolved Gall #{System.unique_integer([:positive])}", "gall")
    host = create_species("Resolved Host #{System.unique_integer([:positive])}", "plant")
    host_alias = "Host Alias #{System.unique_integer([:positive])}"
    {:ok, _alias} = Species.create_alias_for_species(host.id, %{name: host_alias, type: "common"})

    metadata = %{
      "title" => "Gall Paper",
      "authors" => ["Smith, J.", "Jones, A."],
      "year" => 2026,
      "doi" => "10.1234/gall.paper"
    }

    records = [
      %{
        "gall_species" => %{"name" => gall.name, "authority" => nil},
        "host_species" => %{"name" => host_alias, "authority" => nil},
        "traits" => %{
          "shape" => %{"original" => "urn-shaped", "suggested" => ["cup", "globular"]},
          "detachable" => "detachable"
        },
        "description" => "Rounded woody gall on oak twigs.",
        "confidence" => 0.92
      }
    ]

    data_path = "source-ingestions/#{ingestion.id}/data_extract/output.json"
    metadata_path = "source-ingestions/#{ingestion.id}/metadata/output.json"
    output_path = "source-ingestions/#{ingestion.id}/assemble/output.md"

    put_storage_fixtures(%{
      data_path => Jason.encode!(records),
      metadata_path => Jason.encode!(metadata)
    })

    Broadcaster.subscribe(ingestion.id)

    assert {:ok, updated_ingestion} = Assemble.perform_stage(ingestion)

    assert_received {:get_object, _, ^data_path}
    assert_received {:get_object, _, ^metadata_path}
    assert_received {:upload, _, ^output_path, markdown, "text/markdown"}
    assert_receive {:stage_complete, :assemble}

    assert markdown =~ "---\ntitle: \"Gall Paper\""
    assert markdown =~ "authors:\n  - \"Smith, J.\"\n  - \"Jones, A.\""
    assert markdown =~ "year: 2026"
    assert markdown =~ "doi: \"10.1234/gall.paper\"\n---"
    assert markdown =~ "## #{gall.name}"
    assert markdown =~ "Description:\n\nRounded woody gall on oak twigs."
    assert markdown =~ "| trait name | original text | suggested value |"
    assert markdown =~ "| shape | urn-shaped | cup, globular |"
    assert markdown =~ "| detachable |  | detachable |"
    assert markdown =~ "Host species: #{host_alias}"

    assert markdown =~
             "Gall species resolution: resolved as #{gall.name} (species_id: #{gall.id})"

    assert markdown =~
             "Host species resolution: resolved as #{host.name} (species_id: #{host.id})"

    refute markdown =~ "<!-- UNRESOLVED:"
    assert markdown =~ "Confidence: 0.92"

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion.id)
    assert updated_ingestion.processing_stage == "assemble"
    assert reloaded_ingestion.processing_stage == "assemble"
    assert reloaded_ingestion.status == "processing"
  end

  test "memoizes species resolution lookups across repeated records" do
    ingestion = source_ingestion_fixture()
    gall = create_species("Repeated Gall #{System.unique_integer([:positive])}", "gall")
    host = create_species("Repeated Host #{System.unique_integer([:positive])}", "plant")

    records =
      for idx <- 1..3 do
        %{
          "gall_species" => %{"name" => "  #{gall.name}  "},
          "host_species" => %{"name" => host.name},
          "traits" => %{},
          "description" => "Repeated record #{idx}",
          "confidence" => 0.8
        }
      end

    data_path = "source-ingestions/#{ingestion.id}/data_extract/output.json"
    metadata_path = "source-ingestions/#{ingestion.id}/metadata/output.json"

    put_storage_fixtures(%{
      data_path => Jason.encode!(records),
      metadata_path => Jason.encode!(%{"title" => "Repeated names"})
    })

    query_count =
      count_species_resolution_queries(fn ->
        assert {:ok, _updated_ingestion} = Assemble.perform_stage(ingestion)
      end)

    assert query_count == 4
    assert_received {:upload, _, _, markdown, "text/markdown"}
    assert count_occurrences(markdown, "Gall species resolution: resolved as #{gall.name}") == 3
    assert count_occurrences(markdown, "Host species resolution: resolved as #{host.name}") == 3
  end

  test "flags unresolved names when there are zero matches" do
    ingestion = source_ingestion_fixture()

    data_path = "source-ingestions/#{ingestion.id}/data_extract/output.json"
    metadata_path = "source-ingestions/#{ingestion.id}/metadata/output.json"

    put_storage_fixtures(%{
      data_path =>
        Jason.encode!([
          %{
            "gall_species" => %{"name" => "Missing Gall #{System.unique_integer([:positive])}"},
            "host_species" => %{"name" => "Missing Host #{System.unique_integer([:positive])}"},
            "traits" => %{},
            "description" => "No species match exists.",
            "confidence" => 0.5
          }
        ]),
      metadata_path => Jason.encode!(%{"title" => "Unresolved"})
    })

    assert {:ok, _updated_ingestion} = Assemble.perform_stage(ingestion)

    assert_received {:upload, _, _, markdown, "text/markdown"}
    assert markdown =~ "Gall species resolution: unresolved (0 matches)"
    assert markdown =~ "Host species resolution: unresolved (0 matches)"
    assert markdown =~ "<!-- UNRESOLVED: Missing Gall"
    assert markdown =~ "<!-- UNRESOLVED: Missing Host"
  end

  test "accepts fenced json artifacts from earlier pipeline stages" do
    ingestion = source_ingestion_fixture()

    data_path = "source-ingestions/#{ingestion.id}/data_extract/output.json"
    metadata_path = "source-ingestions/#{ingestion.id}/metadata/output.json"

    put_storage_fixtures(%{
      data_path =>
        """
        ```json
        [
          {
            "gall_species": {"name": "Fenced Gall"},
            "host_species": {"name": "Fenced Host"},
            "traits": {},
            "description": "Fenced payload.",
            "confidence": 0.5
          }
        ]
        ```
        """,
      metadata_path =>
        """
        ```json
        {
          "title": "Fenced Metadata"
        }
        ```
        """
    })

    assert {:ok, _updated_ingestion} = Assemble.perform_stage(ingestion)

    assert_received {:upload, _, _, markdown, "text/markdown"}
    assert markdown =~ "title: \"Fenced Metadata\""
    assert markdown =~ "## Fenced Gall"
  end

  test "flags unresolved names when multiple matches are found" do
    ingestion = source_ingestion_fixture()
    query = "Ambiguous Species #{System.unique_integer([:positive])}"

    create_species("#{query} alpha", "gall")
    create_species("#{query} beta", "gall")
    create_species("#{query} host alpha", "plant")
    create_species("#{query} host beta", "plant")

    data_path = "source-ingestions/#{ingestion.id}/data_extract/output.json"
    metadata_path = "source-ingestions/#{ingestion.id}/metadata/output.json"

    put_storage_fixtures(%{
      data_path =>
        Jason.encode!([
          %{
            "gall_species" => %{"name" => query},
            "host_species" => %{"name" => "#{query} host"},
            "traits" => %{},
            "description" => "Multiple matches should stay unresolved.",
            "confidence" => 0.61
          }
        ]),
      metadata_path => Jason.encode!(%{"title" => "Ambiguous"})
    })

    assert {:ok, _updated_ingestion} = Assemble.perform_stage(ingestion)

    assert_received {:upload, _, _, markdown, "text/markdown"}
    assert markdown =~ "Gall species resolution: unresolved (2 matches)"
    assert markdown =~ "Host species resolution: unresolved (2 matches)"
    assert markdown =~ "<!-- UNRESOLVED: #{query} -->"
    assert markdown =~ "<!-- UNRESOLVED: #{query} host -->"
  end

  defp source_ingestion_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          input_type: "pdf",
          status: "processing",
          processing_stage: "data_extract"
        },
        attrs
      )

    {:ok, ingestion} = Ingestions.create_source_ingestion(attrs)
    ingestion
  end

  defp put_storage_fixtures(fixtures) do
    Process.put(:assemble_storage_fixtures, fixtures)
  end

  defp create_species(name, taxoncode) do
    Repo.insert!(%SpeciesRecord{name: name, taxoncode: taxoncode, datacomplete: false})
  end

  defp count_species_resolution_queries(fun) do
    handler_id = "assemble-query-counter-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:gallformers, :repo, :query],
        fn _event_name, _measurements, metadata, pid ->
          if species_resolution_query?(metadata.query) do
            send(pid, :species_resolution_query)
          end
        end,
        self()
      )

    try do
      fun.()
      drain_species_resolution_queries(0)
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_species_resolution_queries(count) do
    receive do
      :species_resolution_query -> drain_species_resolution_queries(count + 1)
    after
      0 -> count
    end
  end

  defp species_resolution_query?(query) when is_binary(query) do
    String.contains?(query, ~s(FROM "species" AS)) or
      String.contains?(query, ~s(FROM "alias" AS))
  end

  defp species_resolution_query?(_query), do: false

  defp count_occurrences(haystack, needle) do
    haystack
    |> String.split(needle)
    |> length()
    |> Kernel.-(1)
  end
end
