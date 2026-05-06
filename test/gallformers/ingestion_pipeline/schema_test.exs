defmodule Gallformers.IngestionPipeline.SchemaTest do
  use ExUnit.Case, async: true

  alias Gallformers.IngestionPipeline.Schema

  describe "prompt_text/0" do
    test "renders schema as human-readable text" do
      prompt = Schema.prompt_text()

      assert String.contains?(prompt, "Data Schema") == true
      assert String.contains?(prompt, "gall_species") == true
      assert String.contains?(prompt, "host_species") == true
      assert String.contains?(prompt, "traits") == true
      assert String.contains?(prompt, "description") == true
      assert String.contains?(prompt, "confidence") == true

      # Trait vocabularies should be included
      assert String.contains?(prompt, ~s("shape":)) == true
      assert String.contains?(prompt, ~s("color":)) == true
      assert String.contains?(prompt, ~s("detachable":)) == true
    end

    test "includes all shape values" do
      prompt = Schema.prompt_text()
      assert String.contains?(prompt, "cluster") == true
      assert String.contains?(prompt, "conical") == true
      assert String.contains?(prompt, "cylindrical") == true
    end

    test "detachable values are listed" do
      prompt = Schema.prompt_text()
      assert String.contains?(prompt, "unknown") == true
      assert String.contains?(prompt, "integral") == true
    end

    test "multi-word vocab values render correctly" do
      prompt = Schema.prompt_text()
      assert String.contains?(prompt, "resinous dots") == true
      assert String.contains?(prompt, "underground (roots+)") == true
      assert String.contains?(prompt, "false chamber") == true
    end
  end

  describe "validate/1" do
    test "validates a minimal valid record" do
      record = [
        %{
          "gall_species" => %{"name" => "Andricus", "family" => "Cynipidae"},
          "host_species" => %{"name" => "Quercus"},
          "traits" => %{},
          "description" => "A gall",
          "confidence" => 0.85
        }
      ]

      assert {:ok, _} = Schema.validate(record)
    end

    test "validates a complete trait record" do
      record = [
        %{
          "gall_species" => %{
            "name" => "Andricus quercuscalifornicus",
            "authority" => "(Cole)",
            "family" => "Cynipidae",
            "order" => "Hymenoptera"
          },
          "host_species" => %{
            "name" => "Quercus lobata",
            "authority" => "Nee",
            "family" => "Fagaceae"
          },
          "traits" => %{
            "shape" => %{"original" => "globular", "suggested" => ["globular"]},
            "color" => %{"original" => "tan", "suggested" => ["tan"]},
            "texture" => %{"original" => nil, "suggested" => []},
            "detachable" => "unknown"
          },
          "description" => "Gall description",
          "location" => "California",
          "confidence" => 0.85
        }
      ]

      assert {:ok, validated} = Schema.validate(record)
      assert length(validated) == 1
    end

    test "returns error for missing required fields" do
      record = [%{"gall_species" => %{"name" => "Andricus"}}]

      assert {:error, :invalid_contract, errors} = Schema.validate(record)
      assert is_list(errors)
      assert Enum.any?(errors, &String.contains?(&1, "Required properties")) == true
    end

    test "returns error for invalid type" do
      record = [
        %{
          "gall_species" => %{"name" => "Andricus", "family" => "Cynipidae"},
          "host_species" => %{"name" => "Quercus"},
          "traits" => %{},
          "description" => "A gall",
          "confidence" => "not a number"
        }
      ]

      assert {:error, :invalid_contract, errors} = Schema.validate(record)
      assert Enum.any?(errors, &String.contains?(&1, "Type mismatch")) == true
    end

    test "returns error for confidence out of range" do
      record = [
        %{
          "gall_species" => %{"name" => "Andricus", "family" => "Cynipidae"},
          "host_species" => %{"name" => "Quercus"},
          "traits" => %{},
          "description" => "A gall",
          "confidence" => 1.5
        }
      ]

      assert {:error, :invalid_contract, errors} = Schema.validate(record)

      assert Enum.any?(errors, &String.contains?(&1, "Expected the value to be <= 1.0")) ==
               true
    end

    test "accepts out-of-vocabulary suggested values for human review" do
      record = [
        %{
          "gall_species" => %{"name" => "Andricus", "family" => "Cynipidae"},
          "host_species" => %{"name" => "Quercus"},
          "traits" => %{
            "shape" => %{"original" => "banana-like", "suggested" => ["banana"]}
          },
          "description" => "A gall",
          "confidence" => 0.8
        }
      ]

      assert {:ok, ^record} = Schema.validate(record)
    end

    test "returns error for non-list input" do
      assert {:error, :invalid_contract, ["Expected a list of records"]} =
               Schema.validate("not a list")

      assert {:error, :invalid_contract, ["Expected a list of records"]} = Schema.validate(nil)
    end
  end
end
