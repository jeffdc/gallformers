defmodule Gallformers.Articles.TagsType do
  @moduledoc """
  Custom Ecto type for storing tags as a JSON array in a text column.

  Handles serialization between Elixir lists and JSON strings.
  """
  use Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def cast(tags) when is_list(tags) do
    {:ok, Enum.map(tags, &to_string/1)}
  end

  def cast(tags) when is_binary(tags) do
    case Jason.decode(tags) do
      {:ok, list} when is_list(list) -> {:ok, list}
      _ -> :error
    end
  end

  def cast(nil), do: {:ok, []}
  def cast(_), do: :error

  @impl true
  def load(nil), do: {:ok, []}
  def load(""), do: {:ok, []}

  def load(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, list} when is_list(list) -> {:ok, list}
      _ -> {:ok, []}
    end
  end

  @impl true
  def dump(tags) when is_list(tags) do
    {:ok, Jason.encode!(tags)}
  end

  def dump(nil), do: {:ok, "[]"}
  def dump(_), do: :error

  @impl true
  def equal?(a, b), do: a == b

  @impl true
  def embed_as(_format), do: :self
end
