defmodule GallformersWeb.FactKey do
  @moduledoc """
  A Fact's key in the change-set contract (matter ec2c: `{:host, taxon_id}`,
  `{:trait, trait, value}` …), as a string for a page's events and element
  ids, and back. A name or value may hold colons: it is always the rest of
  the string.

      iex> GallformersWeb.FactKey.encode({:trait, "season", "spring"})
      "trait:season:spring"

      iex> GallformersWeb.FactKey.decode("host:7")
      {:ok, {:host, 7}}
  """

  @type t ::
          {:inducer, integer()}
          | {:host, integer()}
          | {:trait, String.t(), String.t()}
          | {:alias, String.t()}
          | {:range, :exclude | :only, integer()}
          | {:occurrence, integer()}

  @doc "The key as a string."
  @spec encode(t()) :: String.t()
  def encode({:inducer, id}), do: "inducer:#{id}"
  def encode({:host, id}), do: "host:#{id}"
  def encode({:trait, trait, value}), do: "trait:#{trait}:#{value}"
  def encode({:alias, name}), do: "alias:#{name}"
  def encode({:range, adjustment, place_id}), do: "range:#{adjustment}:#{place_id}"
  def encode({:occurrence, place_id}), do: "occurrence:#{place_id}"

  @doc """
  The key as a query parameter's value (`?fact=host:7`): its string, with
  what would end or join a parameter (`&`, `=`, `#`, `+`, spaces) escaped.
  """
  @spec param(t()) :: String.t()
  def param(key), do: key |> encode() |> URI.encode(&param_char?/1)

  defp param_char?(char), do: URI.char_unescaped?(char) and char not in ~c"&=#+"

  @doc "The key a string names, or `:error`."
  @spec decode(String.t()) :: {:ok, t()} | :error
  def decode("inducer:" <> id), do: with_id(id, &{:inducer, &1})
  def decode("host:" <> id), do: with_id(id, &{:host, &1})
  def decode("occurrence:" <> id), do: with_id(id, &{:occurrence, &1})
  def decode("alias:" <> name) when name != "", do: {:ok, {:alias, name}}

  def decode("trait:" <> rest) do
    case String.split(rest, ":", parts: 2) do
      [trait, value] when trait != "" and value != "" -> {:ok, {:trait, trait, value}}
      _ -> :error
    end
  end

  def decode("range:" <> rest) do
    case String.split(rest, ":", parts: 2) do
      [adj, id] when adj in ["exclude", "only"] ->
        with_id(id, &{:range, String.to_existing_atom(adj), &1})

      _ ->
        :error
    end
  end

  def decode(_), do: :error

  defp with_id(text, build) do
    case Integer.parse(text) do
      {id, ""} -> {:ok, build.(id)}
      _ -> :error
    end
  end
end
