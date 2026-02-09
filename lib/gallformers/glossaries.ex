defmodule Gallformers.Glossaries do
  @moduledoc """
  The Glossaries context.

  Provides functions for working with glossary terms and definitions.
  """

  import Ecto.Query

  alias Gallformers.Glossaries.Glossary
  alias Gallformers.Repo

  @doc """
  Returns all glossary entries ordered alphabetically.
  """
  @spec list_glossary() :: [Glossary.t()]
  def list_glossary do
    from(g in Glossary,
      order_by: g.word
    )
    |> Repo.all()
  end

  @doc """
  Gets a glossary entry by ID.
  """
  @spec get_glossary(integer()) :: Glossary.t() | nil
  def get_glossary(id) do
    Repo.get(Glossary, id)
  end

  @doc """
  Gets a glossary entry by word.
  """
  @spec get_glossary_by_word(String.t()) :: Glossary.t() | nil
  def get_glossary_by_word(word) do
    from(g in Glossary,
      where: g.word == ^word
    )
    |> Repo.one()
  end

  @doc """
  Returns a map of word => definition for the given words.
  """
  @spec get_definitions(list(String.t())) :: %{String.t() => String.t()}
  def get_definitions(words) when is_list(words) and words != [] do
    from(g in Glossary,
      where: g.word in ^words,
      select: {g.word, g.definition}
    )
    |> Repo.all()
    |> Map.new()
  end

  def get_definitions(_), do: %{}

  @doc """
  Searches glossary entries by word (case-insensitive partial match).
  """
  @spec search_glossary(String.t()) :: [Glossary.t()]
  def search_glossary(query) do
    search_term = "%#{String.downcase(query)}%"

    from(g in Glossary,
      where:
        fragment("lower(?) LIKE ?", g.word, ^search_term) or
          fragment("lower(?) LIKE ?", g.definition, ^search_term),
      order_by: g.word
    )
    |> Repo.all()
  end

  @doc """
  Returns the count of glossary entries.
  """
  @spec count_glossary() :: integer()
  def count_glossary do
    from(g in Glossary,
      select: count(g.id)
    )
    |> Repo.one()
  end

  @doc """
  Returns glossary entries starting with a specific letter.
  """
  @spec list_glossary_by_letter(String.t()) :: [Glossary.t()]
  def list_glossary_by_letter(letter) do
    pattern = "#{String.downcase(letter)}%"

    from(g in Glossary,
      where: fragment("lower(?) LIKE ?", g.word, ^pattern),
      order_by: g.word
    )
    |> Repo.all()
  end

  @doc """
  Returns a map of first letters to counts for navigation.
  """
  @spec get_letter_counts() :: %{String.t() => integer()}
  def get_letter_counts do
    from(g in Glossary,
      group_by: fragment("upper(substr(word, 1, 1))"),
      select: {fragment("upper(substr(word, 1, 1))"), count(g.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # Admin functions

  @doc """
  Returns a changeset for tracking glossary changes.
  """
  @spec change_glossary(Glossary.t(), map()) :: Ecto.Changeset.t()
  def change_glossary(%Glossary{} = glossary, attrs \\ %{}) do
    Glossary.changeset(glossary, attrs)
  end

  @doc """
  Creates a glossary entry.
  """
  @spec create_glossary(map()) :: {:ok, Glossary.t()} | {:error, Ecto.Changeset.t()}
  def create_glossary(attrs \\ %{}) do
    %Glossary{}
    |> Glossary.changeset(attrs)
    |> Repo.insert()
    |> broadcast(:glossary_created)
  end

  @doc """
  Updates a glossary entry.
  """
  @spec update_glossary(Glossary.t(), map()) :: {:ok, Glossary.t()} | {:error, Ecto.Changeset.t()}
  def update_glossary(%Glossary{} = glossary, attrs) do
    glossary
    |> Glossary.changeset(attrs)
    |> Repo.update()
    |> broadcast(:glossary_updated)
  end

  @doc """
  Deletes a glossary entry.
  """
  @spec delete_glossary(Glossary.t()) :: {:ok, Glossary.t()} | {:error, Ecto.Changeset.t()}
  def delete_glossary(%Glossary{} = glossary) do
    Repo.delete(glossary)
    |> broadcast(:glossary_deleted)
  end

  @doc """
  Gets a glossary entry by ID, raising if not found.
  """
  @spec get_glossary!(integer()) :: Glossary.t()
  def get_glossary!(id) do
    Repo.get!(Glossary, id)
  end

  @doc """
  Subscribes to glossary changes.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Gallformers.PubSub, "glossary")
  end

  defp broadcast({:ok, glossary}, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, "glossary", {event, glossary})
    {:ok, glossary}
  end

  defp broadcast({:error, changeset}, _event) do
    {:error, changeset}
  end
end
