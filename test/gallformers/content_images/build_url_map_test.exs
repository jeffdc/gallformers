defmodule Gallformers.ContentImages.BuildUrlMapTest do
  @moduledoc """
  Tests for ContentImages.build_image_url_map/1.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.ContentImages
  alias Gallformers.Keys
  alias Gallformers.Storage

  setup do
    {:ok, key} =
      Keys.create_key(%{
        title: "URL Map Test Key",
        slug: "url-map-test",
        version: "1.0",
        couplets: %{"1" => %{"leads" => [%{"text" => "A"}, %{"text" => "B"}]}}
      })

    {:ok, key: key}
  end

  test "returns empty map for empty list" do
    assert ContentImages.build_image_url_map([]) == %{}
  end

  test "returns empty map for non-existent IDs" do
    assert ContentImages.build_image_url_map([999_999]) == %{}
  end

  test "resolves content_image IDs to CDN URLs", %{key: key} do
    {:ok, image} =
      ContentImages.finalize_upload(
        "keys/#{key.id}/12345_1_original.jpg",
        :key,
        key.id,
        "tester"
      )

    url_map = ContentImages.build_image_url_map([image.id])

    assert Map.has_key?(url_map, image.id)
    url = url_map[image.id]
    # Should use medium variant for key images
    assert String.contains?(url, "medium")
    assert String.starts_with?(url, Storage.cdn_url())
  end

  test "handles images without original in path", %{key: key} do
    {:ok, image} =
      ContentImages.finalize_upload(
        "keys/#{key.id}/simple.jpg",
        :key,
        key.id,
        "tester"
      )

    url_map = ContentImages.build_image_url_map([image.id])
    url = url_map[image.id]

    assert String.contains?(url, "simple.jpg")
    refute String.contains?(url, "medium")
  end
end
