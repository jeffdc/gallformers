defmodule Gallformers.Taxa.Rank do
  @moduledoc """
  Taxon ranks, highest first, as the import contract lists them
  (`priv/import/vocab/ranks.schema.json`): kingdom to form. A child ranks
  strictly below its parent in this order.
  """

  @contract Path.expand("../../../priv/import/vocab/ranks.schema.json", __DIR__)
  @external_resource @contract

  @ranks @contract
         |> File.read!()
         |> JSON.decode!()
         |> Map.fetch!("enum")
         |> Enum.map(&String.to_atom/1)
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

  @doc "Whether `rank` ranks strictly below `other`."
  @spec below?(t(), t()) :: boolean()
  def below?(rank, other), do: Map.fetch!(@positions, rank) > Map.fetch!(@positions, other)
end
