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
end
