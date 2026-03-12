defmodule Gallformers.Keys.CoupletsTypeContentImageTest do
  @moduledoc """
  Tests for content_image_id support in CoupletsType.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Keys.CoupletsType

  describe "content_image_id round-trip" do
    test "preserves content_image_id through cast and dump" do
      json = %{
        "1" => %{
          "leads" => [
            %{
              "text" => "Lead A",
              "images" => [%{"ref" => "Fig 1", "content_image_id" => 42}],
              "destination" => %{"type" => "couplet", "number" => "2"}
            },
            %{
              "text" => "Lead B",
              "destination" => %{"type" => "couplet", "number" => "2"}
            }
          ]
        },
        "2" => %{
          "leads" => [
            %{"text" => "Lead C", "destination" => %{"type" => "taxon", "name" => "Quercus"}},
            %{"text" => "Lead D", "destination" => %{"type" => "taxon", "name" => "Acer"}}
          ]
        }
      }

      {:ok, casted} = CoupletsType.cast(json)

      # Verify content_image_id is present in runtime format
      lead_a = hd(casted["1"].leads)
      assert hd(lead_a.images).content_image_id == 42

      # Dump and re-load should preserve it
      {:ok, dumped} = CoupletsType.dump(casted)
      {:ok, reloaded} = CoupletsType.load(dumped)

      lead_a_reloaded = hd(reloaded["1"].leads)
      assert hd(lead_a_reloaded.images).content_image_id == 42
    end

    test "handles images with only file (legacy format)" do
      json = %{
        "1" => %{
          "leads" => [
            %{
              "text" => "Lead A",
              "images" => [%{"ref" => "Fig 1", "file" => "img.jpg"}],
              "destination" => %{"type" => "couplet", "number" => "2"}
            },
            %{
              "text" => "Lead B",
              "destination" => %{"type" => "couplet", "number" => "2"}
            }
          ]
        },
        "2" => %{
          "leads" => [
            %{"text" => "C", "destination" => %{"type" => "taxon", "name" => "X"}},
            %{"text" => "D", "destination" => %{"type" => "taxon", "name" => "Y"}}
          ]
        }
      }

      {:ok, casted} = CoupletsType.cast(json)
      lead_a = hd(casted["1"].leads)
      image = hd(lead_a.images)

      assert image.file == "img.jpg"
      assert image.content_image_id == nil
    end

    test "does not include content_image_id key in dump when nil" do
      json = %{
        "1" => %{
          "leads" => [
            %{
              "text" => "Lead A",
              "images" => [%{"ref" => "Fig 1", "file" => "img.jpg"}],
              "destination" => %{"type" => "couplet", "number" => "2"}
            },
            %{
              "text" => "Lead B",
              "destination" => %{"type" => "couplet", "number" => "2"}
            }
          ]
        },
        "2" => %{
          "leads" => [
            %{"text" => "C", "destination" => %{"type" => "taxon", "name" => "X"}},
            %{"text" => "D", "destination" => %{"type" => "taxon", "name" => "Y"}}
          ]
        }
      }

      {:ok, casted} = CoupletsType.cast(json)
      {:ok, dumped} = CoupletsType.dump(casted)

      decoded = Jason.decode!(dumped)
      image_json = hd(hd(decoded["1"]["leads"])["images"])

      refute Map.has_key?(image_json, "content_image_id")
    end
  end
end
