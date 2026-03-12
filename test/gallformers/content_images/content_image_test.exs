defmodule Gallformers.ContentImages.ContentImageTest do
  @moduledoc """
  Unit tests for ContentImage schema changeset validation.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.ContentImages.ContentImage

  setup do
    {:ok, article} =
      Gallformers.Articles.create_article(%{
        title: "Test Article",
        content: "Some content",
        author: "tester"
      })

    {:ok, key} =
      Gallformers.Keys.create_key(%{
        title: "Test Key",
        slug: "test-key",
        version: "1.0",
        couplets: %{"1" => %{"lead" => "test"}}
      })

    %{article: article, key: key}
  end

  describe "changeset/2" do
    test "valid with article_id and no key_id", %{article: article} do
      changeset =
        ContentImage.changeset(%ContentImage{}, %{
          path: "articles/#{article.id}/test.jpg",
          article_id: article.id,
          uploader: "testuser"
        })

      assert changeset.valid?
    end

    test "valid with key_id and no article_id", %{key: key} do
      changeset =
        ContentImage.changeset(%ContentImage{}, %{
          path: "keys/#{key.id}/test.jpg",
          key_id: key.id,
          uploader: "testuser"
        })

      assert changeset.valid?
    end

    test "invalid with both article_id and key_id", %{article: article, key: key} do
      changeset =
        ContentImage.changeset(%ContentImage{}, %{
          path: "test/path.jpg",
          article_id: article.id,
          key_id: key.id,
          uploader: "testuser"
        })

      refute changeset.valid?
      assert errors_on(changeset).article_id == ["cannot set both article_id and key_id"]
    end

    test "invalid with neither article_id nor key_id" do
      changeset =
        ContentImage.changeset(%ContentImage{}, %{
          path: "test/path.jpg",
          uploader: "testuser"
        })

      refute changeset.valid?
      assert errors_on(changeset).article_id == ["either article_id or key_id must be set"]
    end

    test "path is required", %{article: article} do
      changeset =
        ContentImage.changeset(%ContentImage{}, %{
          article_id: article.id,
          uploader: "testuser"
        })

      refute changeset.valid?
      assert errors_on(changeset).path == ["can't be blank"]
    end

    test "casts attribution fields", %{article: article} do
      changeset =
        ContentImage.changeset(%ContentImage{}, %{
          path: "articles/#{article.id}/test.jpg",
          article_id: article.id,
          creator: "Jane Doe",
          license: "CC-BY",
          licenselink: "https://creativecommons.org/licenses/by/4.0/",
          sourcelink: "https://example.com",
          attribution: "Photo by Jane Doe",
          caption: "A nice gall"
        })

      assert changeset.valid?
      assert get_change(changeset, :creator) == "Jane Doe"
      assert get_change(changeset, :license) == "CC-BY"
    end
  end
end
