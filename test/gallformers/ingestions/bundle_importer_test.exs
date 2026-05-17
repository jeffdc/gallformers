defmodule Gallformers.Ingestions.BundleImporterTest do
  use Gallformers.DataCase, async: false

  alias Gallformers.Accounts
  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.BundleImporter
  alias Gallformers.Ingestions.SourceIngestion
  alias Gallformers.Ingestions.SourceIngestionSpecies
  alias Gallformers.Repo
  alias Gallformers.Species.Species
  alias Gallformers.Storage.SourceArtifacts

  @bundle_root Path.expand("../../../services/source-ingestion/output", __DIR__)

  defmodule BundleStorageBackendStub do
    @behaviour Gallformers.Storage.SourceArtifacts.Backend

    @impl true
    def upload(bucket, path, content, content_type) do
      send(test_pid(), {:upload, bucket, path, byte_size(content), content_type})

      case Process.get(:bundle_storage_upload_result, {:ok, %{}}) do
        {:ok, _response} = ok ->
          objects = Process.get(:bundle_storage_objects, %{})
          Process.put(:bundle_storage_objects, Map.put(objects, path, %{body: content}))
          ok

        {:error, _reason} = error ->
          error
      end
    end

    @impl true
    def get_object(bucket, path) do
      send(test_pid(), {:get_object, bucket, path})

      case Process.get(:bundle_storage_objects, %{}) do
        %{^path => %{body: body}} -> {:ok, %{body: body}}
        _ -> {:error, :not_found}
      end
    end

    @impl true
    def list_objects(_bucket, prefix, _continuation_token) do
      keys =
        Process.get(:bundle_storage_objects, %{})
        |> Map.keys()
        |> Enum.filter(&String.starts_with?(&1, prefix))
        |> Enum.sort()

      {:ok, %{keys: keys, next_continuation_token: nil}}
    end

    @impl true
    def delete_objects(_bucket, keys) do
      objects =
        Process.get(:bundle_storage_objects, %{})
        |> Map.drop(keys)

      Process.put(:bundle_storage_objects, objects)
      {:ok, %{}}
    end

    @impl true
    def copy_object(_dest_bucket, _dest_path, _src_bucket, _src_path), do: {:ok, %{}}

    defp test_pid, do: Process.get(:bundle_importer_test_pid, self())
  end

  setup do
    previous_storage_config = Application.get_env(:gallformers, SourceArtifacts)

    Process.put(:bundle_importer_test_pid, self())
    Process.put(:bundle_storage_objects, %{})

    Application.put_env(:gallformers, SourceArtifacts, backend: BundleStorageBackendStub)

    on_exit(fn ->
      Process.delete(:bundle_importer_test_pid)
      Process.delete(:bundle_storage_objects)
      Process.delete(:bundle_storage_upload_result)

      if previous_storage_config == nil do
        Application.delete_env(:gallformers, SourceArtifacts)
      else
        Application.put_env(:gallformers, SourceArtifacts, previous_storage_config)
      end
    end)

    :ok
  end

  describe "extract_paper_attrs/1" do
    test "unwraps wrapped paper-level fields" do
      review_artifact = %{
        "source" => %{
          "pdf_sha256" => String.duplicate("a", 64),
          "source_text_sha256" => String.duplicate("b", 64)
        },
        "document_metadata" => %{
          "title" => %{"value" => "Some Title"},
          "authors" => [
            %{"value" => "Alice"},
            %{"value" => "Bob"}
          ],
          "year" => %{"value" => "2022"},
          "doi" => %{"value" => "10.1234/example"}
        }
      }

      attrs = BundleImporter.extract_paper_attrs(review_artifact)

      assert attrs[:input_type] == "pdf"
      assert attrs[:status] == "needs_review"
      assert attrs[:processing_stage] == "review"
      assert attrs[:title] == "Some Title"
      assert attrs[:authors] == ["Alice", "Bob"]
      assert attrs[:publication_year] == 2022
      assert attrs[:doi] == "10.1234/example"
      assert attrs[:raw_input_sha256] == String.duplicate("a", 64)
      assert attrs[:preprocessed_text_sha256] == String.duplicate("b", 64)
    end

    test "tolerates missing/null year and doi" do
      review_artifact = %{
        "source" => %{
          "pdf_sha256" => String.duplicate("a", 64),
          "source_text_sha256" => String.duplicate("b", 64)
        },
        "document_metadata" => %{
          "title" => %{"value" => "Some Title"},
          "authors" => [],
          "year" => nil,
          "doi" => nil
        }
      }

      attrs = BundleImporter.extract_paper_attrs(review_artifact)

      assert attrs[:title] == "Some Title"
      assert attrs[:authors] == []
      assert attrs[:publication_year] == nil
      assert attrs[:doi] == nil
    end
  end

  describe "extract_species_attrs/2" do
    test "maps a wrapped-shape gall record into species attrs" do
      record = %{
        "record_id" => "R_001",
        "gall_maker" => %{
          "scientific_name" => %{"value" => "Druon flocculentum"},
          "authority" => %{"value" => "Kinsey, 1937"},
          "taxonomy" => %{
            "order" => %{"value" => "Hymenoptera"},
            "family" => %{"value" => "Cynipidae"}
          },
          "aliases" => ["Cynips flocculenta"]
        },
        "hosts" => [
          %{
            "scientific_name" => %{"value" => "Quercus alba"},
            "authority" => nil,
            "taxonomy" => %{
              "family" => %{"value" => "Fagaceae"},
              "order" => %{"value" => "Fagales"}
            }
          }
        ],
        "gall_traits" => %{
          "color" => %{"original" => "brown", "suggested" => ["brown"]},
          "shape" => %{"original" => "globular", "suggested" => ["globular"]},
          "texture" => %{"original" => nil, "suggested" => []},
          "walls" => %{"original" => nil, "suggested" => []},
          "cells" => %{"original" => nil, "suggested" => []},
          "alignment" => %{"original" => nil, "suggested" => []},
          "plant_part" => %{"original" => "stem", "suggested" => ["stem"]},
          "form" => %{"original" => nil, "suggested" => []},
          "season" => %{"original" => nil, "suggested" => []},
          "detachable" => %{"value" => "integral"}
        },
        "description" => %{
          "value" => "A globular gall.",
          "evidence" => [%{"quote" => "rounded woody gall"}]
        },
        "location" => %{"value" => "on twigs"},
        "confidence_bucket" => "high"
      }

      attrs = BundleImporter.extract_species_attrs(record, 0)

      assert attrs[:position] == 0
      assert attrs[:status] == "pending"
      assert attrs[:extracted_name] == "Druon flocculentum"
      assert attrs[:extracted_authority] == "Kinsey, 1937"
      assert attrs[:description_prose] == "A globular gall."
      assert attrs[:raw_extraction] == record

      payload = attrs[:extraction_payload]
      assert payload[:gall_species][:name] == "Druon flocculentum"
      assert payload[:gall_species][:authority] == "Kinsey, 1937"
      assert payload[:gall_species][:family] == "Cynipidae"
      assert payload[:gall_species][:order] == "Hymenoptera"

      assert [host] = payload[:hosts]
      assert host[:name] == "Quercus alba"
      assert host[:family] == "Fagaceae"
      assert host[:order] == "Fagales"

      assert payload[:aliases] == ["Cynips flocculenta"]

      assert payload[:traits][:color][:original] == "brown"
      assert payload[:traits][:color][:suggested] == ["brown"]
      assert payload[:traits][:detachable] == "integral"

      assert payload[:description_evidence] == [%{text: "rounded woody gall"}]
      assert payload[:location] == "on twigs"
    end

    test "tolerates a record with null scientific_name, null description, null location, empty hosts" do
      record = %{
        "record_id" => "R_002",
        "gall_maker" => %{
          "scientific_name" => %{"value" => nil},
          "authority" => nil,
          "taxonomy" => %{
            "order" => nil,
            "family" => nil
          },
          "aliases" => []
        },
        "hosts" => [],
        "gall_traits" => %{
          "color" => %{"original" => nil, "suggested" => []},
          "shape" => %{"original" => nil, "suggested" => []},
          "texture" => %{"original" => nil, "suggested" => []},
          "walls" => %{"original" => nil, "suggested" => []},
          "cells" => %{"original" => nil, "suggested" => []},
          "alignment" => %{"original" => nil, "suggested" => []},
          "plant_part" => %{"original" => nil, "suggested" => []},
          "form" => %{"original" => nil, "suggested" => []},
          "season" => %{"original" => nil, "suggested" => []},
          "detachable" => %{"value" => "unknown"}
        },
        "description" => nil,
        "location" => nil,
        "confidence_bucket" => "low"
      }

      attrs = BundleImporter.extract_species_attrs(record, 3)

      assert attrs[:position] == 3
      assert attrs[:extracted_name] == nil
      assert attrs[:extracted_authority] == nil
      assert attrs[:description_prose] == ""
      assert attrs[:raw_extraction] == record

      payload = attrs[:extraction_payload]
      assert payload[:gall_species][:name] == nil
      assert payload[:hosts] == []
      assert payload[:aliases] == []
      assert payload[:traits][:detachable] == "unknown"
      assert payload[:description_evidence] == []
      assert payload[:location] == nil
    end
  end

  describe "import_bundle/2 happy path (cuesta)" do
    test "creates SourceIngestion + species rows and uploads artifacts" do
      user = user_fixture()
      bundle_dir = Path.join(@bundle_root, "cuesta")

      assert {:ok, %SourceIngestion{} = ingestion} =
               BundleImporter.import_bundle(bundle_dir, uploaded_by_id: user.id)

      assert is_integer(ingestion.id)
      assert ingestion.input_type == "pdf"
      assert ingestion.status == "needs_review"
      assert ingestion.processing_stage == "review"
      assert ingestion.title =~ "Druon"
      assert ingestion.publication_year == 2022
      assert ingestion.doi == "10.11646/zootaxa.5132.1.1"
      assert ingestion.uploaded_by_id == user.id
      assert is_binary(ingestion.artifacts_path)
      assert ingestion.artifacts_path != ""

      species = Ingestions.list_source_ingestion_species(ingestion.id)
      assert length(species) == 18

      [%SourceIngestionSpecies{} = first | _] = species
      assert first.position == 0
      assert first.status == "pending"
      assert is_map(first.raw_extraction)
      assert Map.has_key?(first.raw_extraction, "record_id") == true

      # PDF + review_artifact uploaded
      assert_receive {:upload, _bucket, _pdf_path, _pdf_size, "application/pdf"}
      assert_receive {:upload, _bucket, _json_path, _json_size, "application/json"}
    end
  end

  describe "import_bundle/2 across all 4 bundles" do
    @bundles ["cuesta", "cook", "mutun", "nicholls"]

    for bundle <- @bundles do
      test "imports #{bundle} bundle successfully" do
        user = user_fixture()
        bundle_dir = Path.join(@bundle_root, unquote(bundle))
        expected_count = expected_record_count(unquote(bundle))

        assert {:ok, %SourceIngestion{} = ingestion} =
                 BundleImporter.import_bundle(bundle_dir, uploaded_by_id: user.id)

        assert is_binary(ingestion.title) and ingestion.title != ""

        species = Ingestions.list_source_ingestion_species(ingestion.id)
        assert length(species) == expected_count

        [first | _] = species
        assert is_map(first.raw_extraction)
      end
    end
  end

  describe "import_bundle/2 auto-mapping" do
    test "auto-maps when only one generation of the gall exists in the DB" do
      single_gen = insert_gall_species!("Druon testus (agamic)")

      bundle_dir = build_bundle_dir!([%{"scientific_name" => "Druon testus"}])
      user = user_fixture()

      assert {:ok, %SourceIngestion{} = ingestion} =
               BundleImporter.import_bundle(bundle_dir, uploaded_by_id: user.id)

      [entry] = Ingestions.list_source_ingestion_species(ingestion.id)
      assert entry.status == "mapped"
      assert entry.species_id == single_gen.id

      File.rm_rf!(bundle_dir)
    end

    test "does NOT auto-map when multiple generations exist (ambiguous)" do
      insert_gall_species!("Druon ambiguus (agamic)")
      insert_gall_species!("Druon ambiguus (sexgen)")

      bundle_dir = build_bundle_dir!([%{"scientific_name" => "Druon ambiguus"}])
      user = user_fixture()

      assert {:ok, %SourceIngestion{} = ingestion} =
               BundleImporter.import_bundle(bundle_dir, uploaded_by_id: user.id)

      [entry] = Ingestions.list_source_ingestion_species(ingestion.id)
      assert entry.status == "pending"
      assert entry.species_id == nil

      File.rm_rf!(bundle_dir)
    end

    test "sets source_id when a Source with the bundle's title already exists" do
      {:ok, source} =
        Gallformers.Sources.create_source(%{
          title: "Auto-Match Source Title",
          author: "Tester",
          pubyear: "2026",
          link: "https://example.com/source",
          citation: "Tester. 2026. Auto-Match Source Title.",
          license: "CC-BY",
          licenselink: "https://creativecommons.org/licenses/by/4.0/"
        })

      bundle_dir =
        build_bundle_dir!([%{"scientific_name" => "Some Gall"}],
          title: "Auto-Match Source Title"
        )

      user = user_fixture()

      assert {:ok, %SourceIngestion{} = ingestion} =
               BundleImporter.import_bundle(bundle_dir, uploaded_by_id: user.id)

      assert ingestion.source_id == source.id

      File.rm_rf!(bundle_dir)
    end

    test "leaves source_id nil when no Source matches the bundle title" do
      bundle_dir =
        build_bundle_dir!([%{"scientific_name" => "Some Gall"}],
          title: "A Title That Definitely Does Not Match Any Source"
        )

      user = user_fixture()

      assert {:ok, %SourceIngestion{} = ingestion} =
               BundleImporter.import_bundle(bundle_dir, uploaded_by_id: user.id)

      assert ingestion.source_id == nil

      File.rm_rf!(bundle_dir)
    end

    test "sets species_id and status=mapped for a record matching an existing gall by name" do
      bundle_dir =
        Path.join(
          System.tmp_dir!(),
          "bundle_importer_automap_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(bundle_dir)

      pdf_sha = String.duplicate("a", 64)
      text_sha = String.duplicate("b", 64)

      File.write!(
        Path.join(bundle_dir, "review_artifact.json"),
        Jason.encode!(%{
          "source" => %{"pdf_sha256" => pdf_sha, "source_text_sha256" => text_sha},
          "document_metadata" => %{"title" => "Auto-map test"},
          "gall_records" => [
            %{
              "gall_maker" => %{
                "scientific_name" => "Andricus quercuscalifornicus",
                "authority" => "Bassett"
              }
            },
            %{"gall_maker" => %{"scientific_name" => "Nonexistent gallus impossibilis"}}
          ]
        })
      )

      File.write!(Path.join(bundle_dir, "source.pdf"), "fake-pdf-bytes")

      user = user_fixture()

      assert {:ok, %SourceIngestion{} = ingestion} =
               BundleImporter.import_bundle(bundle_dir, uploaded_by_id: user.id)

      [mapped, unmapped] = Ingestions.list_source_ingestion_species(ingestion.id)

      assert mapped.extracted_name == "Andricus quercuscalifornicus"
      assert mapped.status == "mapped"
      assert mapped.species_id == 100

      assert unmapped.extracted_name == "Nonexistent gallus impossibilis"
      assert unmapped.status == "pending"
      assert unmapped.species_id == nil

      File.rm_rf!(bundle_dir)
    end
  end

  describe "import_bundle/2 error cases" do
    test "returns error when review_artifact.json is missing" do
      bundle_dir =
        Path.join(
          System.tmp_dir!(),
          "bundle_importer_missing_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(bundle_dir)
      File.write!(Path.join(bundle_dir, "source.pdf"), "fake-pdf-bytes")

      user = user_fixture()

      assert {:error, {:missing_file, "review_artifact.json"}} =
               BundleImporter.import_bundle(bundle_dir, uploaded_by_id: user.id)

      File.rm_rf!(bundle_dir)
    end

    test "returns error when review_artifact.json is malformed" do
      bundle_dir =
        Path.join(
          System.tmp_dir!(),
          "bundle_importer_malformed_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(bundle_dir)
      File.write!(Path.join(bundle_dir, "review_artifact.json"), "{not valid json")
      File.write!(Path.join(bundle_dir, "source.pdf"), "fake-pdf-bytes")

      user = user_fixture()

      assert {:error, {:invalid_json, _}} =
               BundleImporter.import_bundle(bundle_dir, uploaded_by_id: user.id)

      File.rm_rf!(bundle_dir)
    end
  end

  # --- Helpers ---

  defp expected_record_count("cuesta"), do: 18
  defp expected_record_count("cook"), do: 2
  defp expected_record_count("mutun"), do: 21
  defp expected_record_count("nicholls"), do: 13

  defp insert_gall_species!(name) do
    {:ok, species} =
      %Species{name: name, taxoncode: "gall", datacomplete: false}
      |> Repo.insert()

    species
  end

  defp build_bundle_dir!(records, opts \\ []) do
    bundle_dir =
      Path.join(
        System.tmp_dir!(),
        "bundle_importer_automap_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(bundle_dir)

    pdf_sha = String.duplicate("a", 64)
    text_sha = String.duplicate("b", 64)
    title = Keyword.get(opts, :title, "Auto-map test")

    gall_records = Enum.map(records, fn record -> %{"gall_maker" => record} end)

    File.write!(
      Path.join(bundle_dir, "review_artifact.json"),
      Jason.encode!(%{
        "source" => %{"pdf_sha256" => pdf_sha, "source_text_sha256" => text_sha},
        "document_metadata" => %{"title" => title},
        "gall_records" => gall_records
      })
    )

    File.write!(Path.join(bundle_dir, "source.pdf"), "fake-pdf-bytes")
    bundle_dir
  end

  defp user_fixture do
    {:ok, user} =
      Accounts.create_user(%{
        auth0_id: "auth0|bundle-importer-#{System.unique_integer([:positive])}",
        display_name: "Bundle Importer Tester"
      })

    user
  end
end
