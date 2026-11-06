defmodule Gallformers.KeysTest do
  use Gallformers.DataCase, async: true

  alias Gallformers.Keys
  alias Gallformers.Keys.Key
  alias Gallformers.Storage.Images, as: ImageStorage
  alias Gallformers.Storage.PDFKeys

  @valid_couplets Jason.encode!(%{
                    "1" => %{
                      "leads" => [
                        %{
                          "text" => "Lead A",
                          "images" => [],
                          "destination" => %{"type" => "couplet", "number" => "2"}
                        },
                        %{
                          "text" => "Lead B",
                          "images" => [],
                          "destination" => %{"type" => "taxon", "name" => "Species X"}
                        }
                      ]
                    },
                    "2" => %{
                      "leads" => [
                        %{
                          "text" => "Lead C",
                          "images" => [],
                          "destination" => %{"type" => "taxon", "name" => "Species Y"}
                        },
                        %{
                          "text" => "Lead D",
                          "images" => [],
                          "destination" => %{"type" => "taxon", "name" => "Species Z"}
                        }
                      ]
                    }
                  })

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        title: "Test Key",
        version: "2026-01-01",
        couplets: @valid_couplets
      },
      overrides
    )
  end

  describe "list_keys/0" do
    test "returns list of available keys" do
      {:ok, _key} = Keys.create_key(valid_attrs())
      keys = Keys.list_keys()
      assert is_list(keys)
      assert length(keys) >= 1

      key = Enum.find(keys, &(&1.slug == "test-key"))
      assert key != nil
      assert key.title == "Test Key"
    end

    test "counts each key's couplets" do
      {:ok, _key} = Keys.create_key(valid_attrs())
      key = Enum.find(Keys.list_keys(), &(&1.slug == "test-key"))
      assert key.couplet_count == 2
    end

    test "excludes couplets from results" do
      {:ok, _key} = Keys.create_key(valid_attrs())
      keys = Keys.list_keys()
      key = Enum.find(keys, &(&1.slug == "test-key"))
      refute Map.has_key?(key, :couplets)
    end
  end

  describe "get_key/1" do
    test "returns key data for valid slug" do
      {:ok, _key} = Keys.create_key(valid_attrs())
      assert {:ok, key} = Keys.get_key("test-key")
      assert key.slug == "test-key"
      assert key.title == "Test Key"
      assert is_map(key.couplets)
      assert Map.has_key?(key.couplets, "1") == true
    end

    test "returns error for unknown slug" do
      assert {:error, :not_found} = Keys.get_key("nonexistent-key")
    end

    test "parses couplet structure correctly" do
      {:ok, _key} = Keys.create_key(valid_attrs())
      {:ok, key} = Keys.get_key("test-key")
      couplet = key.couplets["1"]
      assert is_list(couplet.leads)
      assert length(couplet.leads) == 2

      lead = hd(couplet.leads)
      assert is_binary(lead.text)
      assert lead.text == "Lead A"
      assert is_list(lead.images)
      assert is_map(lead.destination)
    end

    test "parses taxon destinations" do
      {:ok, _key} = Keys.create_key(valid_attrs())
      {:ok, key} = Keys.get_key("test-key")
      couplet = key.couplets["1"]
      lead = Enum.at(couplet.leads, 1)
      assert lead.destination.type == "taxon"
      assert lead.destination.name == "Species X"
    end

    test "parses couplet destinations" do
      {:ok, _key} = Keys.create_key(valid_attrs())
      {:ok, key} = Keys.get_key("test-key")
      couplet = key.couplets["1"]
      lead = hd(couplet.leads)
      assert lead.destination.type == "couplet"
      assert lead.destination.number == "2"
    end
  end

  describe "couplet_numbers/1" do
    test "returns sorted couplet numbers" do
      {:ok, _key} = Keys.create_key(valid_attrs())
      {:ok, key} = Keys.get_key("test-key")
      numbers = Keys.couplet_numbers(key)
      assert numbers == ["1", "2"]
    end
  end

  describe "create_key/1" do
    test "creates a key with valid attributes" do
      assert {:ok, key} = Keys.create_key(valid_attrs())
      assert key.title == "Test Key"
      assert key.slug == "test-key"
      assert key.version == "2026-01-01"
      assert is_map(key.couplets)
    end

    test "auto-generates slug from title" do
      assert {:ok, key} = Keys.create_key(valid_attrs(%{title: "My Amazing Key!"}))
      assert key.slug == "my-amazing-key"
    end

    test "respects explicit slug" do
      assert {:ok, key} = Keys.create_key(valid_attrs(%{slug: "custom-slug"}))
      assert key.slug == "custom-slug"
    end

    test "ensures unique slugs" do
      {:ok, _first} = Keys.create_key(valid_attrs())
      {:ok, second} = Keys.create_key(valid_attrs(%{title: "Test Key"}))
      assert second.slug == "test-key-2"
    end

    test "returns error for missing required fields" do
      assert {:error, changeset} = Keys.create_key(%{})
      assert errors_on(changeset) |> Map.has_key?(:title)
      assert errors_on(changeset) |> Map.has_key?(:version)
      assert errors_on(changeset) |> Map.has_key?(:couplets)
    end
  end

  describe "update_key/2" do
    test "updates key attributes" do
      {:ok, key} = Keys.create_key(valid_attrs())
      assert {:ok, updated} = Keys.update_key(key, %{title: "Updated Title"})
      assert updated.title == "Updated Title"
    end
  end

  describe "delete_key/1" do
    test "deletes a key" do
      {:ok, key} = Keys.create_key(valid_attrs())
      assert {:ok, _deleted} = Keys.delete_key(key)
      assert {:error, :not_found} = Keys.get_key("test-key")
    end

    test "cascade deletes content images from DB" do
      {:ok, key} = Keys.create_key(valid_attrs())

      {:ok, _img} =
        Gallformers.ContentImages.finalize_upload(
          "keys/#{key.id}/test_original.png",
          :key,
          key.id,
          "tester"
        )

      assert length(Gallformers.ContentImages.list_images_for_key(key.id)) == 1

      assert {:ok, _} = Keys.delete_key(key)
      assert Gallformers.ContentImages.list_images_for_key(key.id) == []
    end
  end

  describe "Key.key_has_images?/1" do
    test "returns false when no leads have images" do
      {:ok, key} = Keys.create_key(valid_attrs())
      refute Key.key_has_images?(key)
    end

    test "returns true when a lead has images" do
      couplets_with_images =
        Jason.encode!(%{
          "1" => %{
            "leads" => [
              %{
                "text" => "Lead A",
                "images" => [%{"ref" => "img1", "file" => "img1.jpg", "caption" => nil}],
                "destination" => %{"type" => "taxon", "name" => "Species X"}
              },
              %{
                "text" => "Lead B",
                "images" => [],
                "destination" => %{"type" => "taxon", "name" => "Species Y"}
              }
            ]
          }
        })

      {:ok, key} = Keys.create_key(valid_attrs(%{couplets: couplets_with_images}))
      assert Key.key_has_images?(key) == true
    end
  end

  describe "Key.serialize/1" do
    test "serializes key struct to JSON string" do
      {:ok, key} = Keys.create_key(valid_attrs())
      json = Key.serialize(key)
      data = Jason.decode!(json)

      assert data["title"] == "Test Key"
      assert data["slug"] == "test-key"
      assert data["version"] == "2026-01-01"
      assert is_map(data["couplets"])
      assert Map.has_key?(data["couplets"], "1") == true
      assert Map.has_key?(data["couplets"], "2") == true
    end

    test "couplet leads have string-keyed maps" do
      {:ok, key} = Keys.create_key(valid_attrs())
      json = Key.serialize(key)
      data = Jason.decode!(json)

      lead = data["couplets"]["1"]["leads"] |> hd()
      assert lead["text"] == "Lead A"
      assert lead["destination"]["type"] == "couplet"
    end
  end

  describe "pdf_urls/1" do
    test "returns full URLs for a key's PDFs" do
      {:ok, key} = Keys.create_key(valid_attrs())
      urls = Keys.pdf_urls(key)

      assert urls == PDFKeys.public_urls(key)
    end
  end

  describe "PDFKeys.public_urls/1" do
    test "returns full URLs for key PDF storage objects" do
      {:ok, key} = Keys.create_key(valid_attrs())
      urls = PDFKeys.public_urls(key)

      assert urls.text_only == "#{ImageStorage.cdn_url()}/keys/test-key/test-key.pdf"

      assert urls.with_images ==
               "#{ImageStorage.cdn_url()}/keys/test-key/test-key-images.pdf"
    end
  end

  describe "CoupletsType validation" do
    test "rejects couplets without entry point" do
      bad_couplets =
        Jason.encode!(%{
          "2" => %{
            "leads" => [
              %{"text" => "A", "destination" => %{"type" => "taxon", "name" => "X"}},
              %{"text" => "B", "destination" => %{"type" => "taxon", "name" => "Y"}}
            ]
          }
        })

      assert {:error, changeset} = Keys.create_key(valid_attrs(%{couplets: bad_couplets}))
      errors = errors_on(changeset)
      assert errors[:couplets] != nil
    end

    test "rejects couplets with fewer than 2 leads" do
      bad_couplets =
        Jason.encode!(%{
          "1" => %{
            "leads" => [
              %{"text" => "Only one lead", "destination" => %{"type" => "taxon", "name" => "X"}}
            ]
          }
        })

      assert {:error, changeset} = Keys.create_key(valid_attrs(%{couplets: bad_couplets}))
      errors = errors_on(changeset)
      assert errors[:couplets] != nil
    end

    test "rejects dangling couplet references" do
      bad_couplets =
        Jason.encode!(%{
          "1" => %{
            "leads" => [
              %{
                "text" => "Goes to 99",
                "destination" => %{"type" => "couplet", "number" => "99"}
              },
              %{"text" => "Taxon", "destination" => %{"type" => "taxon", "name" => "X"}}
            ]
          }
        })

      assert {:error, changeset} = Keys.create_key(valid_attrs(%{couplets: bad_couplets}))
      errors = errors_on(changeset)
      assert errors[:couplets] != nil
    end
  end
end
