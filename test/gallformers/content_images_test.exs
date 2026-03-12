defmodule Gallformers.ContentImagesTest do
  @moduledoc """
  Unit tests for the ContentImages context.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.ContentImages
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

  describe "finalize_upload/5" do
    test "creates record for article owner", %{article: article} do
      path = "articles/#{article.id}/123_456.jpg"

      assert {:ok, %ContentImage{} = image} =
               ContentImages.finalize_upload(path, :article, article.id, "testuser")

      assert image.path == path
      assert image.article_id == article.id
      assert image.key_id == nil
      assert image.uploader == "testuser"
    end

    test "creates record for key owner", %{key: key} do
      path = "keys/#{key.id}/123_456_original.png"

      assert {:ok, %ContentImage{} = image} =
               ContentImages.finalize_upload(path, :key, key.id, "testuser")

      assert image.path == path
      assert image.key_id == key.id
      assert image.article_id == nil
    end

    test "accepts extra metadata attrs", %{article: article} do
      path = "articles/#{article.id}/123_789.jpg"

      assert {:ok, image} =
               ContentImages.finalize_upload(path, :article, article.id, "testuser", %{
                 creator: "Jane Doe",
                 license: "CC-BY"
               })

      assert image.creator == "Jane Doe"
      assert image.license == "CC-BY"
    end

    test "assigns incrementing sort_order", %{article: article} do
      path1 = "articles/#{article.id}/1_1.jpg"
      path2 = "articles/#{article.id}/2_2.jpg"

      {:ok, img1} = ContentImages.finalize_upload(path1, :article, article.id, "testuser")
      {:ok, img2} = ContentImages.finalize_upload(path2, :article, article.id, "testuser")

      assert img2.sort_order > img1.sort_order
    end
  end

  describe "list_images_for_article/1" do
    test "returns images ordered by sort_order", %{article: article} do
      {:ok, _} =
        ContentImages.finalize_upload("articles/#{article.id}/a.jpg", :article, article.id, "t")

      {:ok, _} =
        ContentImages.finalize_upload("articles/#{article.id}/b.jpg", :article, article.id, "t")

      images = ContentImages.list_images_for_article(article.id)
      assert length(images) == 2
      assert Enum.at(images, 0).sort_order <= Enum.at(images, 1).sort_order
    end

    test "does not return images from other articles", %{article: article} do
      {:ok, other_article} =
        Gallformers.Articles.create_article(%{
          title: "Other Article",
          content: "Other content",
          author: "tester"
        })

      {:ok, _} =
        ContentImages.finalize_upload("articles/#{article.id}/a.jpg", :article, article.id, "t")

      {:ok, _} =
        ContentImages.finalize_upload(
          "articles/#{other_article.id}/b.jpg",
          :article,
          other_article.id,
          "t"
        )

      images = ContentImages.list_images_for_article(article.id)
      assert length(images) == 1
    end
  end

  describe "list_images_for_key/1" do
    test "returns images for key", %{key: key} do
      {:ok, _} = ContentImages.finalize_upload("keys/#{key.id}/a_original.png", :key, key.id, "t")

      images = ContentImages.list_images_for_key(key.id)
      assert length(images) == 1
    end
  end

  describe "get_image/1 and get_image!/1" do
    test "returns image by id", %{article: article} do
      {:ok, created} =
        ContentImages.finalize_upload("articles/#{article.id}/get.jpg", :article, article.id, "t")

      assert %ContentImage{} = ContentImages.get_image(created.id)
      assert %ContentImage{} = ContentImages.get_image!(created.id)
    end

    test "get_image returns nil for nonexistent id" do
      assert ContentImages.get_image(999_999) == nil
    end
  end

  describe "update_image/2" do
    test "updates metadata", %{article: article} do
      {:ok, image} =
        ContentImages.finalize_upload("articles/#{article.id}/upd.jpg", :article, article.id, "t")

      assert {:ok, updated} =
               ContentImages.update_image(image, %{
                 creator: "Updated Creator",
                 license: "CC-BY-SA",
                 lastchangedby: "admin"
               })

      assert updated.creator == "Updated Creator"
      assert updated.license == "CC-BY-SA"
    end
  end

  describe "delete_image/1" do
    test "removes from database", %{article: article} do
      {:ok, image} =
        ContentImages.finalize_upload("articles/#{article.id}/del.jpg", :article, article.id, "t")

      assert {:ok, _} = ContentImages.delete_image(image)
      assert ContentImages.get_image(image.id) == nil
    end
  end

  describe "delete_images/3" do
    test "batch deletes with owner validation", %{article: article} do
      {:ok, img1} =
        ContentImages.finalize_upload("articles/#{article.id}/d1.jpg", :article, article.id, "t")

      {:ok, img2} =
        ContentImages.finalize_upload("articles/#{article.id}/d2.jpg", :article, article.id, "t")

      assert {:ok, 2} = ContentImages.delete_images(:article, article.id, [img1.id, img2.id])
      assert ContentImages.list_images_for_article(article.id) == []
    end

    test "does not delete images belonging to different owner", %{article: article} do
      {:ok, other} =
        Gallformers.Articles.create_article(%{title: "Other", content: "c", author: "t"})

      {:ok, img} =
        ContentImages.finalize_upload("articles/#{other.id}/x.jpg", :article, other.id, "t")

      # Try to delete other article's image using our article's id
      assert {:ok, 0} = ContentImages.delete_images(:article, article.id, [img.id])
      # Image still exists
      assert ContentImages.get_image(img.id) != nil
    end
  end

  describe "reorder_images/3" do
    test "updates sort_order based on position", %{article: article} do
      {:ok, img1} =
        ContentImages.finalize_upload("articles/#{article.id}/r1.jpg", :article, article.id, "t")

      {:ok, img2} =
        ContentImages.finalize_upload("articles/#{article.id}/r2.jpg", :article, article.id, "t")

      # Reverse order
      assert :ok = ContentImages.reorder_images(:article, article.id, [img2.id, img1.id])

      reloaded1 = ContentImages.get_image!(img1.id)
      reloaded2 = ContentImages.get_image!(img2.id)
      assert reloaded2.sort_order < reloaded1.sort_order
    end
  end

  describe "copy_metadata/3" do
    test "copies attribution fields from source to targets", %{article: article} do
      {:ok, source} =
        ContentImages.finalize_upload(
          "articles/#{article.id}/src.jpg",
          :article,
          article.id,
          "t",
          %{
            creator: "Source Creator",
            license: "CC-BY",
            licenselink: "https://creativecommons.org/licenses/by/4.0/",
            sourcelink: "https://example.com",
            attribution: "Attribution notes",
            caption: "Source caption"
          }
        )

      {:ok, target} =
        ContentImages.finalize_upload("articles/#{article.id}/tgt.jpg", :article, article.id, "t")

      assert {:ok, 1} = ContentImages.copy_metadata(source.id, [target.id], "admin")

      updated = ContentImages.get_image!(target.id)
      assert updated.creator == "Source Creator"
      assert updated.license == "CC-BY"
      assert updated.caption == "Source caption"
      assert updated.lastchangedby == "admin"
    end

    test "returns error for nonexistent source", %{article: article} do
      {:ok, target} =
        ContentImages.finalize_upload("articles/#{article.id}/t2.jpg", :article, article.id, "t")

      assert {:error, :source_not_found} =
               ContentImages.copy_metadata(999_999, [target.id], "admin")
    end
  end

  describe "collect and delete S3 paths for article" do
    test "returns empty paths for article with no images", %{article: article} do
      assert {[], []} = ContentImages.collect_s3_paths_for_article(article.id)
    end

    test "delete_collected_s3_paths handles empty paths" do
      assert :ok = ContentImages.delete_collected_s3_paths({[], []})
    end
  end

  describe "collect and delete S3 paths for key" do
    test "returns empty paths for key with no images", %{key: key} do
      {paths, _sizes} = ContentImages.collect_s3_paths_for_key(key.id)
      assert paths == []
    end
  end
end
