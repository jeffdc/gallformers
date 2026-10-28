defmodule Gallformers.Taxa.Rank do
  @moduledoc """
  Taxon ranks, highest first: kingdom to form. A child ranks strictly below
  its parent in this order. The import contract's
  `priv/import/vocab/ranks.schema.json` is generated from this list
  (`mix gallformers.import.vocab`).
  """

  @ranks [
    :kingdom,
    :subkingdom,
    :phylum,
    :subphylum,
    :class,
    :subclass,
    :infraclass,
    :superorder,
    :order,
    :suborder,
    :infraorder,
    :superfamily,
    :family,
    :subfamily,
    :tribe,
    :subtribe,
    :genus,
    :subgenus,
    :section,
    :species,
    :subspecies,
    :variety,
    :form
  ]
  @positions @ranks |> Enum.with_index() |> Map.new()

  @type t ::
          :kingdom
          | :subkingdom
          | :phylum
          | :subphylum
          | :class
          | :subclass
          | :infraclass
          | :superorder
          | :order
          | :suborder
          | :infraorder
          | :superfamily
          | :family
          | :subfamily
          | :tribe
          | :subtribe
          | :genus
          | :subgenus
          | :section
          | :species
          | :subspecies
          | :variety
          | :form

  @doc "Every rank, highest first."
  @spec all() :: [t()]
  def all, do: @ranks

  @doc "Species and the ranks below it (an organism, not a group)."
  @spec species_and_below() :: [t()]
  def species_and_below, do: [:species, :subspecies, :variety, :form]

  @doc "Whether `rank` ranks strictly below `other`."
  @spec below?(t(), t()) :: boolean()
  def below?(rank, other), do: Map.fetch!(@positions, rank) > Map.fetch!(@positions, other)
end
