defmodule Gallformers.IngestionPipeline.Stages.LLMSupportTest do
  use Gallformers.DataCase, async: true

  alias Gallformers.IngestionPipeline.Stages.LLMSupport

  describe "strip_fenced_json/1" do
    test "returns raw JSON unchanged when no fences present" do
      json = ~s({"title":"Test","authors":[],"year":2024,"doi":null})
      assert LLMSupport.strip_fenced_json(json) == json
    end

    test "strips standard fenced JSON with newline after fence" do
      fenced = ~s(```json\n{"title":"Test","authors":[],"year":2024,"doi":null}\n```)

      assert LLMSupport.strip_fenced_json(fenced) ==
               ~s({"title":"Test","authors":[],"year":2024,"doi":null})
    end

    test "strips fenced JSON without newline after opening fence" do
      fenced = ~s(```json{"title":"Test","authors":[],"year":2024,"doi":null}```)

      assert LLMSupport.strip_fenced_json(fenced) ==
               ~s({"title":"Test","authors":[],"year":2024,"doi":null})
    end

    test "strips fenced JSON with space after opening fence" do
      fenced = ~s(```json {"title":"Test","authors":[],"year":2024,"doi":null} ```)

      assert LLMSupport.strip_fenced_json(fenced) ==
               ~s({"title":"Test","authors":[],"year":2024,"doi":null})
    end

    test "strips uppercase JSON fence" do
      fenced = ~s(```JSON\n{"title":"Test","authors":[],"year":2024,"doi":null}\n```)

      assert LLMSupport.strip_fenced_json(fenced) ==
               ~s({"title":"Test","authors":[],"year":2024,"doi":null})
    end

    test "strips mixed case JSON fence" do
      fenced = ~s(```Json\n{"title":"Test","authors":[],"year":2024,"doi":null}\n```)

      assert LLMSupport.strip_fenced_json(fenced) ==
               ~s({"title":"Test","authors":[],"year":2024,"doi":null})
    end

    test "strips fence with no language specifier" do
      fenced = ~s(```\n{"title":"Test","authors":[],"year":2024,"doi":null}\n```)

      assert LLMSupport.strip_fenced_json(fenced) ==
               ~s({"title":"Test","authors":[],"year":2024,"doi":null})
    end

    test "handles no closing fence" do
      fenced = ~s(```json\n{"title":"Test","authors":[],"year":2024,"doi":null})

      assert LLMSupport.strip_fenced_json(fenced) ==
               ~s({"title":"Test","authors":[],"year":2024,"doi":null})
    end

    test "trims whitespace from extracted JSON" do
      fenced = ~s(  ```json\n  {"title":"Test"}  \n```  )
      assert LLMSupport.strip_fenced_json(fenced) == ~s({"title":"Test"})
    end

    test "handles leading commentary before fenced JSON" do
      input = ~s(Here is the metadata you requested:\n```json\n{"title":"Test"}\n```)
      assert LLMSupport.strip_fenced_json(input) == ~s({"title":"Test"})
    end
  end

  describe "extract_json_array/1" do
    test "parses raw JSON array" do
      json = ~s([{"name": "Test"}, {"name": "Test2"}])

      assert {:ok, [%{"name" => "Test"}, %{"name" => "Test2"}]} =
               LLMSupport.extract_json_array(json)
    end

    test "parses fenced JSON array" do
      fenced = ~s(```json\n[{"name": "Test"}, {"name": "Test2"}]\n```)

      assert {:ok, [%{"name" => "Test"}, %{"name" => "Test2"}]} =
               LLMSupport.extract_json_array(fenced)
    end

    test "handles preamble before JSON array" do
      input = ~s(Here is the data:\n```json\n[{"name": "Test"}]\n```)
      assert {:ok, [%{"name" => "Test"}]} = LLMSupport.extract_json_array(input)
    end

    test "handles single object as array" do
      json = ~s({"name": "Test"})
      assert {:ok, [%{"name" => "Test"}]} = LLMSupport.extract_json_array(json)
    end

    test "recovers from truncated JSON array - single complete object" do
      # Simulates LLM truncation mid-second object
      truncated = ~s([{"name": "Test"}, {"name": "Incomplete)
      assert {:ok, [%{"name" => "Test"}]} = LLMSupport.extract_json_array(truncated)
    end

    test "recovers from truncated JSON array - multiple complete objects" do
      # Simulates LLM truncation after several complete objects
      truncated = ~s([{"id": 1}, {"id": 2}, {"id": 3, "name": "Inc)
      assert {:ok, [%{"id" => 1}, %{"id" => 2}]} = LLMSupport.extract_json_array(truncated)
    end

    test "recovers from fenced truncated JSON array" do
      truncated = ~s(```json\n[{"name": "Test"}, {"name": "Incomplete)
      assert {:ok, [%{"name" => "Test"}]} = LLMSupport.extract_json_array(truncated)
    end

    test "returns error for completely invalid JSON" do
      invalid = ~s(not json at all)
      assert {:error, :invalid_json} = LLMSupport.extract_json_array(invalid)
    end

    test "handles empty array" do
      assert {:ok, []} = LLMSupport.extract_json_array(~s([]))
    end
  end

  describe "extract_json_object/1" do
    test "parses raw JSON object" do
      json = ~s({"title": "Test", "year": 2024})
      assert {:ok, %{"title" => "Test", "year" => 2024}} = LLMSupport.extract_json_object(json)
    end

    test "parses fenced JSON object" do
      fenced = ~s(```json\n{"title": "Test", "year": 2024}\n```)
      assert {:ok, %{"title" => "Test", "year" => 2024}} = LLMSupport.extract_json_object(fenced)
    end

    test "handles preamble before JSON object" do
      input = ~s(Here is the metadata:\n```json\n{"title": "Test", "year": 2024}\n```)
      assert {:ok, %{"title" => "Test", "year" => 2024}} = LLMSupport.extract_json_object(input)
    end

    test "recovers from truncated JSON object - closes with }" do
      # Truncated but structurally complete object
      truncated = ~s({"title": "Test", "year": 2024)
      assert {:ok, result} = LLMSupport.extract_json_object(truncated)
      assert result["title"] == "Test"
    end

    test "recovers from truncated JSON object with string value" do
      truncated = ~s({"title": "Incomplete string value)
      assert {:ok, result} = LLMSupport.extract_json_object(truncated)
      assert result["title"] == "Incomplete string value"
    end

    test "handles fenced truncated JSON object" do
      truncated = ~s(```json\n{"title": "Test", "year": 202)
      assert {:ok, result} = LLMSupport.extract_json_object(truncated)
      assert result["title"] == "Test"
    end

    test "returns error for completely invalid JSON" do
      invalid = ~s(not json at all)
      assert {:error, :invalid_json} = LLMSupport.extract_json_object(invalid)
    end
  end
end
