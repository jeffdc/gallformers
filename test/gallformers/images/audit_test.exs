defmodule Gallformers.Images.AuditTest do
  @moduledoc """
  Unit tests for the Images.Audit module (orphan detection and management).
  """
  use Gallformers.DataCase, async: false

  alias Gallformers.Images.Audit

  describe "parse_species_id_from_path/1" do
    test "extracts species_id from valid gall path" do
      assert {:ok, 123} =
               Audit.parse_species_id_from_path("gall/123/123_1234567890_original.jpg")

      assert {:ok, 1} = Audit.parse_species_id_from_path("gall/1/1_1234567890_original.png")
      assert {:ok, 99_999} = Audit.parse_species_id_from_path("gall/99999/some_file.jpg")
    end

    test "returns error for non-gall paths" do
      assert {:error, :invalid_path} = Audit.parse_species_id_from_path("articles/1/image.jpg")
      assert {:error, :invalid_path} = Audit.parse_species_id_from_path("other/123/image.jpg")
    end

    test "returns error for invalid species_id" do
      assert {:error, :invalid_path} = Audit.parse_species_id_from_path("gall/abc/image.jpg")
      assert {:error, :invalid_path} = Audit.parse_species_id_from_path("gall/12.5/image.jpg")
    end

    test "returns error for malformed paths" do
      assert {:error, :invalid_path} = Audit.parse_species_id_from_path("gall")
      assert {:error, :invalid_path} = Audit.parse_species_id_from_path("")
      assert {:error, :invalid_path} = Audit.parse_species_id_from_path("image.jpg")
    end
  end

  describe "find_orphan_paths/1" do
    test "returns empty list for empty input" do
      assert [] = Audit.find_orphan_paths([])
    end

    test "identifies paths with non-existent species as orphans" do
      # Use a species ID that definitely doesn't exist
      s3_objects = [
        %{key: "gall/999999999/999999999_1234567890_original.jpg", last_modified: nil, size: 1000}
      ]

      orphans = Audit.find_orphan_paths(s3_objects)
      assert length(orphans) == 1
      assert hd(orphans).species_exists == false
    end
  end
end
