defmodule Gallformers.Utils do
  @moduledoc """
  The seemingly project mandatory collection of utilities that have nowhere else to live.
  """
  use Boundary, exports: :all

  @doc """
  Tests to see if a string is all uppercase.
  """
  @spec all_caps?(String.t()) :: boolean
  def all_caps?(line) do
    upcased = String.upcase(line)
    downcased = String.downcase(line)
    line == upcased and line != downcased
  end

  @doc """
  Retrieves the value of an attribute from a map, falling back to a string key if the atom key is not present.
  """
  @spec attr_value(map(), atom() | String.t()) :: any()
  def attr_value(attrs, key) do
    # Look up by atom key first, then fall back to string key.
    # Explicitly checks for nil to preserve false/0/"" values.
    case Map.get(attrs, key) do
      nil -> Map.get(attrs, Atom.to_string(key))
      value -> value
    end
  end

  @doc """
  Normalizes an atom to a string.
  """
  @spec normalize_atom(atom() | String.t()) :: String.t()
  def normalize_atom(status) when is_atom(status), do: Atom.to_string(status)
  def normalize_atom(status) when is_binary(status), do: status

  @doc """
  Retrieves a nested value from a map, falling back to a string key if the atom key is not present.
  """
  @spec nested_value(map(), atom() | String.t(), any()) :: any()
  def nested_value(map, key, default) when is_map(map) do
    string_key =
      case key do
        value when is_atom(value) -> Atom.to_string(value)
        value when is_binary(value) -> value
      end

    case Map.get(map, key) do
      nil -> Map.get(map, string_key, default)
      value -> value
    end
  end

  def nested_value(_map, _key, default), do: default

  @doc """
  Retrieves a nested integer value from a map, falling back to nil if not present or invalid.
  """
  @spec nested_integer(map(), atom() | String.t()) :: integer() | nil
  def nested_integer(map, key) do
    case nested_value(map, key, nil) do
      value when is_integer(value) -> value
      value when is_binary(value) and value != "" -> String.to_integer(value)
      _ -> nil
    end
  end

  @doc """
  Normalizes a list or map of indexed values into a sorted list.
  """
  @spec normalize_indexed_values(value :: list() | map()) :: list()
  def normalize_indexed_values(values) when is_list(values), do: values

  def normalize_indexed_values(values) when is_map(values) do
    values
    |> Enum.map(fn {key, value} -> {parse_index_key(key), value} end)
    |> Enum.sort_by(fn {index, _value} -> index end)
    |> Enum.map(fn {_index, value} -> value end)
  end

  def normalize_indexed_values(_), do: []

  @doc """
  Normalizes a string or list of strings into a list of strings.
  """
  @spec normalize_string_list(value :: binary() | list()) :: list()
  def normalize_string_list(values) when is_list(values) do
    values
    |> Enum.flat_map(fn
      value when is_binary(value) and value != "" -> [value]
      _ -> []
    end)
    |> Enum.uniq()
  end

  def normalize_string_list(value) when is_binary(value) and value != "", do: [value]
  def normalize_string_list(_), do: []

  @doc """
  Normalizes an optional string value, returning `nil` if the value is `nil` or an empty string.
  """
  @spec normalize_optional_string(value :: binary() | nil) :: binary() | nil
  def normalize_optional_string(nil), do: nil

  def normalize_optional_string(value) when is_binary(value),
    do: normalize_optional_string(value, nil)

  def normalize_optional_string(value, fallback) when is_binary(value) do
    if String.trim(value) == "" do
      fallback
    else
      String.trim(value)
    end
  end

  def normalize_optional_string(_value, fallback), do: fallback

  defp parse_index_key(key) when is_integer(key), do: key
  defp parse_index_key(key) when is_binary(key), do: String.to_integer(key)
end
