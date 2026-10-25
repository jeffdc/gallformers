defmodule Gallformers.CatalogMigration.Old do
  @moduledoc """
  Reads of today's model (`species`, `taxonomy`, `species_taxonomy`, ...)
  for the data migration. Only the migration reads the old tables this way
  (`9449` *Architecture*); they are left untouched.
  """

  alias Gallformers.Repo

  @doc "Runs `sql` and returns its rows as maps with atom keys."
  @spec rows(String.t(), list()) :: [map()]
  def rows(sql, params \\ []) do
    %{columns: columns, rows: rows} = Repo.query!(sql, params, timeout: :infinity)
    keys = Enum.map(columns, &String.to_atom/1)
    Enum.map(rows, &(keys |> Enum.zip(&1) |> Map.new()))
  end

  @doc "A single count."
  @spec count(String.t(), list()) :: non_neg_integer()
  def count(sql, params \\ []) do
    %{rows: [[n]]} = Repo.query!(sql, params, timeout: :infinity)
    n
  end

  @doc "Every `taxonomy` row, by ID."
  @spec taxonomy() :: [map()]
  def taxonomy do
    rows("""
    SELECT id, name, description, type, rank, parent_id, is_placeholder
    FROM taxonomy ORDER BY id
    """)
  end

  @doc """
  The genus and section links (`species_taxonomy`) of the species with
  `taxoncode`, by species ID: `%{genus: taxonomy_id, section: taxonomy_id}`
  (either may be nil).
  """
  @spec links(String.t()) :: %{integer() => %{genus: integer() | nil, section: integer() | nil}}
  def links(taxoncode) do
    """
    SELECT st.species_id, st.taxonomy_id, t.type
    FROM species_taxonomy st
    JOIN taxonomy t ON t.id = st.taxonomy_id
    JOIN species s ON s.id = st.species_id
    WHERE s.taxoncode = $1 AND t.type IN ('genus', 'section')
    ORDER BY st.species_id, st.taxonomy_id
    """
    |> rows([taxoncode])
    |> Enum.reduce(%{}, fn %{species_id: id, taxonomy_id: taxonomy_id, type: type}, acc ->
      Map.update(
        acc,
        id,
        put_link(%{genus: nil, section: nil}, type, taxonomy_id),
        &put_link(&1, type, taxonomy_id)
      )
    end)
  end

  # The first link of each type wins (links are ordered by taxonomy ID).
  defp put_link(link, "genus", id), do: Map.update!(link, :genus, &(&1 || id))
  defp put_link(link, "section", id), do: Map.update!(link, :section, &(&1 || id))

  @doc "Plant species rows."
  @spec plants() :: [map()]
  def plants do
    rows("""
    SELECT id, name, genus_placeholder FROM species
    WHERE taxoncode = 'plant' ORDER BY id
    """)
  end

  @doc "Gall species rows with their `gall_traits` columns."
  @spec galls() :: [map()]
  def galls do
    rows("""
    SELECT s.id, s.name, s.datacomplete, s.abundance_id,
           COALESCE(gt.undescribed, false) AS undescribed, gt.gallformers_code, gt.detachable
    FROM species s
    LEFT JOIN gall_traits gt ON gt.species_id = s.id
    WHERE s.taxoncode = 'gall'
    ORDER BY s.id
    """)
  end
end
