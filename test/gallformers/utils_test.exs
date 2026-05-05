defmodule Gallformers.UtilsTest do
  use ExUnit.Case, async: true

  alias Gallformers.Utils

  describe "all_caps?/1" do
    test "returns true for all uppercase text" do
      assert Utils.all_caps?("HELLO WORLD") == true
    end

    test "returns false for all lowercase text" do
      refute Utils.all_caps?("hello world")
    end

    test "returns false for mixed case text" do
      refute Utils.all_caps?("Hello World")
    end

    test "returns false for single lowercase letter" do
      refute Utils.all_caps?("a")
    end

    test "returns true for single uppercase letter" do
      assert Utils.all_caps?("A") == true
    end

    test "returns false for empty string" do
      refute Utils.all_caps?("")
    end

    test "returns true for uppercase with numbers" do
      assert Utils.all_caps?("CHAPTER 1") == true
    end

    test "returns true for all uppercase with punctuation" do
      assert Utils.all_caps?("HELLO, WORLD!") == true
    end

    test "handles strings with only spaces" do
      refute Utils.all_caps?("   ")
    end

    test "handles strings with only special characters" do
      refute Utils.all_caps?("...!!!")
    end
  end

  describe "attr_value/2" do
    test "returns value for atom key when present" do
      assert Utils.attr_value(%{name: "John"}, :name) == "John"
    end

    test "returns value for string key when atom key not present" do
      assert Utils.attr_value(%{"name" => "Jane"}, :name) == "Jane"
    end

    test "returns nil when neither key is present" do
      assert Utils.attr_value(%{}, :name) == nil
    end

    test "prefers atom key over string key when both present" do
      assert Utils.attr_value(%{:name => "Atom", "name" => "String"}, :name) == "Atom"
    end

    test "preserves false values" do
      assert Utils.attr_value(%{active: false}, :active) == false
    end

    test "preserves 0 values" do
      assert Utils.attr_value(%{count: 0}, :count) == 0
    end

    test "preserves empty string values" do
      assert Utils.attr_value(%{note: ""}, :note) == ""
    end
  end

  describe "normalize_atom/1" do
    test "converts atom to string" do
      assert Utils.normalize_atom(:active) == "active"
    end

    test "returns string when given a string" do
      assert Utils.normalize_atom("active") == "active"
    end
  end

  describe "nested_value/3" do
    test "returns value for atom key when present" do
      assert Utils.nested_value(%{data: "value"}, :data, "default") == "value"
    end

    test "returns value for string key when atom key not present" do
      assert Utils.nested_value(%{"data" => "value"}, :data, "default") == "value"
    end

    test "returns default when key not present" do
      assert Utils.nested_value(%{}, :data, "default") == "default"
    end

    test "returns default for non-map input" do
      assert Utils.nested_value("not a map", :data, "default") == "default"
    end
  end

  describe "nested_integer/2" do
    test "returns integer value when present" do
      assert Utils.nested_integer(%{count: 42}, :count) == 42
    end

    test "converts string to integer" do
      assert Utils.nested_integer(%{"count" => "42"}, :count) == 42
    end

    test "returns nil when key not present" do
      assert Utils.nested_integer(%{}, :count) == nil
    end

    test "returns nil for empty string" do
      assert Utils.nested_integer(%{count: ""}, :count) == nil
    end

    test "returns nil for non-map input" do
      assert Utils.nested_integer("not a map", :count) == nil
    end
  end

  describe "normalize_indexed_values/1" do
    test "returns list as-is when given a list" do
      assert Utils.normalize_indexed_values([1, 2, 3]) == [1, 2, 3]
    end

    test "converts map with integer keys to sorted list" do
      assert Utils.normalize_indexed_values(%{2 => "b", 1 => "a", 3 => "c"}) == ["a", "b", "c"]
    end

    test "converts map with string keys to sorted list" do
      assert Utils.normalize_indexed_values(%{"2" => "b", "1" => "a"}) == ["a", "b"]
    end

    test "returns empty list for invalid input" do
      assert Utils.normalize_indexed_values("invalid") == []
    end

    test "handles empty map" do
      assert Utils.normalize_indexed_values(%{}) == []
    end
  end

  describe "normalize_string_list/1" do
    test "returns unique non-empty strings from list" do
      assert Utils.normalize_string_list(["a", "b", "a", "", nil]) == ["a", "b"]
    end

    test "wraps single string in list" do
      assert Utils.normalize_string_list("hello") == ["hello"]
    end

    test "returns empty list for empty string" do
      assert Utils.normalize_string_list("") == []
    end

    test "returns empty list for nil" do
      assert Utils.normalize_string_list(nil) == []
    end

    test "filters out non-string values" do
      assert Utils.normalize_string_list([1, 2, "hello"]) == ["hello"]
    end
  end

  describe "normalize_optional_string/1" do
    test "returns trimmed string when valid" do
      assert Utils.normalize_optional_string("  hello  ") == "hello"
    end

    test "returns nil for nil input" do
      assert Utils.normalize_optional_string(nil) == nil
    end

    test "returns nil for empty string" do
      assert Utils.normalize_optional_string("") == nil
    end

    test "returns nil for whitespace-only string" do
      assert Utils.normalize_optional_string("   ") == nil
    end
  end

  describe "normalize_optional_string/2" do
    test "returns fallback when string is empty" do
      assert Utils.normalize_optional_string("", "default") == "default"
    end

    test "returns fallback when string is whitespace" do
      assert Utils.normalize_optional_string("   ", "default") == "default"
    end

    test "returns trimmed string when valid" do
      assert Utils.normalize_optional_string("  hello  ", "default") == "hello"
    end

    test "returns fallback for nil with fallback" do
      assert Utils.normalize_optional_string(nil, "default") == "default"
    end

    test "returns fallback for non-binary value" do
      assert Utils.normalize_optional_string(123, "default") == "default"
    end
  end
end
