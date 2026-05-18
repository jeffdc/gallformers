defmodule GallformersWeb.Admin.IngestionReviewLive.PresenterTest do
  use Gallformers.DataCase, async: true

  alias GallformersWeb.Admin.IngestionReviewLive.Presenter

  alias Gallformers.Accounts
  alias Gallformers.Ingestions

  describe "source_ingestion_review_view!/1 species entries" do
    test "keeps generation-suffixed species as separate entries (no collation)" do
      {:ok, user} =
        Accounts.create_user(%{
          auth0_id: "auth0|presenter-test-#{System.unique_integer([:positive])}",
          display_name: "Presenter Reviewer"
        })

      ingestion = review_ready_ingestion_fixture(%{uploaded_by_id: user.id})

      _entry_agamic =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Acraspis quercushirta (agamic)"
        })

      _entry_sexgen =
        source_ingestion_species_fixture(ingestion, 1, %{
          extracted_name: "Acraspis quercushirta (sexgen)"
        })

      review_view = Presenter.source_ingestion_review_view!(ingestion.id)
      entries = review_view.species_entries

      assert length(entries) == 2

      names = Enum.map(entries, & &1.extracted_name)
      assert "Acraspis quercushirta (agamic)" in names
      assert "Acraspis quercushirta (sexgen)" in names
    end

    test "filters out entries with nil or empty extracted_name" do
      {:ok, user} =
        Accounts.create_user(%{
          auth0_id: "auth0|presenter-test-#{System.unique_integer([:positive])}",
          display_name: "Presenter Reviewer"
        })

      ingestion = review_ready_ingestion_fixture(%{uploaded_by_id: user.id})

      _named =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Andricus paradoxus"
        })

      _nil_named =
        source_ingestion_species_fixture(ingestion, 1, %{
          extracted_name: nil
        })

      _empty_named =
        source_ingestion_species_fixture(ingestion, 2, %{
          extracted_name: ""
        })

      review_view = Presenter.source_ingestion_review_view!(ingestion.id)
      entries = review_view.species_entries

      assert length(entries) == 1
      assert hd(entries).extracted_name == "Andricus paradoxus"
    end

    test "returned entries do not carry a :sibling_ids key" do
      {:ok, user} =
        Accounts.create_user(%{
          auth0_id: "auth0|presenter-test-#{System.unique_integer([:positive])}",
          display_name: "Presenter Reviewer"
        })

      ingestion = review_ready_ingestion_fixture(%{uploaded_by_id: user.id})

      _entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Andricus paradoxus"
        })

      review_view = Presenter.source_ingestion_review_view!(ingestion.id)
      [entry] = review_view.species_entries

      refute Map.has_key?(entry, :sibling_ids)
    end

    test "review_view includes normalized_text from the source ingestion" do
      {:ok, user} =
        Accounts.create_user(%{
          auth0_id: "auth0|presenter-test-#{System.unique_integer([:positive])}",
          display_name: "Presenter Reviewer"
        })

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: user.id,
          normalized_text: "Verbatim normalized source text for the workspace modal."
        })

      review_view = Presenter.source_ingestion_review_view!(ingestion.id)

      assert review_view.normalized_text ==
               "Verbatim normalized source text for the workspace modal."
    end
  end

  describe "load_existing_gall_data/1" do
    test "returns hosts, aliases, traits for a gall with associations" do
      # Species 100 (Andricus quercuscalifornicus) has:
      #   hosts: species 6 (Thymus alpinus), species 8 (Mentha arvensis)
      #   aliases: alias 3 (Oak Apple Gall Wasp)
      #   gall_traits: detachable=integral
      result = Presenter.load_existing_gall_data(100)

      assert is_map(result)
      assert length(result.hosts) == 2
      assert Enum.any?(result.hosts, &(&1.host_name == "Thymus alpinus")) == true
      assert Enum.any?(result.hosts, &(&1.host_name == "Mentha arvensis")) == true

      assert length(result.aliases) == 1
      assert hd(result.aliases).name == "Oak Apple Gall Wasp"

      assert is_map(result.traits)
    end

    test "returns empty collections for a gall with no associations" do
      # Species 102 (Callirhytis quercuspunctata) has no hosts, no aliases
      result = Presenter.load_existing_gall_data(102)

      assert is_map(result)
      assert result.hosts == []
      assert result.aliases == []
      assert is_map(result.traits)
    end

    test "returns nil for nil species_id" do
      assert Presenter.load_existing_gall_data(nil) == nil
    end

    test "includes description from species-source mapping when available" do
      # Create a source and species_source for species 100
      {:ok, source} =
        Gallformers.Sources.create_source(%{
          title: "Test Source",
          author: "Author",
          pubyear: "2026",
          link: "https://example.com",
          citation: "Test citation",
          license: "CC-BY",
          licenselink: "https://creativecommons.org/licenses/by/4.0/"
        })

      {:ok, _species_source} =
        Gallformers.Sources.create_species_source(%{
          species_id: 100,
          source_id: source.id,
          description: "A round gall on oak leaves."
        })

      result = Presenter.load_existing_gall_data(100)
      assert result.description == "A round gall on oak leaves."
    end
  end

  defp review_ready_ingestion_fixture(attrs) do
    merged =
      attrs
      |> Map.new()
      |> Map.put_new(:input_type, "pdf")
      |> Map.put_new(:status, "needs_review")
      |> Map.put_new(:processing_stage, "review")

    {:ok, ingestion} = Ingestions.create_source_ingestion(merged)
    ingestion
  end

  defp source_ingestion_species_fixture(source_ingestion, position, attrs) do
    default_payload = %{
      "hosts" => [%{"name" => "Quercus alba", "evidence" => "On Quercus alba twigs"}],
      "traits" => %{
        "shape" => %{"original" => "globular", "suggested" => ["globular"]}
      },
      "description_evidence" => [
        %{"text" => "Rounded woolly gall on oak twigs.", "page" => 3}
      ]
    }

    merged =
      attrs
      |> Map.new()
      |> Map.put_new(:source_ingestion_id, source_ingestion.id)
      |> Map.put_new(:position, position)
      |> Map.put_new(:status, "pending")
      |> Map.put_new(:extracted_name, "Gall #{position}")
      |> Map.put_new(:extracted_authority, "Author")
      |> Map.put_new(:description_prose, "Rounded woolly gall on oak twigs.")
      |> Map.put_new(:extraction_payload, default_payload)

    {:ok, source_ingestion_species} = Ingestions.create_source_ingestion_species(merged)
    source_ingestion_species
  end
end
