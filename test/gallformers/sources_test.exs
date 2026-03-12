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

      assert Sources.has_sources?(species.id)
    end
  end
end
