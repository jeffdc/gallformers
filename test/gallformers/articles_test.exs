defmodule Gallformers.ArticlesTest do
  @moduledoc """
  Unit tests for the Articles context.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Articles
  alias Gallformers.Articles.Article

  @valid_attrs %{
    title: "Test Article",
    author: "Test Author",
    content: "This is the article content."
  }

  @update_attrs %{
    title: "Updated Title",
    author: "Updated Author",
    content: "Updated content."
  }

  @invalid_attrs %{title: nil, author: nil, content: nil}

  # These tests own the articles table: the converted test database holds
  # the catalog migration's placeholder Article (gall-lookalikes).
  setup do
    Repo.delete_all(Article)
    :ok
  end

  defp create_article(attrs \\ %{}) do
    {:ok, article} = Articles.create_article(Map.merge(@valid_attrs, attrs))
    article
  end

  describe "list_articles/1" do
    test "returns empty list when no articles exist" do
      assert Articles.list_articles() == []
    end

    test "returns all articles" do
      article = create_article()
      assert [returned] = Articles.list_articles()
      assert returned.id == article.id
    end

    test "filters by published_only option" do
      _unpublished = create_article(%{title: "Unpublished"})
      published = create_article(%{title: "Published", is_published: true})

      assert [returned] = Articles.list_articles(published_only: true)
      assert returned.id == published.id
    end

    test "filters by tag" do
      _untagged = create_article(%{title: "Untagged"})
      tagged = create_article(%{title: "Tagged", tags: ["biology", "ecology"]})

      assert [returned] = Articles.list_articles(tag: "biology")
      assert returned.id == tagged.id
    end
  end

  describe "list_published_articles/0" do
    test "returns only published articles" do
      _unpublished = create_article(%{title: "Unpublished"})
      published = create_article(%{title: "Published", is_published: true})

      assert [returned] = Articles.list_published_articles()
      assert returned.id == published.id
    end
  end

  describe "get_article!/1" do
    test "returns article with given id" do
      article = create_article()
      assert Articles.get_article!(article.id).id == article.id
    end

    test "raises for non-existent id" do
      assert_raise Ecto.NoResultsError, fn ->
        Articles.get_article!(999_999)
      end
    end
  end

  describe "get_article_by_slug!/1" do
    test "returns article with given slug" do
      article = create_article()
      assert Articles.get_article_by_slug!(article.slug).id == article.id
    end

    test "raises for non-existent slug" do
      assert_raise Ecto.NoResultsError, fn ->
        Articles.get_article_by_slug!("nonexistent-slug")
      end
    end
  end

  describe "get_article_by_slug/1" do
    test "returns article with given slug" do
      article = create_article()
      assert Articles.get_article_by_slug(article.slug).id == article.id
    end

    test "returns nil for non-existent slug" do
      assert Articles.get_article_by_slug("nonexistent-slug") == nil
    end
  end

  describe "create_article/1" do
    test "creates article with valid data" do
      assert {:ok, %Article{} = article} = Articles.create_article(@valid_attrs)
      assert article.title == "Test Article"
      assert article.author == "Test Author"
      assert article.content == "This is the article content."
      assert article.is_published == false
      assert article.tags == []
    end

    test "auto-generates slug from title" do
      assert {:ok, %Article{} = article} = Articles.create_article(@valid_attrs)
      assert article.slug == "test-article"
    end

    test "uses provided slug if given" do
      attrs = Map.put(@valid_attrs, :slug, "custom-slug")
      assert {:ok, %Article{} = article} = Articles.create_article(attrs)
      assert article.slug == "custom-slug"
    end

    test "returns error with invalid data" do
      assert {:error, %Ecto.Changeset{}} = Articles.create_article(@invalid_attrs)
    end

    test "validates max length for title (boundary)" do
      long_title = String.duplicate("a", 201)

      attrs = %{
        title: long_title,
        author: "Test Author",
        content: "Content"
      }

      assert {:error, changeset} = Articles.create_article(attrs)
      assert "should be at most 200 character(s)" in errors_on(changeset).title
    end

    test "trims whitespace from strings (boundary)" do
      attrs = %{
        title: "  Test Title  ",
        author: "  Test Author  ",
        content: "  Content  ",
        description: "  Description  "
      }

      assert {:ok, article} = Articles.create_article(attrs)
      assert article.title == "Test Title"
      assert article.author == "Test Author"
      assert article.content == "Content"
      assert article.description == "Description"
    end

    test "rejects empty strings after trimming (boundary)" do
      attrs = %{
        title: "   ",
        author: "Test Author",
        content: "Content"
      }

      # Empty strings after trimming should fail required validation
      assert {:error, changeset} = Articles.create_article(attrs)
      assert "can't be blank" in errors_on(changeset).title
    end

    test "auto-generates unique slug on collision" do
      assert {:ok, article1} = Articles.create_article(@valid_attrs)
      assert article1.slug == "test-article"

      # Second article with same title gets a numbered slug
      assert {:ok, article2} = Articles.create_article(@valid_attrs)
      assert article2.slug == "test-article-2"

      # Third article gets the next number
      assert {:ok, article3} = Articles.create_article(@valid_attrs)
      assert article3.slug == "test-article-3"
    end

    test "stores tags as array" do
      attrs = Map.put(@valid_attrs, :tags, ["biology", "ecology"])
      assert {:ok, %Article{} = article} = Articles.create_article(attrs)
      assert article.tags == ["biology", "ecology"]
    end

    test "stores description" do
      attrs = Map.put(@valid_attrs, :description, "A brief summary of the article.")
      assert {:ok, %Article{} = article} = Articles.create_article(attrs)
      assert article.description == "A brief summary of the article."
    end

    test "sets published_at when created as published" do
      attrs = Map.put(@valid_attrs, :is_published, true)
      assert {:ok, %Article{} = article} = Articles.create_article(attrs)
      assert article.is_published != nil
      assert article.published_at != nil
    end

    test "does not set published_at when created as draft" do
      assert {:ok, %Article{} = article} = Articles.create_article(@valid_attrs)
      assert article.is_published == false
      assert article.published_at == nil
    end
  end

  describe "update_article/2" do
    test "updates article with valid data" do
      article = create_article()
      assert {:ok, %Article{} = updated} = Articles.update_article(article, @update_attrs)
      assert updated.title == "Updated Title"
      assert updated.author == "Updated Author"
      assert updated.content == "Updated content."
    end

    test "returns error with invalid data" do
      article = create_article()
      assert {:error, %Ecto.Changeset{}} = Articles.update_article(article, @invalid_attrs)
    end

    test "sets published_at when transitioning from draft to published" do
      article = create_article(%{is_published: false})
      assert article.published_at == nil

      {:ok, updated} = Articles.update_article(article, %{is_published: true})
      assert updated.is_published != nil
      assert updated.published_at != nil
    end

    test "does not change published_at when already published" do
      {:ok, article} = Articles.create_article(Map.put(@valid_attrs, :is_published, true))
      original_published_at = article.published_at

      # Wait a tiny bit to ensure timestamps would differ
      :timer.sleep(10)

      {:ok, updated} = Articles.update_article(article, %{title: "New Title"})
      assert updated.published_at == original_published_at
    end

    test "does not set published_at when remaining as draft" do
      article = create_article(%{is_published: false})
      {:ok, updated} = Articles.update_article(article, %{title: "New Title"})
      assert updated.published_at == nil
    end
  end

  describe "delete_article/1" do
    test "deletes the article" do
      article = create_article()
      assert {:ok, %Article{}} = Articles.delete_article(article)
      assert_raise Ecto.NoResultsError, fn -> Articles.get_article!(article.id) end
    end

    test "cascade deletes content images from DB" do
      article = create_article()

      {:ok, _img} =
        Gallformers.ContentImages.finalize_upload(
          "articles/#{article.id}/test.jpg",
          :article,
          article.id,
          "tester"
        )

      assert length(Gallformers.ContentImages.list_images_for_article(article.id)) == 1

      assert {:ok, _} = Articles.delete_article(article)
      assert Gallformers.ContentImages.list_images_for_article(article.id) == []
    end
  end

  describe "change_article/2" do
    test "returns a changeset" do
      article = create_article()
      assert %Ecto.Changeset{} = Articles.change_article(article)
    end
  end

  describe "list_related_articles/2" do
    test "returns empty list when article has no tags" do
      article = create_article(%{tags: []})
      assert Articles.list_related_articles(article) == []
    end

    test "returns articles with shared tags" do
      article1 = create_article(%{title: "Article 1", tags: ["biology"], is_published: true})

      article2 =
        create_article(%{title: "Article 2", tags: ["biology", "ecology"], is_published: true})

      _article3 = create_article(%{title: "Article 3", tags: ["botany"], is_published: true})

      related = Articles.list_related_articles(article1)
      assert length(related) == 1
      assert hd(related).id == article2.id
    end

    test "excludes the article itself" do
      article = create_article(%{title: "Article 1", tags: ["biology"], is_published: true})
      _article2 = create_article(%{title: "Article 2", tags: ["biology"], is_published: true})

      related = Articles.list_related_articles(article)
      refute Enum.any?(related, &(&1.id == article.id))
    end

    test "only returns published articles" do
      article = create_article(%{title: "Article 1", tags: ["biology"], is_published: true})

      _unpublished =
        create_article(%{title: "Unpublished", tags: ["biology"], is_published: false})

      related = Articles.list_related_articles(article)
      assert related == []
    end

    test "respects limit option" do
      article = create_article(%{title: "Article 1", tags: ["biology"], is_published: true})

      for i <- 2..10 do
        create_article(%{title: "Article #{i}", tags: ["biology"], is_published: true})
      end

      related = Articles.list_related_articles(article, limit: 3)
      assert length(related) == 3
    end
  end

  describe "list_tags/1" do
    test "returns empty list when no articles exist" do
      assert Articles.list_tags() == []
    end

    test "returns tags with counts" do
      create_article(%{title: "Article 1", tags: ["biology", "ecology"]})
      create_article(%{title: "Article 2", tags: ["biology", "botany"]})

      tags = Articles.list_tags()
      biology = Enum.find(tags, &(&1.tag == "biology"))
      ecology = Enum.find(tags, &(&1.tag == "ecology"))
      botany = Enum.find(tags, &(&1.tag == "botany"))

      assert biology.count == 2
      assert ecology.count == 1
      assert botany.count == 1
    end

    test "filters by published_only option" do
      create_article(%{title: "Draft", tags: ["draft-only"], is_published: false})
      create_article(%{title: "Published", tags: ["published-tag", "shared"], is_published: true})
      create_article(%{title: "Draft 2", tags: ["shared"], is_published: false})

      # Without filter, all tags included
      all_tags = Articles.list_tags()
      assert Enum.find(all_tags, &(&1.tag == "draft-only")).count == 1
      assert Enum.find(all_tags, &(&1.tag == "published-tag")).count == 1
      assert Enum.find(all_tags, &(&1.tag == "shared")).count == 2

      # With published_only, only tags from published articles
      published_tags = Articles.list_tags(published_only: true)
      assert Enum.find(published_tags, &(&1.tag == "draft-only")) == nil
      assert Enum.find(published_tags, &(&1.tag == "published-tag")).count == 1
      assert Enum.find(published_tags, &(&1.tag == "shared")).count == 1
    end
  end

  describe "Article.slugify/1" do
    test "converts to lowercase" do
      assert Article.slugify("Hello World") == "hello-world"
    end

    test "replaces spaces with hyphens" do
      assert Article.slugify("one two three") == "one-two-three"
    end

    test "removes special characters" do
      assert Article.slugify("Hello! World?") == "hello-world"
    end

    test "handles ampersands" do
      assert Article.slugify("Oaks & Their Galls") == "oaks-their-galls"
    end

    test "collapses multiple hyphens" do
      assert Article.slugify("hello   world") == "hello-world"
    end

    test "trims leading and trailing hyphens" do
      assert Article.slugify("  hello world  ") == "hello-world"
    end
  end
end
