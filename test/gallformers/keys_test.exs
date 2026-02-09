defmodule Gallformers.KeysTest do
  use ExUnit.Case, async: true

  alias Gallformers.Keys

  describe "list_keys/0" do
    test "returns list of available keys" do
      keys = Keys.list_keys()
      assert is_list(keys)
      assert length(keys) >= 1

      key = Enum.find(keys, &(&1.slug == "oak-parasite-key"))
      assert key
      assert key.title =~ "parasitic wasps"
      assert is_list(key.authors)
    end
  end

  describe "get_key/1" do
    test "returns key data for valid slug" do
      assert {:ok, key} = Keys.get_key("oak-parasite-key")
      assert key.slug == "oak-parasite-key"
      assert key.title =~ "parasitic wasps"
      assert is_map(key.couplets)
      assert Map.has_key?(key.couplets, "1")
    end

    test "returns error for unknown slug" do
      assert {:error, :not_found} = Keys.get_key("nonexistent-key")
    end

    test "parses couplet structure correctly" do
      {:ok, key} = Keys.get_key("oak-parasite-key")
      couplet = key.couplets["1"]
      assert is_list(couplet.leads)
      assert length(couplet.leads) == 2

      lead = hd(couplet.leads)
      assert is_binary(lead.text)
      assert is_list(lead.images)
      assert is_map(lead.destination)
    end

    test "parses taxon destinations" do
      {:ok, key} = Keys.get_key("oak-parasite-key")
      couplet = key.couplets["4"]
      lead = hd(couplet.leads)
      assert lead.destination.type == "taxon"
      assert lead.destination.name == "Ichneumonidae"
    end

    test "parses couplet destinations" do
      {:ok, key} = Keys.get_key("oak-parasite-key")
      couplet = key.couplets["1"]
      lead = hd(couplet.leads)
      assert lead.destination.type == "couplet"
      assert lead.destination.number == "2"
    end
  end

  describe "couplet_numbers/1" do
    test "returns sorted couplet numbers" do
      {:ok, key} = Keys.get_key("oak-parasite-key")
      numbers = Keys.couplet_numbers(key)
      assert is_list(numbers)
      assert hd(numbers) == "1"
      # Numbers should be sorted numerically
      int_numbers = Enum.map(numbers, &String.to_integer/1)
      assert int_numbers == Enum.sort(int_numbers)
    end
  end
end
