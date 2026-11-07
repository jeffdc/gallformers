defmodule GallformersWeb.TaxonomyURL do
  @moduledoc """
  Centralized URL builder for public taxonomy pages.

  Every place that builds a URL for a taxonomy record (family, genus,
  section, intermediate) should call through this module. This ensures
  the URL scheme is defined in one place and is changeable in one place.
  """
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Taxon
  alias Gallformers.Taxa.TreeBuilder

  @doc """
  Returns the public URL path for a taxonomy record, or nil if the
  record doesn't map to a public page.

  Accepts any map/struct with `:type` and `:name` fields (and `:rank`
  for intermediates).

  ## Examples

      iex> TaxonomyURL.public_path(%{type: "family", name: "Cynipidae"})
      "/family/Cynipidae"

      iex> TaxonomyURL.public_path(%{type: "intermediate", rank: "Subfamily", name: "Cynipinae"})
      "/subfamily/Cynipinae"

      iex> TaxonomyURL.public_path(%{type: "family", name: "Santalaceae (gall)"})
      "/family/Santalaceae%20(gall)"
  """
  @spec public_path(map()) :: String.t() | nil
  def public_path(%{type: "family", name: name}), do: "/family/#{URI.encode(name)}"
  def public_path(%{type: "genus", name: name}), do: "/genus/#{URI.encode(name)}"
  def public_path(%{type: "section", name: name}), do: "/section/#{URI.encode(name)}"

  def public_path(%{type: "intermediate", rank: rank, name: name})
      when rank not in [nil, ""],
      do: "/#{String.downcase(rank)}/#{URI.encode(name)}"

  # A taxon (`Gallformers.Taxa`): its rank is an atom.
  def public_path(%{rank: rank, name: name}) when is_atom(rank),
    do: TreeBuilder.rank_path(rank, name)

  def public_path(_), do: nil

  @ranks ~w(family subfamily tribe subtribe genus section)a

  @species_ranks ~w(species subspecies variety form)

  @doc """
  The public page of a taxon given as `%{id, name, rank, kingdom}` with the
  rank and kingdom as strings (a read model's row): a plant species,
  subspecies, variety or form's Host page; any other taxon at those ranks
  (an organism that induces Galls) its species page; a family's, tribe's,
  genus's or section's page; nil for a taxon with no page of its own (an
  order).

      iex> TaxonomyURL.taxon_path(%{id: 7, name: "Quercus alba", rank: "species", kingdom: "Plantae"})
      "/host/7"

      iex> TaxonomyURL.taxon_path(%{id: 8, name: "Andricus kingi", rank: "species", kingdom: "Animalia"})
      "/species/8"
  """
  @spec taxon_path(map()) :: String.t() | nil
  def taxon_path(%{id: id, rank: rank, kingdom: "Plantae"}) when rank in @species_ranks,
    do: "/host/#{id}"

  def taxon_path(%{id: id, rank: rank}) when rank in @species_ranks, do: species_path(id)

  def taxon_path(%{name: name, rank: rank}) when is_binary(rank) do
    case Enum.find(@ranks, &(Atom.to_string(&1) == rank)) do
      nil -> nil
      atom -> TreeBuilder.rank_path(atom, name)
    end
  end

  def taxon_path(_), do: nil

  @doc "The species page of the organism's taxon `id` (`GallformersWeb.SpeciesLive`)."
  @spec species_path(integer()) :: String.t()
  def species_path(id) when is_integer(id), do: "/species/#{id}"

  @doc """
  Where a Gall's Inducer (`%{taxon_id, name, rank}`, rank an atom) is
  shown, or edited with `edit: true`: at species rank or below its species
  page (in Edit mode); above (an undescribed Gall's genus) its rank page,
  and the taxonomy admin to edit it.
  """
  @spec inducer_path(%{taxon_id: integer(), name: String.t(), rank: atom()}, keyword()) ::
          String.t()
  def inducer_path(%{taxon_id: id, rank: rank} = inducer, opts \\ []) do
    species? = Atom.to_string(rank) in @species_ranks

    case {species?, Keyword.get(opts, :edit, false)} do
      {true, true} -> species_path(id) <> "?edit"
      {true, false} -> species_path(id)
      {false, true} -> "/admin/taxonomy/#{id}"
      {false, false} -> public_path(%{rank: rank, name: inducer.name}) || "/admin/taxonomy/#{id}"
    end
  end

  @doc """
  The old taxonomy ID in a numeric rank-page URL (`/genus/33`), mapped to
  its taxon's page through the crosswalk
  (`Gallformers.Taxa.get_by_legacy_id/2`), or nil.
  """
  @spec legacy_path(String.t()) :: String.t() | nil
  def legacy_path(id_str) do
    with %Taxon{} = taxon <- Taxa.get_by_legacy_id(:taxonomy, String.to_integer(id_str)) do
      public_path(%{rank: taxon.rank, name: Taxa.accepted_name(taxon)})
    end
  end

  @doc """
  Returns true if the string looks like a numeric ID (digits only).
  Used by taxonomy LiveViews to detect old ID-based URLs and redirect.
  """
  @spec numeric?(String.t()) :: boolean()
  def numeric?(s), do: Regex.match?(~r/^\d+$/, s)
end
