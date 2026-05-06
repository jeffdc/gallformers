defmodule Gallformers.SourcesTest do
  @moduledoc """
  Unit tests for the Sources context.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Sources
  alias Gallformers.Species.Species

  describe "has_sources?/1" do
    test "returns false when species has no sources" do
      {:ok, species} =
        Repo.insert(%Species{
          name: "Sourceless species",
          taxoncode: "gall",
          datacomplete: false
        })

      refute Sources.has_sources?(species.id)
    end

    test "returns true when species has at least one source" do
      {:ok, species} =
        Repo.insert(%Species{
          name: "Sourced species",
          taxoncode: "gall",
          datacomplete: false
        })

      {:ok, source} =
        Sources.create_source(%{
          title: "Test Source",
          author: "Author",
          pubyear: "2024",
          link: "http://example.com",
          citation: "Test citation",
          license: "CC BY"
        })

      {:ok, _} =
        Sources.create_species_source(%{
          species_id: species.id,
          source_id: source.id,
          description: "",
          externallink: "",
          useasdefault: false
        })

      assert Sources.has_sources?(species.id) == true
    end
  end

  describe "create_species_source/1 default handling" do
    test "clears existing defaults when string params cast useasdefault to true" do
      species = insert_species("Create default cast species")
      source1 = insert_source("Create Default Source 1")
      source2 = insert_source("Create Default Source 2")

      {:ok, existing_default} =
        Sources.create_species_source(%{
          species_id: species.id,
          source_id: source1.id,
          useasdefault: true
        })

      assert existing_default.useasdefault == true

      assert {:ok, new_default} =
               Sources.create_species_source(%{
                 "species_id" => Integer.to_string(species.id),
                 "source_id" => Integer.to_string(source2.id),
                 "useasdefault" => "1"
               })

      refute Sources.get_species_source!(existing_default.id).useasdefault
      assert Sources.get_species_source!(new_default.id).useasdefault == true
    end

    test "returns changeset errors for malformed species_id instead of raising" do
      source = insert_source("Malformed Species Source")

      assert {:error, changeset} =
               Sources.create_species_source(%{
                 "species_id" => "not-an-int",
                 "source_id" => Integer.to_string(source.id),
                 "useasdefault" => "true"
               })

      assert changeset.errors[:species_id] != nil
    end
  end

  describe "update_species_source/2 default handling" do
    test "clears existing defaults when update params cast useasdefault to true" do
      species = insert_species("Update default cast species")
      source1 = insert_source("Update Default Source 1")
      source2 = insert_source("Update Default Source 2")

      {:ok, existing_default} =
        Sources.create_species_source(%{
          species_id: species.id,
          source_id: source1.id,
          useasdefault: true
        })

      {:ok, candidate} =
        Sources.create_species_source(%{
          species_id: species.id,
          source_id: source2.id,
          useasdefault: false
        })

      assert {:ok, updated_default} =
               Sources.update_species_source(candidate, %{
                 "useasdefault" => "1"
               })

      assert updated_default.useasdefault == true
      refute Sources.get_species_source!(existing_default.id).useasdefault
    end
  end

  defp insert_species(name) do
    {:ok, species} =
      Repo.insert(%Species{
        name: name,
        taxoncode: "gall",
        datacomplete: false
      })

    species
  end

  defp insert_source(title) do
    {:ok, source} =
      Sources.create_source(%{
        title: title,
        author: "Author",
        pubyear: "2024",
        link: "http://example.com",
        citation: "#{title} citation",
        license: "CC BY"
      })

    source
  end
end
