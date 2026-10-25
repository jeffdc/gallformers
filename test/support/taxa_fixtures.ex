defmodule Gallformers.TaxaFixtures do
  @moduledoc """
  Taxa for tests (`Gallformers.Taxa`). Every write is audited as
  `Gallformers.DataCase.test_actor/0`.
  """

  import Gallformers.DataCase, only: [test_actor: 0]

  alias Gallformers.Taxa

  @doc """
  Creates a taxon. Defaults: a curated species with a unique name and no
  parent. `attrs` may give `:parent` (a taxon) in place of `:parent_id`.
  """
  def taxon_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    attrs =
      case Map.pop(attrs, :parent) do
        {nil, attrs} -> attrs
        {parent, attrs} -> Map.put(attrs, :parent_id, parent.id)
      end

    defaults = %{
      rank: :species,
      origin: :curated,
      name: "Taxon #{System.unique_integer([:positive])}"
    }

    {:ok, taxon} = Taxa.create_taxon(test_actor(), Map.merge(defaults, attrs))
    taxon
  end
end
