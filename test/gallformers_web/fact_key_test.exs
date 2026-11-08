defmodule GallformersWeb.FactKeyTest do
  use ExUnit.Case, async: true

  alias GallformersWeb.FactKey

  doctest GallformersWeb.FactKey

  test "every key in the change-set contract goes to a string and back" do
    for key <- [
          {:inducer, 12},
          {:host, 7},
          {:trait, "season", "spring"},
          {:trait, "texture", "hairy, sticky"},
          {:alias, "Oak apple: the big one"},
          {:range, :exclude, 31},
          {:range, :only, 4},
          {:occurrence, 9}
        ] do
      assert key |> FactKey.encode() |> FactKey.decode() == {:ok, key}
    end
  end

  test "a string that isn't a key" do
    assert FactKey.decode("host:abc") == :error
    assert FactKey.decode("range:sideways:3") == :error
    assert FactKey.decode("nonsense") == :error
  end

  describe "param/1" do
    test "a key as a query parameter's value: what ends or joins a parameter is escaped" do
      assert GallformersWeb.FactKey.param({:host, 7}) == "host:7"
      assert GallformersWeb.FactKey.param({:trait, "season", "Spring"}) == "trait:season:Spring"
      assert GallformersWeb.FactKey.param({:alias, "oak apple"}) == "alias:oak%20apple"
      assert GallformersWeb.FactKey.param({:alias, "a&b=c#d+e"}) == "alias:a%26b%3Dc%23d%2Be"
    end

    test "it reads back as the key" do
      key = {:alias, "a&b=c#d+e oak"}

      assert key
             |> GallformersWeb.FactKey.param()
             |> URI.decode_www_form()
             |> GallformersWeb.FactKey.decode() ==
               {:ok, key}
    end
  end
end
