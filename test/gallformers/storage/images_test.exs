defmodule Gallformers.Storage.ImagesTest do
  @moduledoc """
  Unit tests for image-specific storage helpers.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Gallformers.Storage.Images

  describe "generate_path/2" do
    test "lays a Gall's image out under its ID" do
      path = Images.generate_path({:gall, 42}, "jpg")
      assert path =~ ~r{^gall/42/42_\d+_\d+_original\.jpg$}
    end

    test "lays a taxon's image out the same way" do
      path = Images.generate_path({:taxon, 7}, ".png")
      assert path =~ ~r{^gall/7/7_\d+_\d+_original\.png$}
    end
  end

  describe "generate_content_image_path/4" do
    test "generates article path without _original suffix" do
      path = Images.generate_content_image_path("articles", 42, "jpg", has_variants: false)
      assert String.starts_with?(path, "articles/42/") == true
      assert String.ends_with?(path, ".jpg") == true
      refute String.contains?(path, "_original")
    end

    test "generates key path with _original suffix" do
      path = Images.generate_content_image_path("keys", 7, "png", has_variants: true)
      assert String.starts_with?(path, "keys/7/") == true
      assert String.ends_with?(path, ".png") == true
      assert String.contains?(path, "_original") == true
    end

    test "strips leading dot from extension" do
      path = Images.generate_content_image_path("articles", 1, ".jpg", has_variants: false)
      assert String.ends_with?(path, ".jpg") == true
      refute String.contains?(path, "..jpg")
    end

    test "generates unique paths on successive calls" do
      path1 = Images.generate_content_image_path("articles", 1, "jpg", has_variants: false)
      path2 = Images.generate_content_image_path("articles", 1, "jpg", has_variants: false)
      assert path1 != path2
    end
  end

  describe "variant_keys_for_path/2" do
    test "returns only the path when sizes is empty" do
      keys = Images.variant_keys_for_path("articles/42/123_456.jpg", [])
      assert keys == ["articles/42/123_456.jpg"]
    end

    test "returns original + variant keys when sizes provided" do
      keys = Images.variant_keys_for_path("keys/7/123_original.png", [:medium, :large])
      assert "keys/7/123_original.png" in keys
      assert "keys/7/123_medium.png" in keys
      assert "keys/7/123_large.png" in keys
      assert length(keys) == 3
    end
  end

  describe "generate_size_variants/2" do
    test "logs and returns an error when the original image cannot be fetched" do
      assert capture_log(fn ->
               assert {:error, _} =
                        Images.generate_size_variants(
                          "nonexistent/path/original.jpg",
                          medium: 800,
                          large: 1200
                        )
             end) =~ "Failed to generate size variants"
    end
  end

  describe "presigned_upload_url/2" do
    test "returns a presigned URL through the storage adapter" do
      assert {:ok, url} =
               Images.presigned_upload_url("articles/42/upload.jpg", "image/jpeg")

      assert url ==
               "https://example.test/mock-s3/gallformers-images-us-east-1/articles/42/upload.jpg?method=PUT"
    end
  end

  describe "public_url/1" do
    test "builds a CDN URL for an image path" do
      assert Images.public_url("keys/7/sample.jpg") ==
               "#{Images.cdn_url()}/keys/7/sample.jpg"
    end
  end
end
